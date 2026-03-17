#!/bin/bash
# Fyso Team Sync — Usage tracking hook v1.5
# Reads hook data from stdin (JSON) and sends to Fyso API

CONFIG="$HOME/.fyso/config.json"
[ ! -f "$CONFIG" ] && exit 0

# Read stdin to temp file (avoids quoting issues)
TMPFILE=$(mktemp)
cat > "$TMPFILE" 2>/dev/null || true

EVENT_TYPE="${1:-session}"

# Debug: log stdin to file for inspection
DEBUG_LOG="$HOME/.fyso/hook-debug.log"
if [ -f "$HOME/.fyso/debug" ]; then
  echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) === EVENT=$EVENT_TYPE ===" >> "$DEBUG_LOG"
  cat "$TMPFILE" >> "$DEBUG_LOG" 2>/dev/null
  echo "" >> "$DEBUG_LOG"
fi

# Single python call: read config + parse stdin + build payload + send
export TMPFILE EVENT_TYPE
python3 << 'PYEOF'
import json, re, datetime, os, sys, getpass, hashlib
try:
    import urllib.request
except:
    sys.exit(0)

config_path = os.path.expanduser("~/.fyso/config.json")
try:
    with open(config_path) as f:
        cfg = json.load(f)
except:
    sys.exit(0)

token = cfg.get("token", "")
tenant = cfg.get("tenant_id", "")
api_url = cfg.get("api_url", "https://api.fyso.dev")
team_name = cfg.get("team_name", "")
user_email = cfg.get("user_email", "")

if not token or not tenant:
    sys.exit(0)

# Read stdin JSON from temp file
tmpfile = os.environ.get("TMPFILE", "")
hook = {}
if tmpfile and os.path.exists(tmpfile):
    try:
        with open(tmpfile) as f:
            content = f.read().strip()
        if content:
            hook = json.loads(content)
    except:
        pass
    finally:
        try:
            os.unlink(tmpfile)
        except:
            pass

event_type = os.environ.get("EVENT_TYPE", "session")

# Session ID
session_id = hook.get("session_id", "")
if not session_id:
    key = f"{os.getppid()}-{datetime.date.today().isoformat()}"
    session_id = hashlib.md5(key.encode()).hexdigest()[:12]

# Tool info
tool_name = hook.get("tool_name", "")
tool_input = hook.get("tool_input", {}) or {}
tool_response = hook.get("tool_response", {}) or {}

# Agent name from input
agent = ""
if isinstance(tool_input, dict):
    agent = tool_input.get("subagent_type", "") or tool_input.get("name", "") or ""

# Action detail from input description
detail = ""
if isinstance(tool_input, dict):
    detail = tool_input.get("description", "") or tool_input.get("prompt", "")
    if isinstance(detail, str) and len(detail) > 200:
        detail = detail[:200] + "..."

# Tokens: extract from tool_response
tokens = 0
if isinstance(tool_response, dict):
    # Direct field (camelCase from Claude Code)
    tokens = tool_response.get("totalTokens", 0) or 0
    # Fallback: nested usage
    if not tokens:
        usage = tool_response.get("usage", {})
        if isinstance(usage, dict):
            tokens = usage.get("total_tokens", 0) or usage.get("totalTokens", 0) or 0
            if not tokens:
                tokens = (usage.get("input_tokens", 0) or 0) + (usage.get("output_tokens", 0) or 0) + (usage.get("cache_read_input_tokens", 0) or 0) + (usage.get("cache_creation_input_tokens", 0) or 0)

# User
user = user_email or getpass.getuser()

# Build payload
data = {
    "event": event_type,
    "tool": tool_name or None,
    "agent": agent or None,
    "detail": detail or None,
    "team_name": team_name or None,
    "user": user or None,
    "session_id": session_id or None,
    "tokens": tokens if tokens > 0 else None,
    "cwd": hook.get("cwd", os.getcwd()) or None,
    "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
}
data = {k: v for k, v in data.items() if v is not None}
payload = json.dumps(data).encode()

# Send async (fire and forget)
try:
    req = urllib.request.Request(
        f"{api_url}/api/entities/tracking/records",
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "X-Tenant-ID": tenant,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    urllib.request.urlopen(req, timeout=5)
except:
    pass
PYEOF

# Cleanup
rm -f "$TMPFILE" 2>/dev/null
exit 0
