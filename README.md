# QMD Menu Bar

A small macOS menu bar utility for a local QMD-backed `agent-memory` vault.

Defaults:

- QMD binary: `~/qmd/bin/qmd`
- Index: the default QMD index (`~/.cache/qmd/index.sqlite`)
- Collections: iCloud `agent-memory` directories plus root-level Markdown (`agent-memory-root`)
- Vault: `~/Library/Mobile Documents/com~apple~CloudDocs/agent-memory`
- File mask: `**/*.md`

Menu actions:

- Update + Embed
- Update Index
- Generate Embeddings
- Force Rebuild
- Ensure Collections
- Automatic update + embed while the app is running
- Persistent recent-run diagnostics with command time, duration, exit code, and QMD output summary

Build and launch:

```bash
./script/build_and_run.sh --verify
```
