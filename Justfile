set dotenv-load := false

repo := invocation_directory()
derived_data := repo / "/.derived-data"
debug_app := derived_data / "/Build/Products/Debug/Hex Debug.app"
release_app := derived_data / "/Build/Products/Release/Hex.app"
evals := repo / "/Tools/HexEvals"
evals_derived_data := evals / "/.derived-data"

# List available commands.
default:
  @just --list

# Build the Debug app with Xcode from a neutral cwd.
build-debug:
  cd /tmp && env -u IN_NIX_SHELL TMPDIR=/tmp xcodebuild \
    -project "{{repo}}/Hex.xcodeproj" \
    -scheme Hex \
    -configuration Debug \
    -derivedDataPath "{{derived_data}}" \
    build

# Build the Release app with Xcode from a neutral cwd.
build:
  cd /tmp && env -u IN_NIX_SHELL TMPDIR=/tmp xcodebuild \
    -project "{{repo}}/Hex.xcodeproj" \
    -scheme Hex \
    -configuration Release \
    -derivedDataPath "{{derived_data}}" \
    build

# Alias for build.
build-release: build

# Run the built Release app.
run: build
  open "{{release_app}}"

# Run the built Debug app.
run-debug: build-debug
  open "{{debug_app}}"

# Build, ad-hoc sign, and install into /Applications.
install:
  env -u IN_NIX_SHELL TMPDIR=/tmp bash "{{repo}}/scripts/install-local.sh"

# Common typo alias for install.
instlal: install

# Run HexCore unit tests.
test-core:
  cd "{{repo}}/HexCore" && swift test

# Run all app tests through Xcode from a neutral cwd.
test-xcode:
  cd /tmp && env -u IN_NIX_SHELL TMPDIR=/tmp xcodebuild test \
    -project "{{repo}}/Hex.xcodeproj" \
    -scheme Hex \
    -derivedDataPath "{{derived_data}}"

# Run all local transcript evals. Uses xcodebuild so MLX Metal resources are available.
eval:
  cd "{{evals}}" && env -u IN_NIX_SHELL TMPDIR=/tmp xcodebuild test \
    -scheme HexEvals \
    -destination 'platform=macOS' \
    -derivedDataPath "{{evals_derived_data}}"

# Run cleanup-only evals.
eval-cleanup:
  cd "{{evals}}" && env -u IN_NIX_SHELL TMPDIR=/tmp xcodebuild test \
    -scheme HexEvals \
    -destination 'platform=macOS' \
    -derivedDataPath "{{evals_derived_data}}" \
    -only-testing:HexEvalsTests/CleanupEvals

# Run transcription-only evals.
eval-transcription:
  cd "{{evals}}" && env -u IN_NIX_SHELL TMPDIR=/tmp xcodebuild test \
    -scheme HexEvals \
    -destination 'platform=macOS' \
    -derivedDataPath "{{evals_derived_data}}" \
    -only-testing:HexEvalsTests/TranscriptionEvals

# Run end-to-end evals.
eval-e2e:
  cd "{{evals}}" && env -u IN_NIX_SHELL TMPDIR=/tmp xcodebuild test \
    -scheme HexEvals \
    -destination 'platform=macOS' \
    -derivedDataPath "{{evals_derived_data}}" \
    -only-testing:HexEvalsTests/EndToEndEvals

# Remove generated build products.
clean:
  rm -rf "{{derived_data}}" "{{evals_derived_data}}" "{{evals}}/.build"
