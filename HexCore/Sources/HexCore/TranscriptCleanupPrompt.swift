public enum TranscriptCleanupPrompt {
  public static let system = """
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
  - Preserve blunt wording, emotional emphasis, and intensity. Do not soften or sanitize the speaker's tone.
  - Do not add facts, examples, headings, bullets, names, or conclusions.
  - Do not correct an unclear word into a different word unless the correction is obvious from nearby words.
  - Fix words or numbers that are obviously wrong from the local context, such as API/HTTP status codes: "four oh one", "four dot one", or "four zero one" should become "401" when the speaker is talking about HTTP/API responses.
  - If a word, name, product, project, app, command, path, acronym, code symbol, or variable name is unclear, keep the exact spoken wording.
  - Never output two alternative spellings for the same term.

  Self-correction rules:
  - If the speaker starts a phrase and immediately replaces it with a clearer phrase, keep the final phrase and remove the abandoned phrase.
  - Remove repeated setup words only when the final intent is clear. For example, "when we have the model when we have the cleanup enabled" should become "when we have the cleanup enabled".
  - Do not remove repeated words when they may be intentional emphasis or part of a list.

  Paragraph rules:
  - Use paragraph breaks for readability. Paragraph breaks do not require rewriting the text.
  - Under 80 words: usually one paragraph.
  - 80 to 180 words: split into 2 or 3 paragraphs if the speaker makes more than one point.
  - Over 180 words: split into multiple paragraphs.
  - Start a new paragraph at topic shifts, new points, examples, plan changes, questions, or conclusions.
  - Aim for 2 to 4 sentences per paragraph.
  - Do not put every sentence on its own line.
  """

  public static func userMessage(
    rawTranscript: String,
    appName: String?,
    bundleID: String?,
    includeAppContext: Bool
  ) -> String {
    var sections: [String] = []
    if includeAppContext {
      var lines = ["Current app context:"]
      if let appName, !appName.isEmpty {
        lines.append("- App name: \(promptSafeContextValue(appName))")
      }
      if let bundleID, !bundleID.isEmpty {
        lines.append("- Bundle ID: \(promptSafeContextValue(bundleID))")
      }
      sections.append(lines.joined(separator: "\n"))
    }
    sections.append("Transcript:\n\(rawTranscript)")
    return sections.joined(separator: "\n\n")
  }

  public static func promptSafeContextValue(_ value: String) -> String {
    value
      .components(separatedBy: .newlines)
      .joined(separator: " ")
      .prefix(120)
      .description
  }
}
