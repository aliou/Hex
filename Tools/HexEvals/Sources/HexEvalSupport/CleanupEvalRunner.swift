import Foundation
import HexCore
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

public struct CleanupEvalResult: Sendable {
  public var output: String
  public var prepareSeconds: Double
  public var generationSeconds: Double
}

public actor CleanupEvalRunner {
  public static let shared = CleanupEvalRunner()

  private var modelContainer: ModelContainer?
  private var currentModelID: String?

  public init() {}

  public func clean(
    systemPrompt: String = TranscriptCleanupPrompt.system,
    rawTranscript: String,
    appName: String? = nil,
    bundleID: String? = nil,
    includeAppContext: Bool = false,
    modelID: String = "mlx-community/gemma-4-e2b-it-4bit"
  ) async throws -> CleanupEvalResult {
    let container = try await loadContainer(modelID: modelID)
    let userMessage = TranscriptCleanupPrompt.userMessage(
      rawTranscript: rawTranscript,
      appName: appName,
      bundleID: bundleID,
      includeAppContext: includeAppContext
    )
    let input = UserInput(chat: [
      .system(systemPrompt),
      .user(userMessage),
    ])

    let prepareStart = ContinuousClock.now
    let lmInput = try await container.prepare(input: input)
    let prepareSeconds = Self.seconds(since: prepareStart)

    let generationStart = ContinuousClock.now
    let stream = try await container.generate(
      input: lmInput,
      parameters: GenerateParameters(maxTokens: Self.maxTokens(for: rawTranscript), temperature: 0)
    )
    var output = ""
    for await event in stream {
      if let chunk = event.chunk, !chunk.isEmpty {
        output += chunk
      }
    }

    return CleanupEvalResult(
      output: Self.sanitize(output),
      prepareSeconds: prepareSeconds,
      generationSeconds: Self.seconds(since: generationStart)
    )
  }

  private func loadContainer(modelID: String) async throws -> ModelContainer {
    if let modelContainer, currentModelID == modelID { return modelContainer }

    Memory.cacheLimit = 20 * 1024 * 1024
    let configuration: ModelConfiguration = modelID == "mlx-community/gemma-4-e2b-it-4bit"
      ? LLMRegistry.gemma4_e2b_it_4bit
      : ModelConfiguration(id: modelID, defaultPrompt: "", extraEOSTokens: ["<turn|>"])
    let hubClient = try HubClient(cache: HubCache(location: .fixed(directory: URL.hexCleanupHuggingFaceCacheDirectory)))
    let resolved = try await resolve(
      configuration: configuration,
      from: #hubDownloader(hubClient),
      useLatest: false
    ) { _ in }
    let container = try await LLMModelFactory.shared.loadContainer(
      from: resolved.modelDirectory,
      using: #huggingFaceTokenizerLoader()
    )
    modelContainer = container
    currentModelID = modelID
    return container
  }

  private static func maxTokens(for transcript: String) -> Int {
    let words = transcript.split { $0.isWhitespace || $0.isNewline }.count
    return min(max(128, words * 3 + 96), 2048)
  }

  private static func sanitize(_ output: String) -> String {
    output
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
  }

  private static func seconds(since start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now)
    return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }
}
