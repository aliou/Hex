# Hex evals

CLI-only evals for Hex transcription and transcript cleanup.

Run from this directory:

```bash
swift test
```

Fixtures are local-only because they can contain private voice recordings and transcripts. Add them under `Fixtures/`; JSON and audio files there are ignored by git.

## Cleanup fixture

`Fixtures/cleanup/*.jsonl`:

```json
{"id":"profanity","rawTranscript":"this is fucking broken","expectedContains":["fucking"]}
```

Optional fields:

- `systemPrompt`
- `appName`
- `bundleID`
- `includeAppContext`
- `expectedContains`
- `expectedNotContains`

## Transcription fixture

`Fixtures/transcription/*.jsonl`:

```json
{"id":"api-401","audioPath":"Fixtures/audio/api-401.wav","model":"openai_whisper-small","language":"en","expectedContains":["401"]}
```

## End-to-end fixture

`Fixtures/end-to-end/*.jsonl`:

```json
{"id":"api-401","audioPath":"Fixtures/audio/api-401.wav","transcriptionModel":"openai_whisper-small","language":"en","expectedCleanedContains":["401"]}
```
