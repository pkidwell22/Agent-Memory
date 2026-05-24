# QMD Menu Bar

A small macOS menu bar utility for a local QMD-backed `agent-memory` vault.

Defaults:

- QMD binary: `~/qmd/bin/qmd`
- Index: `obsidian-agent-memory`
- Collection: `agent-memory`
- Vault: `~/Library/Mobile Documents/com~apple~CloudDocs/agent-memory`
- File mask: `**/*.md`

Menu actions:

- Update + Embed
- Update Index
- Generate Embeddings
- Force Rebuild
- Ensure Collection
- Automatic update + embed while the app is running

Build and launch:

```bash
./script/build_and_run.sh --verify
```
