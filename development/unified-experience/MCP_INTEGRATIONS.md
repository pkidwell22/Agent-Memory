# MCP Integration Plan

## Goal

After onboarding, a selected agent client can launch the same QMD installation
and query the same machine-local index configured by QMD Menu Bar.

MCP registration, QMD skill installation, and `AGENTS.md` instructions are
separate operations:

- MCP registration makes QMD tools available to the client.
- The QMD skill teaches an agent how to use those tools well.
- `AGENTS.md` tells an agent when memory should be searched or updated.

The UI must report these as separate states.

## Default Transport

Use stdio for the default public setup:

```text
<absolute-qmd-path> mcp
```

Benefits:

- no fixed port;
- no LaunchAgent;
- no IPv4/IPv6 ambiguity;
- no daemon lifecycle to coordinate with app updates;
- each client owns the subprocess it uses; and
- QMD's documented default transport is preserved.

HTTP is an advanced option only. If supported later, bind to loopback, verify
the exact address, manage the daemon explicitly, and configure every selected
client with the same verified URL.

## Binary Resolution

Agent configs must use the same QMD executable verified during onboarding.
Prefer an absolute path because GUI applications often receive a minimal PATH.

Do not write a source-checkout path such as `~/qmd/bin/qmd` for a new public
installation. The expected release path should come from the Homebrew formula
or another app-managed runtime decision.

Each generated configuration should include a minimal environment only when the
client requires it:

- `HOME`
- a PATH containing the resolved QMD and Node/Bun locations
- documented QMD runtime flags selected by the user

Do not copy the app's full inherited environment into agent configs.

## Adapter Contract

Every client adapter implements:

```text
detect()    -> installed, config path, current qmd state
preview()   -> exact proposed semantic change
backup()    -> timestamped machine-local copy
apply()     -> add/update only the app-owned qmd entry
verify()    -> parse config and perform an MCP handshake
restore()   -> restore the exact backup created by this operation
```

Adapters must be idempotent. Running setup twice should produce no second
change when the executable, arguments, and environment already match.

## Backup And State Locations

Use an app-owned machine-local directory:

```text
~/Library/Application Support/QMD Menu Bar/
  integrations.json
  Backups/
    codex/<timestamp>/config.toml
    opencode/<timestamp>/opencode.jsonc
    claude-code/<timestamp>/settings.json
    claude-desktop/<timestamp>/claude_desktop_config.json
    hermes/<timestamp>/config.yaml
```

`integrations.json` may record client name, config path, backup path, adapter
version, and verification timestamp. It must not store secrets or complete
copies of client configuration.

## Supported Clients

### Codex

Observed config location:

```text
~/.codex/config.toml
```

Target semantic entry:

```toml
[mcp_servers.qmd]
command = "/absolute/path/to/qmd"
args = ["mcp"]
```

Prefer an official Codex MCP command if one can make the same user-scoped,
idempotent change. Otherwise use a TOML-preserving parser. Do not regenerate the
whole file because it may contain unrelated tools and preferences.

### OpenCode

Observed config location:

```text
~/.config/opencode/opencode.jsonc
```

OpenCode uses the `mcp` key rather than `mcpServers`. The adapter must follow the
schema for the detected OpenCode version and preserve JSONC comments. Do not use
a plain JSON serializer against a JSONC file.

### Claude Code

Possible setup paths include the official QMD plugin and manual MCP
configuration in:

```text
~/.claude/settings.json
```

Prefer the official Claude CLI or QMD plugin flow if installed. If direct file
editing is required, preserve all unrelated settings and distinguish user scope
from project scope.

### Claude Desktop

Config location:

```text
~/Library/Application Support/Claude/claude_desktop_config.json
```

Target semantic entry under `mcpServers`:

```json
{
  "mcpServers": {
    "qmd": {
      "command": "/absolute/path/to/qmd",
      "args": ["mcp"]
    }
  }
}
```

Claude Desktop must be restarted after the configuration changes.

### Hermes

Config location:

```text
~/.hermes/config.yaml
```

Target semantic entry:

```yaml
mcp_servers:
  qmd:
    command: /absolute/path/to/qmd
    args: [mcp]
    enabled: true
```

Use a YAML-preserving strategy. Do not discard comments, ordering, unrelated
servers, providers, or security settings.

## Apply Safety

Before writing:

1. Confirm the config path belongs to the current user.
2. Reject symlinks that resolve outside the expected user configuration area
   unless the user explicitly approves the resolved target.
3. Check file ownership and avoid writing a file owned by another user.
4. Parse the current format successfully.
5. Create and verify the backup.
6. Show the semantic change, not the entire potentially sensitive config.
7. Write atomically with restrictive existing permissions preserved.
8. Parse the result again before reporting success.

Never display or log unrelated config values. Agent configs may contain API
keys, provider URLs, headers, or other secret-adjacent data.

## Verification

Verification has three levels:

1. **Config verified:** the resulting file parses and contains the expected
   QMD entry.
2. **MCP verified:** a controlled subprocess completes MCP initialization and
   exposes `query`, `get`, `multi_get`, and `status`.
3. **Client verified:** after any required restart, the client reports QMD tools
   available.

The app can automate the first two. It should not claim client verification
until the client itself has been checked.

## Existing Configurations

If an existing `qmd` entry differs:

- show whether it uses stdio or HTTP;
- test it without changing it;
- offer `Keep Existing`, `Migrate To Recommended`, and `Remove` separately;
- default to `Keep Existing` when it is healthy; and
- never remove an existing HTTP daemon or LaunchAgent as a side effect of
  editing a client config.

## Initial Implementation Order

1. Build fixture files for every supported config format, including comments,
   unrelated MCPs, missing sections, malformed input, and secret-shaped values.
2. Implement Codex and Claude Desktop adapters first because TOML and JSON have
   clear target structures.
3. Add OpenCode only with JSONC-preserving support.
4. Add Hermes only with YAML-preserving support.
5. Add Claude Code through its supported CLI/plugin path where possible.
6. Add HTTP migration only after stdio setup is reliable.
