import Foundation

public enum EvalCaseLoading {
  public static func packageRoot(filePath: String = #filePath) -> URL {
    var url = URL(fileURLWithPath: filePath)
    while url.lastPathComponent != "HexEvals" && url.path != "/" {
      url.deleteLastPathComponent()
    }
    return url
  }

  public static func loadJSONL<T: Decodable>(
    _ type: T.Type,
    from directory: URL
  ) throws -> [T] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let files = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "jsonl" }
    .sorted { $0.path < $1.path }

    let decoder = JSONDecoder()
    var cases: [T] = []
    for file in files {
      let contents = try String(contentsOf: file, encoding: .utf8)
      for line in contents.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
        cases.append(try decoder.decode(T.self, from: Data(trimmed.utf8)))
      }
    }
    return cases
  }
}

public struct CleanupEvalCase: Codable, Sendable {
  public var id: String
  public var systemPrompt: String?
  public var rawTranscript: String
  public var appName: String?
  public var bundleID: String?
  public var includeAppContext: Bool?
  public var expectedOutput: String?
  public var expectedContains: [String]?
  public var expectedNotContains: [String]?
}

public struct TranscriptionEvalCase: Codable, Sendable {
  public var id: String
  public var audioPath: String
  public var model: String
  public var language: String?
  public var expectedOutput: String?
  public var expectedContains: [String]?
  public var expectedNotContains: [String]?
}

public struct EndToEndEvalCase: Codable, Sendable {
  public var id: String
  public var audioPath: String
  public var transcriptionModel: String
  public var language: String?
  public var systemPrompt: String?
  public var appName: String?
  public var bundleID: String?
  public var includeAppContext: Bool?
  public var expectedRawOutput: String?
  public var expectedCleanedOutput: String?
  public var expectedRawContains: [String]?
  public var expectedCleanedContains: [String]?
  public var expectedCleanedNotContains: [String]?
}
