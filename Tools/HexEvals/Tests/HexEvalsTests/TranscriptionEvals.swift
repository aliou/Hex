import Foundation
import HexEvalSupport
import Testing

@Suite("Transcription evals")
struct TranscriptionEvals {
  @Test("local transcription fixtures")
  func localTranscriptionFixtures() async throws {
    let root = EvalCaseLoading.packageRoot()
    let cases = try EvalCaseLoading.loadJSONL(
      TranscriptionEvalCase.self,
      from: root.appending(path: "Fixtures/transcription")
    )
    guard !cases.isEmpty else {
      print("No transcription fixtures found. Add local JSONL files under Tools/HexEvals/Fixtures/transcription/.")
      return
    }

    for evalCase in cases {
      let audioPath = absolutePath(evalCase.audioPath, root: root)
      let result = try await TranscriptionEvalRunner.shared.transcribe(
        audioPath: audioPath,
        model: evalCase.model,
        language: evalCase.language
      )

      print("[transcription] \(evalCase.id): transcribed in \(result.transcriptionSeconds)s")
      assertContains(evalCase.expectedContains, in: result.rawTranscript, id: evalCase.id)
      assertDoesNotContain(evalCase.expectedNotContains, in: result.rawTranscript, id: evalCase.id)
    }
  }
}

func absolutePath(_ path: String, root: URL) -> String {
  if path.hasPrefix("/") { return path }
  return root.appending(path: path).path
}
