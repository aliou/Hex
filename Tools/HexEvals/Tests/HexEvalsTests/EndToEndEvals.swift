import Foundation
import HexCore
import HexEvalSupport
import Testing

@Suite("End-to-end evals")
struct EndToEndEvals {
  @Test("local end-to-end fixtures")
  func localEndToEndFixtures() async throws {
    let root = EvalCaseLoading.packageRoot()
    let cases = try EvalCaseLoading.loadJSONL(
      EndToEndEvalCase.self,
      from: root.appending(path: "Fixtures/end-to-end")
    )
    guard !cases.isEmpty else {
      print("No end-to-end fixtures found. Add local JSONL files under Tools/HexEvals/Fixtures/end-to-end/.")
      return
    }

    for evalCase in cases {
      let audioPath = absolutePath(evalCase.audioPath, root: root)
      let transcription = try await TranscriptionEvalRunner.shared.transcribe(
        audioPath: audioPath,
        model: evalCase.transcriptionModel,
        language: evalCase.language
      )
      assertContains(evalCase.expectedRawContains, in: transcription.rawTranscript, id: evalCase.id)

      let cleanup = try await CleanupEvalRunner.shared.clean(
        systemPrompt: evalCase.systemPrompt ?? TranscriptCleanupPrompt.system,
        rawTranscript: transcription.rawTranscript,
        appName: evalCase.appName,
        bundleID: evalCase.bundleID,
        includeAppContext: evalCase.includeAppContext ?? false
      )

      print("[end-to-end] \(evalCase.id): transcribed in \(transcription.transcriptionSeconds)s, cleaned in \(cleanup.generationSeconds)s")
      assertContains(evalCase.expectedCleanedContains, in: cleanup.output, id: evalCase.id)
      assertDoesNotContain(evalCase.expectedCleanedNotContains, in: cleanup.output, id: evalCase.id)
    }
  }
}
