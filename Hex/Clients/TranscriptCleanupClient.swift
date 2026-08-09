import Dependencies
import DependenciesMacros
import Foundation
import HexCore
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

private let cleanupLogger = HexLog.cleanup

struct TranscriptCleanupContext: Equatable, Sendable {
  var sourceAppName: String?
  var sourceAppBundleID: String?
  var includeAppContext: Bool
}

struct CleanupModelInfo: Equatable, Identifiable, Sendable {
  var displayName: String
  var internalName: String
  var size: String
  var storageSize: String
  var isDownloaded: Bool

  var id: String { internalName }
}

enum CleanupModels {
  static let gemma4E2B = "mlx-community/gemma-4-e2b-it-4bit"

  static let curated: [CleanupModelInfo] = [
    .init(
      displayName: "Gemma 4 E2B IT 4-bit",
      internalName: gemma4E2B,
      size: "2B",
      storageSize: "~1.5 GB",
      isDownloaded: false
    )
  ]
}

@DependencyClient
struct TranscriptCleanupClient {
  var cleanup: @Sendable (String, String, TranscriptCleanupContext) async throws -> String
  var prewarm: @Sendable (String) async throws -> Void
  var downloadModel: @Sendable (String, @escaping @Sendable (Progress) -> Void) async throws -> Void
  var deleteModel: @Sendable (String) async throws -> Void
  var isModelDownloaded: @Sendable (String) async -> Bool = { _ in false }
  var modelLocation: @Sendable (String) async -> URL?
}

extension TranscriptCleanupClient: DependencyKey {
  static var liveValue: Self {
    let live = TranscriptCleanupClientLive()
    return Self(
      cleanup: { try await live.cleanup(transcript: $0, modelID: $1, context: $2) },
      prewarm: { try await live.prewarm(modelID: $0) },
      downloadModel: { try await live.downloadModel($0, progress: $1) },
      deleteModel: { try await live.deleteModel($0) },
      isModelDownloaded: { await live.isModelDownloaded($0) },
      modelLocation: { await live.modelLocation($0) }
    )
  }
}

extension DependencyValues {
  var transcriptCleanup: TranscriptCleanupClient {
    get { self[TranscriptCleanupClient.self] }
    set { self[TranscriptCleanupClient.self] = newValue }
  }
}

actor TranscriptCleanupClientLive {
  private var modelContainer: ModelContainer?
  private var currentModelID: String?

  func prewarm(modelID: String) async throws {
    guard !modelID.isEmpty else { return }
    guard modelContainer == nil || currentModelID != modelID else { return }
    cleanupLogger.info("Prewarming cleanup model \(modelID)")
    _ = try await loadContainer(modelID: modelID) { _ in }
  }

  func cleanup(
    transcript: String,
    modelID: String,
    context: TranscriptCleanupContext
  ) async throws -> String {
    let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return transcript }

    let container = try await loadContainer(modelID: modelID) { _ in }
    let prompt = Self.prompt(for: trimmed, context: context)
    let input = UserInput(chat: [
      .system("You clean up dictated transcripts. Return only the final cleaned text. Do not explain."),
      .user(prompt),
    ])

    let maxTokens = Self.maxTokens(for: trimmed)
    let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0)
    let prepareStart = ContinuousClock.now
    let lmInput = try await container.prepare(input: input)
    let promptTokenCount = lmInput.text.tokens.size
    cleanupLogger.info("Prepared cleanup prompt tokens=\(promptTokenCount) seconds=\(Self.seconds(since: prepareStart), format: .fixed(precision: 2))")

    let generationStart = ContinuousClock.now
    let stream = try await container.generate(input: lmInput, parameters: parameters)
    var output = ""
    for await event in stream {
      if let chunk = event.chunk, !chunk.isEmpty {
        output += chunk
      }
    }
    cleanupLogger.info("Generated cleanup text length=\(output.count) seconds=\(Self.seconds(since: generationStart), format: .fixed(precision: 2))")

    let cleaned = Self.sanitize(output)
    return cleaned.isEmpty ? transcript : cleaned
  }

  func downloadModel(_ modelID: String, progress: @escaping @Sendable (Progress) -> Void) async throws {
    _ = try await resolveModel(modelID: modelID, useLatest: false, progress: progress)
  }

  func deleteModel(_ modelID: String) async throws {
    if currentModelID == modelID {
      modelContainer = nil
      currentModelID = nil
    }
    guard let directory = repoCacheDirectory(modelID) else { return }
    try FileManager.default.removeItem(at: directory)
  }

  func isModelDownloaded(_ modelID: String) async -> Bool {
    guard let snapshots = snapshotsDirectory(modelID) else { return false }
    guard let contents = try? FileManager.default.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil) else {
      return false
    }
    return contents.contains { snapshot in
      guard snapshot.hasDirectoryPath else { return false }
      let config = snapshot.appendingPathComponent("config.json")
      let tokenizer = snapshot.appendingPathComponent("tokenizer.json")
      let files = (try? FileManager.default.contentsOfDirectory(atPath: snapshot.path)) ?? []
      let hasWeights = files.contains { $0.hasSuffix(".safetensors") || $0.hasSuffix(".gguf") }
      return FileManager.default.fileExists(atPath: config.path)
        && FileManager.default.fileExists(atPath: tokenizer.path)
        && hasWeights
    }
  }

  func modelLocation(_ modelID: String) async -> URL? {
    repoCacheDirectory(modelID)
  }

  private func loadContainer(
    modelID: String,
    progress: @escaping @Sendable (Progress) -> Void
  ) async throws -> ModelContainer {
    if let modelContainer, currentModelID == modelID {
      return modelContainer
    }

    Memory.cacheLimit = 20 * 1024 * 1024
    let resolved = try await resolveModel(modelID: modelID, useLatest: false, progress: progress)
    let loadStart = ContinuousClock.now
    let container = try await LLMModelFactory.shared.loadContainer(
      from: resolved.modelDirectory,
      using: #huggingFaceTokenizerLoader()
    )
    cleanupLogger.info("Loaded cleanup model \(modelID) seconds=\(Self.seconds(since: loadStart), format: .fixed(precision: 2))")
    modelContainer = container
    currentModelID = modelID
    return container
  }

  private func resolveModel(
    modelID: String,
    useLatest: Bool,
    progress: @escaping @Sendable (Progress) -> Void
  ) async throws -> ResolvedModelConfiguration {
    let configuration = Self.configuration(for: modelID)
    let hubClient = try HubClient(cache: HubCache(location: .fixed(directory: URL.hexCleanupHuggingFaceCacheDirectory)))
    return try await resolve(
      configuration: configuration,
      from: #hubDownloader(hubClient),
      useLatest: useLatest,
      progressHandler: progress
    )
  }

  private func repoCacheDirectory(_ modelID: String) -> URL? {
    guard let escaped = Self.escapedRepoDirectoryName(modelID) else { return nil }
    return try? URL.hexCleanupHuggingFaceCacheDirectory.appendingPathComponent(escaped, isDirectory: true)
  }

  private func snapshotsDirectory(_ modelID: String) -> URL? {
    repoCacheDirectory(modelID)?.appendingPathComponent("snapshots", isDirectory: true)
  }

  private static func configuration(for modelID: String) -> ModelConfiguration {
    if modelID == CleanupModels.gemma4E2B {
      return LLMRegistry.gemma4_e2b_it_4bit
    }
    return ModelConfiguration(id: modelID, defaultPrompt: "", extraEOSTokens: ["<turn|>"])
  }

  private static func prompt(for transcript: String, context: TranscriptCleanupContext) -> String {
    var sections: [String] = [basePrompt]
    if context.includeAppContext {
      var lines = ["Current app context:"]
      if let sourceAppName = context.sourceAppName, !sourceAppName.isEmpty {
        lines.append("- App name: \(promptSafeContextValue(sourceAppName))")
      }
      if let sourceAppBundleID = context.sourceAppBundleID, !sourceAppBundleID.isEmpty {
        lines.append("- Bundle ID: \(promptSafeContextValue(sourceAppBundleID))")
      }
      sections.append(lines.joined(separator: "\n"))
    }
    sections.append("Transcript:\n\(transcript)")
    return sections.joined(separator: "\n\n")
  }

  private static let basePrompt = """
  You clean up dictated transcripts for direct paste.

  Output only the cleaned transcript. No explanation. No labels. No markdown unless the speaker clearly dictated it.

  Priority order:
  1. Preserve the original words and meaning.
  2. Improve readability with punctuation, capitalization, sentence boundaries, and paragraph breaks.
  3. Remove filler and obvious repeated words only when safe.

  Conservative editing rules:
  - Do not rewrite for style.
  - Do not summarize or shorten ideas.
  - Do not make the speaker sound more certain, formal, or polished than they are.
  - Do not add facts, examples, headings, bullets, names, or conclusions.
  - Do not correct an unclear word into a different word unless the correction is obvious from nearby words.
  - If a word, name, product, project, app, command, path, acronym, code symbol, or variable name is unclear, keep the exact spoken wording.
  - Never output two alternative spellings for the same term.

  Paragraph rules:
  - Use paragraph breaks for readability. Paragraph breaks do not require rewriting the text.
  - Under 80 words: usually one paragraph.
  - 80 to 180 words: split into 2 or 3 paragraphs if the speaker makes more than one point.
  - Over 180 words: split into multiple paragraphs.
  - Start a new paragraph at topic shifts, new points, examples, plan changes, questions, or conclusions.
  - Aim for 2 to 4 sentences per paragraph.
  - Do not put every sentence on its own line.
  """

  private static func maxTokens(for transcript: String) -> Int {
    let words = transcript.split { $0.isWhitespace || $0.isNewline }.count
    return min(max(128, words * 3 + 96), 2048)
  }

  private static func sanitize(_ output: String) -> String {
    output
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
  }

  private static func escapedRepoDirectoryName(_ modelID: String) -> String? {
    guard !modelID.isEmpty else { return nil }
    return "models--" + modelID.replacingOccurrences(of: "/", with: "--")
  }

  private static func promptSafeContextValue(_ value: String) -> String {
    value
      .components(separatedBy: .newlines)
      .joined(separator: " ")
      .prefix(120)
      .description
  }

  private static func seconds(since start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now)
    return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }
}
