# Hex evals

CLI-only evals for Hex transcription and transcript cleanup.

Run from this directory:

```bash
TMPDIR=/tmp xcodebuild test \
  -scheme HexEvals \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data
```

Use `xcodebuild`, not bare `swift test`, for evals that load MLX. MLX needs Xcode's build path to generate and copy its Metal library resources.

Fixtures are local-only because they can contain private voice recordings and transcripts. Add them under `Fixtures/`; JSON and audio files there are ignored by git.

## Cleanup fixture

`Fixtures/cleanup/*.jsonl`:

```json
{"id":"tone","rawTranscript":"this is really broken","expectedOutput":"This is really broken."}
```

Optional fields:

- `systemPrompt`
- `appName`
- `bundleID`
- `includeAppContext`
- `expectedOutput`
- `expectedContains`
- `expectedNotContains`

## Transcription fixture

`Fixtures/transcription/*.jsonl`:

```json
{"id":"api-401","audioPath":"Fixtures/audio/api-401.wav","model":"openai_whisper-small","language":"en","expectedOutput":"The API returned a 401."}
```

## End-to-end fixture

`Fixtures/end-to-end/*.jsonl`:

```json
{"id":"api-401","audioPath":"Fixtures/audio/api-401.wav","transcriptionModel":"openai_whisper-small","language":"en","expectedCleanedOutput":"The API returned a 401."}
```
