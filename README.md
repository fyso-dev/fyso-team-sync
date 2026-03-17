# fyso-team-sync

Claude Code plugin that syncs Fyso agent teams into local `.claude/agents/` files, making them available as subagents.

## Installation

### From GitHub (recommended)

```bash
# Add the marketplace
/plugin marketplace add fyso-dev/fyso-team-sync

# Install the plugin
/plugin install fyso-team-sync@fyso-dev
```

### For a whole team

Add to your project's `.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "fyso-team-sync@fyso-dev": true
  }
}
```

### Local development

```bash
claude --plugin-dir /path/to/fyso-team-sync
```

## Usage

In any Claude Code session, run:

```
/sync-team
```

You will be prompted for:

- **Token** (Bearer token for API access)
- **Tenant ID** (your tenant slug)

Then pick a team from the list. The plugin creates `.claude/agents/` files in your current working directory.

## Requirements

- A Fyso account with access to a tenant
- At least one team configured with agents assigned
- Network access to the Fyso API

## Generated file format

Each agent file follows the Claude Code agent spec:

```markdown
---
name: agent-slug
description: role -- Display Name. First line of soul.
tools: Read, Write, Edit, Bash, Grep, Glob
color: green
---

# Display Name

**Role:** developer

## Soul
(agent soul text)

## System Prompt
(agent system prompt)
```

Colors are mapped by role: developer=green, qa/tester=yellow, reviewer=purple, coordinator=blue, writer=cyan, security=red, other=gray.
