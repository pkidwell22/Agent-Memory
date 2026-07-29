# Unified QMD Experience

Status: product and architecture planning only. No Homebrew tap or public
release should be created until the onboarding and integration requirements in
this folder are implemented and verified.

## Vision

A user installs Agent Memory, chooses a folder containing Markdown, and leaves
onboarding with:

- the folder indexed locally for keyword search;
- optional local embeddings ready for hybrid search;
- automatic index maintenance configured;
- QMD available to selected agent clients through MCP;
- version-matched QMD agent instructions available to install or copy; and
- a clear health screen showing what is ready and what still needs attention.

The current machine is the behavioral reference, not the installation model.
The public app must reproduce its useful outcomes without assuming a QMD source
checkout, Patrick's paths, an existing LaunchAgent, or preconfigured agents.

## Product Principles

1. **Local first.** Source documents, indexes, embeddings, and searches remain
   local. The app must not upload document names, contents, or queries.
2. **User-selected content.** No personal folder is indexed until the user
   chooses it with the macOS folder picker and confirms the scan preview.
3. **Synced source, local index.** The selected folder may live in iCloud or
   another sync provider. QMD configuration, SQLite indexes, models, backups,
   and logs remain machine-local.
4. **Explicit integrations.** The app only changes agent configurations that
   the user selects after previewing the change.
5. **Non-destructive setup.** Existing QMD collections and agent configuration
   are detected, backed up, and preserved. Automatic setup may add or update the
   app-owned `qmd` entry, but it must never replace an entire config file.
6. **Resumable work.** Model downloads, indexing, and embedding can be retried
   after interruption without restarting onboarding.
7. **Honest readiness.** Installed, indexed, embedded, MCP-configured, and
   client-verified are separate states in the UI.

## Current Behavior To Preserve

The current setup uses a user-owned Markdown root, QMD's default local index,
one collection per first-level project folder, a separate root collection for
root-level Markdown, update-and-embed maintenance, menu-bar search, and agent
access through QMD MCP.

The public app should preserve these capabilities while removing these current
assumptions:

- QMD exists at `~/qmd/bin/qmd`.
- The working directory is `~/qmd`.
- The content root is a specific iCloud `agent-memory` folder.
- Every user wants first-level folders split into collections.
- An HTTP MCP daemon and per-client configuration already exist.
- The global QMD skill and agent instructions are already installed.

## First-Run Experience

### 1. Welcome And Privacy

Explain that QMD indexes Markdown locally, where the machine-local index is
stored, and that choosing a synced folder does not sync the index itself.

Actions:

- `Set Up QMD`
- `Use Existing Setup`
- `Learn What Stays Local`

### 2. Runtime Readiness

Resolve QMD in this order:

1. App-managed or Homebrew-managed QMD dependency.
2. An existing `qmd` executable on a trusted PATH.
3. A user-selected executable for migration and development.

The release design should prefer a Homebrew formula dependency for
`@tobilu/qmd` and Node 22 rather than silently running a global npm install.
The exact dependency strategy remains an open decision and must be prototyped
before the cask is published.

Show the resolved executable, QMD version, Node/Bun runtime, and whether the
installation is app-managed or external.

### 3. Choose Content

Use `NSOpenPanel` to select one folder. Valid examples include iCloud Drive,
Desktop, Documents, an Obsidian vault, or another local folder.

Store a security-scoped bookmark in addition to the display path so the design
can support a sandboxed build later. Detect unavailable iCloud placeholders and
offer to download them before scanning.

Do not assume the selected folder is writable. Indexing must work in read-only
mode; agent-authored memory is a separate opt-in.

### 4. Choose Collection Layout

Offer two modes:

**Single collection, recommended**

- One collection for the selected folder.
- Recursive `**/*.md` mask.
- Best for notes, documentation, and ordinary vaults.

**Project folders**

- One collection per first-level folder.
- A separate root collection using `*.md`.
- Lowercase names with non-alphanumeric runs converted to `-`.
- Best for the current `agent-memory` organization.

The preview must show proposed names, paths, masks, collisions, empty folders,
hidden folders, unreadable files, and files excluded by QMD rules.

### 5. Build The Index

Run the setup as observable stages:

1. Add or reconcile approved collections.
2. Run `qmd update` for keyword search.
3. Confirm keyword search is ready.
4. Explain the embedding model download and estimated work.
5. Run `qmd embed --chunk-strategy auto` if the user enables hybrid search.
6. Verify document coverage and pending embeddings.

Keyword readiness must not wait for embeddings. The user can finish onboarding
with keyword search enabled and run embeddings later.

### 6. Configure Agents

Detect supported clients and present checkboxes. The initial target set is:

- Codex
- OpenCode
- Claude Code
- Claude Desktop
- Hermes

Use stdio `qmd mcp` by default. It avoids a background daemon, port conflicts,
IPv4/IPv6 differences, and stale LaunchAgents. HTTP transport remains an
advanced option for users who deliberately want one shared long-lived server.

For each selected client, show:

- config path or official client command;
- whether an existing `qmd` entry was found;
- the proposed before/after change;
- backup location;
- whether the client must restart; and
- verification status.

Detailed requirements are in [MCP_INTEGRATIONS.md](MCP_INTEGRATIONS.md).

### 7. Install Or Copy Agent Instructions

Offer three separate actions:

1. Install the version-matched upstream QMD skill globally at
   `~/.agents/skills/qmd` by invoking QMD's supported skill installer.
2. Copy a generated global QMD instruction block.
3. Copy or insert a generated project-level `AGENTS.md` block.

Do not copy this repository's complete `Agents.md`. It includes personal,
machine-specific, browser, release, and workflow instructions that do not
belong on another user's machine.

Templates and write-policy rules are in
[AGENT_INSTRUCTIONS.md](AGENT_INSTRUCTIONS.md).

### 8. Verify And Finish

The completion screen reports each state independently:

- QMD executable resolved
- selected folder accessible
- collections configured
- indexed document count verified
- keyword search verified
- embeddings current or intentionally skipped
- QMD skill installed or skipped
- each selected MCP client configured
- MCP server handshake verified
- client restart still required
- automatic maintenance enabled or skipped

Provide `Open Agent Memory`, `Open Settings`, and `Export Setup Report` actions.
The report must omit document names, queries, credentials, and private paths by
default.

## Application Architecture

### Setup Coordinator

A persisted state machine drives onboarding. It records completed steps and
recoverable failures but never stores credentials.

Suggested states:

```text
welcome
runtime
folder
collectionPreview
indexing
embedding
integrations
instructions
verification
complete
```

### Runtime Resolver

Responsible for locating QMD and its runtime, reporting versions, and producing
one absolute executable path for the runner and integration adapters.

### Folder Access Manager

Owns folder selection, bookmarks, iCloud availability checks, read/write
capability checks, and human-readable privacy summaries.

### Collection Planner

Extends the current reconciliation logic with an explicit single-collection
mode and a project-folders mode. Planning and applying remain separate actions.

### Indexing Coordinator

Runs collection setup, update, and embedding as cancellable stages. It exposes
progress without retaining raw private output in notifications or long-lived
logs.

### Integration Manager

Detects clients and delegates to a versioned adapter for each config format.
Every adapter implements detect, preview, backup, apply, verify, and restore.

### Instruction Generator

Renders generic QMD guidance using the chosen folder, collection layout, MCP
availability, and optional write policy. It never includes Patrick-specific
instructions.

## Machine-Local Data

Use established QMD locations where possible:

```text
~/.config/qmd/                         QMD collection configuration
~/.cache/qmd/                          indexes, models, and QMD runtime state
~/.agents/skills/qmd/                  optional global QMD skill
~/Library/Application Support/
  Agent Memory/                        onboarding state and integration backups
```

The user-selected Markdown folder remains wherever the user chose it. The app
must not move it into an app-owned directory.

## Existing-User Migration

On first launch after this feature ships:

1. Run a read-only health check.
2. If QMD, the folder, collections, and index are healthy, offer
   `Keep Existing Setup` rather than showing new-user onboarding.
3. Import existing paths into the new setup state without rewriting QMD config.
4. Detect existing HTTP or stdio MCP entries and leave them unchanged unless
   the user chooses to migrate.
5. Never reset collections, delete indexes, reinstall QMD, or replace agent
   configs as part of migration.

## Failure And Recovery Requirements

- Missing QMD: explain the dependency and provide one supported repair path.
- Inaccessible folder: let the user reselect it without losing later choices.
- iCloud file unavailable: identify counts without exposing filenames in logs.
- Collection conflict: preview rename/add/replace/remove separately.
- Interrupted update: retain keyword readiness from the last successful run.
- Interrupted embedding: show pending count and resume.
- Invalid client config: do not modify it; provide a copyable manual snippet.
- Failed integration: offer restore from the app-created backup.
- App uninstall: do not delete user documents, QMD indexes, agent configs, or
  integration backups unless the user explicitly chooses a separate cleanup.

## Delivery Phases

### Phase 0: Decisions And Prototypes

- Decide formula dependency versus bundled QMD runtime.
- Validate installation on clean Apple Silicon and Intel test accounts.
- Confirm QMD package/version ownership and update policy.
- Prototype config-preserving adapters for the initial agent clients.
- Decide whether the first release supports both collection layouts.

### Phase 1: Runtime And Existing-Setup Detection

- Replace `~/qmd` defaults with runtime resolution.
- Add setup-state models and read-only migration detection.
- Keep the current machine working without changes.

### Phase 2: Folder And Index Onboarding

- Add first-run window, folder picker, scan preview, and collection modes.
- Add staged indexing, embedding progress, cancellation, and recovery.
- Verify coverage against controlled iCloud and local fixtures.

### Phase 3: MCP Integrations

- Implement client detection, preview, backups, idempotent writes, restore, and
  verification.
- Start with two clients, then expand only after fixture coverage exists for
  every supported config format.

### Phase 4: Instructions And Skills

- Add global skill installation through QMD.
- Add generated global/project instruction previews and copy actions.
- Add optional, explicit write-to-memory policy.

### Phase 5: Distribution

- Finalize Developer ID signing and notarization.
- Publish the app DMG and QMD formula in a separate Homebrew tap.
- Make the cask depend on the tested QMD formula.
- Run onboarding in a clean user account before publishing each release.

## Release Acceptance Criteria

A clean machine with Homebrew but no QMD checkout must be able to:

1. install the app with one cask command;
2. launch without editing paths manually;
3. select an iCloud or local Markdown folder;
4. complete keyword indexing;
5. optionally complete embeddings;
6. configure at least the supported launch clients without losing existing
   config;
7. use QMD through MCP after the documented restart;
8. install or copy generic agent instructions; and
9. uninstall the app without deleting user content.

## Open Decisions

- Ship a Homebrew formula for upstream QMD or bundle a private runtime?
- Support both collection layouts in the first public release?
- Which two agent clients are required for the first integration milestone?
- Should automatic update-and-embed be opt-in or enabled after onboarding?
- Should generated agent instructions allow writing summaries by default?
- Remain hardened but unsandboxed, or invest in sandbox bookmarks and helper
  processes before public release?
