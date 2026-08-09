# Hex — Voice → Text (personal fork)

Personal fork of [kitlangton/Hex](https://github.com/kitlangton/Hex). On-device voice-to-text for Apple Silicon Macs: press-and-hold a hotkey to transcribe and paste the result into whatever you're typing.

Built and installed from source:

```bash
bash scripts/install-local.sh
```

That builds a Release `.app`, ad-hoc signs it, quits any running copy, and installs it into `/Applications`.

## How it works

Hex supports two transcription engines:

- **Parakeet TDT v3** (default) via [FluidAudio](https://github.com/FluidInference/FluidAudio) — fast and multilingual.
- **Whisper** via [WhisperKit](https://github.com/argmaxinc/WhisperKit).

Two recording modes:

1. **Press-and-hold** the hotkey to record; release to transcribe.
2. **Double-tap** to lock recording; tap again to transcribe.

State management uses [Swift Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture).

## Development

```bash
# Build
xcodebuild -scheme Hex -configuration Release

# Unit tests (run from HexCore)
cd HexCore && swift test

# Open in Xcode
open Hex.xcodeproj
```

See `AGENTS.md` for fork-specific architecture notes and `docs/hotkey-semantics.md` for hotkey behavior.

## License

MIT, © Kit Langton. See `LICENSE`.
