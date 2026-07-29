# Agent Instruction Templates

## Purpose

Agent Memory should generate a small, portable QMD instruction block instead
of copying this repository's complete `Agents.md`.

`AGENTS.md` is normally a file, not a folder. Global instruction locations vary
by agent, so the first implementation should provide copy actions and a
project-level insertion workflow rather than assuming one universal global
file path.

The app renders templates using:

- the selected memory root;
- configured collection names;
- whether MCP was configured;
- the resolved QMD executable for CLI fallback; and
- whether the user explicitly enabled agent-written memory.

Private paths should be shown in the preview but omitted from diagnostics and
telemetry.

## Global Template

The following is the generic block offered by `Copy Global Instructions`.
Placeholders are replaced by the app before copying.

````markdown
## Agent Memory: QMD

Use QMD to search the user's local Markdown knowledge base before substantive
work when prior decisions, project context, or historical notes could affect
the result.

Memory root: `<selected-memory-root>`

Preferred workflow:

1. Check QMD status.
2. Search for candidate documents with a structured query that states the
   intent and includes exact terms or semantic descriptions.
3. Retrieve the relevant source documents before relying on search snippets.
4. Base claims about prior decisions or history on the retrieved source text.

When QMD MCP tools are available, prefer its `status`, `query`, `get`, and
`multi_get` tools. Otherwise use the local QMD CLI:

```bash
qmd status
qmd query $'intent: <what you need and what to avoid>\nlex: <exact terms>\nvec: <semantic description>'
qmd get "<result>"
```

Do not run collection mutation, forced embedding, cleanup, or reindexing unless
the user asks or current index maintenance is required for the task. Do not
expose document contents, private paths, credentials, or sensitive query text
in logs or external services.
````

## Project Template

The following block can be inserted into a repository's `AGENTS.md`. The app
should detect an existing file, show a preview, and insert only between owned
markers after user confirmation.

```markdown
<!-- qmd-menu-bar:start -->
## Project Memory

Before substantive work in this project, search QMD for prior project context,
decisions, constraints, and unresolved questions. Prefer these collections:
`<project-collections>`.

Search snippets are leads, not evidence. Retrieve the source document before
making claims about prior work. Keep project code and QMD memory as separate
sources of truth: verify current code behavior in the live repository.

Do not mutate QMD collections or run heavy re-embedding as routine orientation.
<!-- qmd-menu-bar:end -->
```

The owned markers allow safe updates without replacing unrelated project
instructions.

## Optional Write-To-Memory Addendum

Writing is disabled by default. Offer this only after the user selects a
writable destination and explicitly enables agent-authored summaries.

```markdown
### Saving Project Memory

Only save to QMD memory when the user asks to save, remember, capture, or log
the session. Write to `<writable-project-memory-location>` using the configured
session format. Preserve existing history: daily session logs are append-only,
and existing entries must not be rewritten or deleted.

Never save credentials, tokens, private keys, raw private prompts, or unrelated
personal data. Summarize decisions and outcomes rather than copying complete
chat transcripts.
```

## Installation Options

The instructions screen should offer:

- `Install QMD Skill`: invokes the version-matched QMD global skill installer
  for `~/.agents/skills/qmd`.
- `Copy Global Instructions`: copies the rendered global block.
- `Copy Project Instructions`: copies the rendered project block.
- `Insert Into Project AGENTS.md`: previews and inserts the owned block after a
  backup, only when the user selected a project file.
- `Copy Write Addendum`: available only when memory writing is enabled.

## Safety Requirements

- Never copy Patrick's complete project `Agents.md` to another user.
- Never infer that a selected index folder is writable agent memory.
- Never enable write instructions by default.
- Never overwrite an existing `AGENTS.md`.
- Never append duplicate owned blocks.
- Preserve line endings and unrelated content.
- Create a timestamped backup before updating a project file.
- Show the final rendered instructions before copying or inserting them.

## Verification

Instruction setup can be reported as:

- generated;
- copied to clipboard;
- inserted into a selected project file; or
- global QMD skill installed.

Copying text is not proof that an agent loaded it. The app should tell the user
which clients need a restart or new session before the instructions take
effect.
