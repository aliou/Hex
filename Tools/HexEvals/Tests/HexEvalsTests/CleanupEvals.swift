import Foundation
import HexCore
import HexEvalSupport
import Testing

@Suite("Cleanup evals")
struct CleanupEvals {
  @Test("local cleanup fixtures")
  func localCleanupFixtures() async throws {
    let root = EvalCaseLoading.packageRoot()
    let cases = try EvalCaseLoading.loadJSONL(
      CleanupEvalCase.self,
      from: root.appending(path: "Fixtures/cleanup")
    )
    guard !cases.isEmpty else {
      print("No cleanup fixtures found. Add local JSONL files under Tools/HexEvals/Fixtures/cleanup/.")
      return
    }

    for evalCase in cases {
      let result = try await CleanupEvalRunner.shared.clean(
        systemPrompt: evalCase.systemPrompt ?? TranscriptCleanupPrompt.system,
        rawTranscript: evalCase.rawTranscript,
        appName: evalCase.appName,
        bundleID: evalCase.bundleID,
        includeAppContext: evalCase.includeAppContext ?? false
      )

      print("[cleanup] \(evalCase.id): generated in \(result.generationSeconds)s")
      assertContains(evalCase.expectedContains, in: result.output, id: evalCase.id)
      assertDoesNotContain(evalCase.expectedNotContains, in: result.output, id: evalCase.id)
    }
  }
}

func assertContains(_ expected: [String]?, in output: String, id: String) {
  for expected in expected ?? [] {
    #expect(output.localizedCaseInsensitiveContains(expected), "\(id) expected output to contain configured text")
  }
}

func assertDoesNotContain(_ forbidden: [String]?, in output: String, id: String) {
  for forbidden in forbidden ?? [] {
    #expect(!output.localizedCaseInsensitiveContains(forbidden), "\(id) expected output not to contain configured text")
  }
}
