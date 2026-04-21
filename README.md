# fyso-team-sync (ARCHIVED)

> **This plugin has been merged into [`fyso-plugin`](https://github.com/fyso-dev/fyso-plugin).** Use that instead.

## Migration

All functionality from this repo (team sync, tracking, heartbeat) is now included in the unified Fyso plugin:

**Claude Code:**
```bash
/plugin marketplace add fyso-dev/fyso-plugin
/plugin install fyso@fyso-plugins
```

**OpenCode (Windows):**
```powershell
irm https://raw.githubusercontent.com/fyso-dev/fyso-plugin/main/setup-opencode.ps1 | iex
```

**OpenCode (macOS/Linux):**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fyso-dev/fyso-plugin/main/setup-opencode.sh)
```
