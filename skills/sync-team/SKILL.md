---
name: sync-team
description: Sync a Fyso agent team to local .claude/agents/ directory. Downloads agent definitions and creates .md files for Claude Code to use as subagents.
user-invocable: true
---

# Sync Fyso Team Agents

Follow these steps exactly to sync a Fyso team's agents into the local `.claude/agents/` directory and the team prompt into `.claude/CLAUDE.md`.

## Step 1 — Get the token

First, check if a saved token exists at `~/.fyso/config.json`. If it does, read it and use the stored `token` and `tenant_id` values. Tell the user you found saved credentials and ask if they want to use them or enter new ones.

If no saved config exists, ask the user for their **Token** (Bearer token for API access).

Tell the user:

> Para obtener tu token, andá a https://agent-ui-sites.fyso.dev/ , ingresá con tu email y contraseña, y copiá el token que aparece en pantalla.

The tenant ID is always `fyso-world-fcecd`. Do NOT ask the user for it.

The API URL is always `https://api.fyso.dev`. Do NOT ask the user for it.

## Step 2 — Save credentials

After obtaining the token (whether new or from saved config), validate it by fetching the current user:

```
curl -s "https://api.fyso.dev/api/auth/me" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "X-Tenant-ID: fyso-world-fcecd"
```

This returns the user's email and name. Save everything to `~/.fyso/config.json`:

```bash
mkdir -p ~/.fyso
```

Write the file with the Write tool:

```json
{
  "token": "{TOKEN}",
  "tenant_id": "fyso-world-fcecd",
  "api_url": "https://api.fyso.dev",
  "user_email": "{EMAIL_FROM_API}",
  "user_name": "{NAME_FROM_API}",
  "saved_at": "{ISO_TIMESTAMP}"
}
```

This ensures future runs of `/sync-team` can reuse the token without asking again.

## Step 3 — List teams

Fetch all teams:

```
curl -s "https://api.fyso.dev/api/entities/teams/records" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "X-Tenant-ID: fyso-world-fcecd"
```

Parse the JSON response. The records are in `data.items`. Each team has at least `id`, `name`, and optionally `prompt`.

## Step 4 — Let the user pick a team

Present the list of teams to the user in a numbered list, showing each team's name. Ask them to pick one by number or name. Wait for their response before continuing.

Save the selected team info to `~/.fyso/config.json` (update the existing file adding `team_id` and `team_name` fields).

## Step 5 — Write team prompt to CLAUDE.md

If the selected team has a `prompt` field (non-empty), write it to `.claude/CLAUDE.md` in the current working directory. If the file already exists, replace the section between `<!-- FYSO TEAM START -->` and `<!-- FYSO TEAM END -->` markers. If no markers exist, append the section at the end.

The format is:

```markdown
<!-- FYSO TEAM START -->
{team prompt content}
<!-- FYSO TEAM END -->
```

If the team has no prompt, skip this step and inform the user.

## Step 6 — Fetch team agents

Using the selected team's `id`, fetch the agents assigned to that team:

```
curl -s "https://api.fyso.dev/api/entities/team_agents/records?resolve=true&filter.team={TEAM_ID}" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "X-Tenant-ID: fyso-world-fcecd"
```

The response contains records where each entry has an `_agent` field (resolved to a full agent object because of `resolve=true`). Extract the agent details from each record. Key fields on each agent:

- `name` — slug/identifier
- `display_name` — human-readable name
- `role` — the agent's role (developer, qa, reviewer, coordinator, writer, security, etc.)
- `soul` — the agent's soul text (personality and principles)
- `system_prompt` — the agent's system prompt (instructions, rules, workflow)

If any field is missing, use a sensible default (empty string for text fields, "assistant" for role).

## Step 7 — Create agent files

First, ensure the `.claude/agents/` directory exists in the current working directory:

```
mkdir -p .claude/agents
```

For each agent, create a file at `.claude/agents/{name}.md` where `{name}` is the agent's `name` field (the slug). Use the Write tool to create each file with this exact format:

```markdown
---
name: {name}
description: {role} -- {display_name}. {first_line_of_soul}
tools: Read, Write, Edit, Bash, Grep, Glob
color: {color}
---

# {display_name}

**Role:** {role}

## Soul
{soul}

## System Prompt
{system_prompt}
```

IMPORTANT: Include the FULL content of `soul` and `system_prompt` fields. Do NOT truncate, summarize, or abbreviate them. These are the agent's complete instructions and must be preserved exactly as received from the API.

Map the `color` field based on the agent's role using these rules:

| Role contains | Color  |
|---------------|--------|
| developer     | green  |
| qa or tester  | yellow |
| reviewer      | purple |
| coordinator   | blue   |
| writer        | cyan   |
| security      | red    |
| triage        | orange |
| (anything else) | gray |

The match should be case-insensitive and partial (e.g. "Senior Developer" matches "developer" and gets green).

For `first_line_of_soul`: take the first non-empty line of the `soul` field, trimmed. If soul is empty, use the display_name instead.

## Step 8 — Report results

After creating all files, print a summary:

- Whether the team prompt was written to `.claude/CLAUDE.md`
- How many agent files were created
- The full path of each file created
- That credentials were saved to `~/.fyso/config.json` for future use
- A reminder that the user can now use these agents as subagents in Claude Code via the Task tool or by referencing them

If no agents were found for the selected team, inform the user and suggest they check the team configuration in the Fyso dashboard at https://agent-ui-sites.fyso.dev.
