# Agent Memory

A native macOS menu bar app that turns a folder of Markdown files into a searchable, automatically maintained [QMD](https://github.com/tobi/qmd) knowledge base.

Agent Memory is the control layer around QMD. QMD owns the index, embeddings, and retrieval engine; Agent Memory maps the vault into collections, runs the right QMD commands, schedules maintenance, and presents the results in a compact menu bar interface.

## System flow

```text
Markdown vault
    ↓
QMD collections
    ↓
Keyword index + vector embeddings
    ↓
Keyword, Fast, or Deep search, optionally scoped by collection
    ↓
Open the source file or copy the result
```

## How it works, start to finish

### 1. The app starts and restores its configuration

Agent Memory loads its saved paths, update interval, GPU preference, launch-at-login state, previous run summaries, and last successful automatic update. It then:

- starts monitoring macOS wake and network-recovery events;
- starts watching the configured memory folder when automatic updates are enabled;
- schedules the first automatic maintenance run when automatic updates are enabled;
- runs a health check; and
- checks the latest commit on GitHub's `main` branch for a newer app build.

Opening the menu refreshes QMD status when the displayed status is more than 60 seconds old. The header shows the current document and vector counts, the last check time, and the age of the newest indexed content.

### 2. The health check verifies the local QMD environment

Before relying on the index, Agent Memory checks:

- whether the configured QMD binary exists and is executable;
- which Node or Bun runtime the configured `PATH` resolves;
- whether QMD can report its version and status;
- whether the memory root is readable and the working directory exists;
- whether the QMD index exists and is readable and writable; and
- which executable, runtime, and index paths are actually in use.

Failures include a suggested remediation in Settings. QMD Doctor is also available for deeper QMD diagnostics.

### 3. The Markdown vault becomes a set of QMD collections

The configured memory root is mapped into collections before an index update:

- Markdown files directly inside the root become the reserved `agent-memory-root` collection with the `*.md` mask.
- Every immediate subfolder becomes its own uniquely named QMD collection.
- Each subfolder uses the configured recursive file mask, which defaults to `**/*.md`.

Collection names are normalized to QMD-safe names and disambiguated when folder names collide. Agent Memory caches a successful collection check, repeats it when the folder layout changes, and performs a safety recheck after 24 hours.

`Review Collections` builds a dry-run reconciliation plan before changing existing collections. The plan identifies additions, renames, replacements, and stale app-managed collections; the user decides whether to apply it.

### 4. Maintenance updates the index and embeddings

The primary `Update + Embed` action runs this pipeline:

1. Ensure the expected collections exist when a collection check is due.
2. Run `qmd update` to index new, changed, and removed Markdown files.
3. Run `qmd embed --chunk-strategy auto` to generate any missing vector embeddings.
4. Record a bounded result summary with the duration, exit status, and aggregate index counts.
5. Refresh the visible QMD status after a successful manual run.

The other maintenance actions expose individual parts of the pipeline:

| Action | Behavior |
| --- | --- |
| `Update Index` | Reconcile collections when needed, then run `qmd update`. |
| `Generate Embeddings` | Generate missing embeddings with automatic chunking. |
| `Force Rebuild` | Confirm with the user, then regenerate all embeddings with `qmd embed -f`. |
| `Review Collections` | Preview collection changes before applying them. |

Only one maintenance, health, status, collection-planning, or search operation runs at a time. QMD database-lock failures are retried, commands have a configurable timeout, and cancellation waits for the child process to terminate before another run can begin.

### 5. Search selects the appropriate QMD retrieval path

Entering a query and pressing Return cancels any older in-flight search and requests up to eight JSON results from QMD. Search can cover every non-empty collection or be scoped to one collection; the selected mode and collection persist between launches, and a removed collection automatically falls back to `All Collections`.

| Mode | QMD behavior | Best for |
| --- | --- | --- |
| `Keyword` | Runs `qmd search` without a language model. | Exact terms, filenames, identifiers, and fast lookups. |
| `Fast` | Routes exact-looking input to `qmd search`; otherwise sends direct `vec:` + `lex:` retrieval to `qmd query` with a 16-result candidate pool, bypassing query expansion and reranking. | Low-latency exploratory retrieval without either language-model stage. |
| `Deep` | Runs `qmd query` with a 16-result semantic candidate pool, query expansion, and reranking. | The highest-quality conceptual retrieval, preferably scoped to one collection. |

`Keyword` remains the default so opening the menu does not silently opt into model latency. Agent Memory decodes the QMD results and displays the title, collection path, and snippet. Opening a result asks QMD for the full source path and opens the Markdown file in its default macOS app. Copying a result places its title, QMD path, and snippet on the clipboard.

### 6. Automatic maintenance keeps the index current

When automatic updates are enabled, Agent Memory runs the same `Update + Embed` pipeline in response to:

- the configured periodic interval, from 5 to 720 minutes;
- debounced filesystem changes anywhere under the memory root;
- the Mac waking from sleep; and
- network connectivity returning after an observed outage.

Event-triggered runs are throttled so successful automatic runs stay at least five minutes apart. If another operation is busy, the scheduler retries in 60 seconds. The timestamp advances only after a successful automatic run; failures remain visible in the run panel and can trigger a macOS notification.

### 7. GitHub pushes prompt installed apps to update

Every packaged build records the exact Git commit it contains. Agent Memory compares that commit with the repository's `main` branch when the app launches and once per hour while it remains open.

After a new commit is pushed, each Mac shows a persistent update link in the menu footer and sends one macOS notification for that commit. The link opens the exact GitHub commit so the change can be reviewed. This is an update prompt, not a silent installer: replacing the installed app remains an explicit action until a signed and notarized distribution feed is configured.

### 8. Diagnostics preserve useful evidence without unbounded logs

The menu shows the active or most recent run, its duration, exit code, and concise index totals. Settings adds:

- health-check results and remediation;
- document, vector, collection-file, and freshness diagnostics;
- recent bounded run summaries;
- QMD Doctor;
- collection reconciliation; and
- app update status.

Captured process output is bounded, and persisted history stores summaries rather than unlimited raw command output.

## Defaults

- QMD binary: `~/qmd/bin/qmd`
- Index: the default QMD index (`~/.cache/qmd/index.sqlite`)
- Collections: iCloud `agent-memory` directories plus root-level Markdown (`agent-memory-root`)
- Vault: `~/Library/Mobile Documents/com~apple~CloudDocs/agent-memory`
- File mask: `**/*.md`

All paths and maintenance preferences are configurable in Settings. GPU acceleration is enabled by default; disabling it makes the runner set `QMD_LLAMA_GPU=false` for QMD processes.

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

The packaging script creates `dist/Agent Memory.app`, a versioned `Agent-Memory` ZIP, and a drag-to-Applications DMG. It derives the marketing version from the latest `v*` Git tag (falling back to `0.2.0`), the build number from the Git commit count, and embeds the full Git commit for push-aware update checks.

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

Unsigned local builds receive an ad-hoc signature. Signed releases can be published as GitHub Releases. Independently of release tags, the app checks GitHub's `main` branch on launch and hourly so every pushed commit can prompt installed copies.

Tagged releases are built by `.github/workflows/release.yml`. The workflow requires these GitHub Actions secrets:

- `DEVELOPER_ID_APPLICATION_P12`: base64-encoded Developer ID Application certificate and private key
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`: password protecting the exported certificate
- `APPLE_ID`: Apple ID used by `notarytool`
- `APPLE_TEAM_ID`: Apple Developer team identifier
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password used for notarization

It also requires the `APPLE_SIGNING_IDENTITY` Actions variable, such as `Developer ID Application: Example (TEAMID)`. Pushing a semantic version tag such as `v0.2.0` runs tests, signs and notarizes the app and DMG, verifies both artifacts, and publishes the DMG plus its SHA-256 checksum to GitHub Releases.
