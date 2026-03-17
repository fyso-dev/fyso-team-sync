# fyso-team-sync

Claude Code plugin that syncs Fyso agent teams into local `.claude/agents/` files, making them available as subagents.

## What it does

The `/sync-team` skill connects to the Fyso REST API, lets you pick a team, and downloads all agents assigned to that team. For each agent it creates a `.claude/agents/{name}.md` file with the agent's soul, system prompt, role, and metadata -- ready to be used as a Claude Code subagent via the Task tool.

## Installation

Add the plugin path to your Claude Code configuration. Either:

1. **Local install**: Add the absolute path to this directory in your Claude Code plugin settings
2. **Project install**: Copy or symlink this directory into your project and reference it in `.claude/plugins`

## Usage

In any Claude Code session, run:

```
/sync-team
```

You will be prompted for:

- **API URL** (defaults to `https://api.fyso.dev`)
- **Tenant ID** (your tenant slug)
- **Email and password** (your Fyso login credentials)

Then pick a team from the list. The plugin creates `.claude/agents/` files in your current working directory.

## Requirements

- A Fyso account with access to a tenant
- At least one team configured in that tenant with agents assigned
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
