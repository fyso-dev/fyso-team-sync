---
name: sync-team
description: Sync a Fyso agent team to local .claude/agents/ directory. Downloads agent definitions and creates .md files for Claude Code to use as subagents.
user-invocable: true
---

# Sync Fyso Team Agents

Follow these steps exactly to sync a Fyso team's agents into the local `.claude/agents/` directory.

## Step 1 — Get the token

Ask the user for their **Token** (Bearer token for API access). If they have provided it previously in this conversation, reuse it.

Tell the user:

> Para obtener tu token, andá a https://agent-ui-sites.fyso.dev/ , ingresá con tu email y contraseña, y copiá el token que aparece en pantalla.

The tenant ID is always `fyso-world-fcecd`. Do NOT ask the user for it.

The API URL is always `https://api.fyso.dev`. Do NOT ask the user for it.

Do NOT store credentials to disk. Keep them only in conversation memory for the duration of this session.

## Step 2 — List teams

Fetch all teams:

```
curl -s "https://api.fyso.dev/api/entities/teams/records" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "X-Tenant-ID: fyso-world-fcecd"
```

Parse the JSON response. The records are typically in a `data` array (or at the top level if the response is an array). Each team has at least `id` and `name`.

## Step 3 — Let the user pick a team

Present the list of teams to the user in a numbered list, showing each team's name. Ask them to pick one by number or name. Wait for their response before continuing.

## Step 4 — Fetch team agents

Using the selected team's `id`, fetch the agents assigned to that team:

```
curl -s "https://api.fyso.dev/api/entities/team_agents/records?resolve=true&filter.team={TEAM_ID}" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "X-Tenant-ID: fyso-world-fcecd"
```

The response contains records where each entry has an `agent` field (resolved to a full agent object because of `resolve=true`). Extract the agent details from each record. Key fields on each agent:

- `name` — slug/identifier
- `display_name` — human-readable name
- `role` — the agent's role (developer, qa, reviewer, coordinator, writer, security, etc.)
- `soul` — the agent's soul text (personality and principles)
- `system_prompt` — the agent's system prompt

If any field is missing, use a sensible default (empty string for text fields, "assistant" for role).

## Step 5 — Create agent files

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

Map the `color` field based on the agent's role using these rules:

| Role contains | Color  |
|---------------|--------|
| developer     | green  |
| qa or tester  | yellow |
| reviewer      | purple |
| coordinator   | blue   |
| writer        | cyan   |
| security      | red    |
| (anything else) | gray |

The match should be case-insensitive and partial (e.g. "Senior Developer" matches "developer" and gets green).

For `first_line_of_soul`: take the first non-empty line of the `soul` field, trimmed. If soul is empty, use the display_name instead.

## Step 6 — Report results

After creating all files, print a summary:

- How many agent files were created
- The full path of each file created
- A reminder that the user can now use these agents as subagents in Claude Code via the Task tool or by referencing them

If no agents were found for the selected team, inform the user and suggest they check the team configuration in the Fyso dashboard.
