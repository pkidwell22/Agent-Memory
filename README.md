# QMD Menu Bar

A native macOS menu bar companion for searching and maintaining a local [QMD](https://github.com/tobi/qmd)-backed `agent-memory` vault.

## Features

- Fast keyword search and optional hybrid QMD queries from the menu bar
- Open the source Markdown file or copy a search result
- Update the index, generate embeddings, or force a confirmed rebuild
- Cancellable QMD processes with timeout, lock retry, and stale-run protection
- First-run health check for the QMD binary, Node/Bun runtime, index, and memory folder
- QMD Doctor action with persistent, bounded run diagnostics
- Automatic update + embed shortly after launch and on a configurable interval
- Wake/network recovery, skipped-run retry, failure notifications, and optional Launch at Login
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

## Release builds

The packaging script creates `dist/QMDMenuBar.app` and a versioned ZIP. It derives the marketing version from the latest `v*` Git tag (falling back to `0.2.0`) and the build number from the Git commit count.

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
