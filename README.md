# Agent Memory

A native macOS menu bar companion for searching and maintaining a local [QMD](https://github.com/tobi/qmd)-backed `agent-memory` vault.

## Features

- Keyword, candidate-limited Hybrid, and no-rerank Fast search modes from the menu bar
- A compact status panel with a custom aperture menu-bar icon and selected-only search-mode highlighting
- Open the source Markdown file or copy a search result
- Update the index, generate embeddings, or force a confirmed rebuild
- Cancellable QMD processes with timeout, lock retry, and stale-run protection
- First-run health check for the QMD binary, Node/Bun runtime, index, and memory folder
- QMD Doctor action with persistent, bounded run diagnostics
- Adaptive automatic update + embed with a configurable periodic fallback
- Debounced folder watching, throttled wake/network recovery, failure notifications, and optional Launch at Login
- Collection checks cached until the folder layout changes, with a daily safety recheck
- Dry-run collection reconciliation before additions, renames, replacements, or stale removals
- GitHub Releases update check

## Defaults

- QMD binary: `~/qmd/bin/qmd`
- Index: the default QMD index (`~/.cache/qmd/index.sqlite`)
- Collections: iCloud `agent-memory` directories plus root-level Markdown (`agent-memory-root`)
- Vault: `~/Library/Mobile Documents/com~apple~CloudDocs/agent-memory`
- File mask: `**/*.md`

Paths are configurable in Settings. The health check shows the resolved QMD executable and the exact Node/Bun runtime selected by the app's PATH, which is useful when native Node modules were built for a different ABI.

## Development

Requires macOS 14 or newer and Swift 6.

```bash
swift build
swift test
./script/build_and_run.sh --debug --verify
```

CI runs both `swift build` and `swift test` on macOS.

## Installation

To build and run Agent Memory locally without replacing an installed copy:

```bash
./script/build_and_run.sh --release --verify
```

The local app runs from `dist/Agent Memory.app`. The same build also creates a drag-to-Applications DMG at `dist/Agent-Memory-<version>.dmg`.

Once the first signed release and Homebrew tap are published:

```bash
brew install --cask pkidwell22/tap/qmd-menu-bar
```

Homebrew installs the app as `/Applications/Agent Memory.app`. Development builds continue to run from `dist/` unless you install the generated app or DMG yourself.

## Release builds

The packaging script creates `dist/Agent Memory.app`, a versioned `Agent-Memory` ZIP, and a drag-to-Applications DMG. It derives the marketing version from the latest `v*` Git tag (falling back to `0.2.0`) and the build number from the Git commit count.

```bash
./script/build_and_run.sh --release --no-launch
```

To create a hardened, Developer ID-signed build:

```bash
./script/build_and_run.sh \
  --release \
  --sign "Developer ID Application: Example (TEAMID)" \
  --no-launch
```

To notarize, first store App Store Connect credentials in a `notarytool` keychain profile, then add:

```bash
--notarize-profile "qmd-menu-bar-notary"
```

Unsigned local builds receive an ad-hoc signature. Signed releases can be published as GitHub Releases; the app's Settings screen links users to the latest release when a newer version is available.

Tagged releases are built by `.github/workflows/release.yml`. The workflow requires these GitHub Actions secrets:

- `DEVELOPER_ID_APPLICATION_P12`: base64-encoded Developer ID Application certificate and private key
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`: password protecting the exported certificate
- `APPLE_ID`: Apple ID used by `notarytool`
- `APPLE_TEAM_ID`: Apple Developer team identifier
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password used for notarization

It also requires the `APPLE_SIGNING_IDENTITY` Actions variable, such as `Developer ID Application: Example (TEAMID)`. Pushing a semantic version tag such as `v0.2.0` runs tests, signs and notarizes the app and DMG, verifies both artifacts, and publishes the DMG plus its SHA-256 checksum to GitHub Releases.
