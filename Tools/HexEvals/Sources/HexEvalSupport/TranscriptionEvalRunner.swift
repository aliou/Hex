import Foundation
import HexCore
@preconcurrency import WhisperKit

public struct TranscriptionEvalResult: Sendable {
  public var rawTranscript: String
  public var transcriptionSeconds: Double
}

public actor TranscriptionEvalRunner {
  public static let shared = TranscriptionEvalRunner()

  private var whisperKit: WhisperKit?
  private var currentModel: String?

  public init() {}

  public func transcribe(
    audioPath: String,
    model: String,
    language: String? = nil
  ) async throws -> TranscriptionEvalResult {
    let audioURL = URL(fileURLWithPath: audioPath)
    try await ensureLoaded(model: model)
    guard let whisperKit else {
      throw NSError(
        domain: "HexEvals.TranscriptionEvalRunner",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "WhisperKit model is not loaded"]
      )
    }

    let options = DecodingOptions(
      language: language,
      detectLanguage: language == nil,
      chunkingStrategy: .vad
    )
    let start = ContinuousClock.now
    let results = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)
    return TranscriptionEvalResult(
      rawTranscript: results.map(\.text).joined(separator: " "),
      transcriptionSeconds: Self.seconds(since: start)
    )
  }

  private func ensureLoaded(model: String) async throws {
    if whisperKit != nil, currentModel == model { return }
    let modelFolder = modelPath(for: model)
    let tokenizerFolder = tokenizerPath(for: model)

    if !FileManager.default.fileExists(atPath: modelFolder.path) {
      let tempFolder = try await WhisperKit.download(
        variant: model,
        downloadBase: nil,
        useBackgroundSession: false,
        progressCallback: { _ in }
      )
      try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
      try moveContents(of: tempFolder, to: modelFolder)
    }

    let config = WhisperKitConfig(
      model: model,
      modelFolder: modelFolder.path,
      tokenizerFolder: tokenizerFolder,
      prewarm: false,
      load: true
    )
    whisperKit = try await WhisperKit(config)
    currentModel = model
  }

  private func modelPath(for model: String) -> URL {
    let sanitized = model.components(separatedBy: CharacterSet(charactersIn: "./\\")).joined(separator: "_")
    return (try! URL.hexModelsDirectory)
      .appendingPathComponent("argmaxinc")
      .appendingPathComponent("whisperkit-coreml")
      .appendingPathComponent(sanitized, isDirectory: true)
  }

  private func tokenizerPath(for model: String) -> URL {
    modelPath(for: model).appendingPathComponent("tokenizer", isDirectory: true)
  }

  private func moveContents(of sourceFolder: URL, to destinationFolder: URL) throws {
    let items = try FileManager.default.contentsOfDirectory(atPath: sourceFolder.path)
    for item in items {
      let source = sourceFolder.appendingPathComponent(item)
      let destination = destinationFolder.appendingPathComponent(item)
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.moveItem(at: source, to: destination)
    }
  }

  private static func seconds(since start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now)
    return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }
}
