#!/bin/bash
# Fyso Team Sync — Usage tracking hook v1.5
# Reads hook data from stdin (JSON) and sends to Fyso API

CONFIG="$HOME/.fyso/config.json"
[ ! -f "$CONFIG" ] && exit 0

# Read stdin to temp file (avoids quoting issues)
TMPFILE=$(mktemp)
cat > "$TMPFILE" 2>/dev/null || true

EVENT_TYPE="${1:-session}"

# Debug: save raw stdin for inspection
if [ -f "$HOME/.fyso/debug" ]; then
  echo "=== $(date -u) === EVENT=$EVENT_TYPE ===" >> "$HOME/.fyso/hook-debug.log"
  cp "$TMPFILE" "$HOME/.fyso/last-hook-stdin.json" 2>/dev/null
  echo "TMPFILE=$TMPFILE size=$(wc -c < "$TMPFILE")" >> "$HOME/.fyso/hook-debug.log"
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
user_email = cfg.get("user_email", "")

if not token or not tenant:
    sys.exit(0)

# Read stdin JSON from temp file (once)
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

# Team info from local .fyso/team.json (per project directory)
team_name = ""
hook_cwd = hook.get("cwd", os.getcwd())
try:
    team_path = os.path.join(hook_cwd, ".fyso", "team.json")
    if os.path.exists(team_path):
        with open(team_path) as tf:
            team_name = json.load(tf).get("team_name", "")
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
if event_type in ("session_start", "session_end"):
    detail = event_type.replace("_", " ")

# Tokens: extract from tool_response or transcript
tokens = 0
if isinstance(tool_response, dict):
    tokens = tool_response.get("totalTokens", 0) or 0
    if not tokens:
        usage = tool_response.get("usage", {})
        if isinstance(usage, dict):
            tokens = usage.get("total_tokens", 0) or usage.get("totalTokens", 0) or 0
            if not tokens:
                tokens = (usage.get("input_tokens", 0) or 0) + (usage.get("output_tokens", 0) or 0) + (usage.get("cache_read_input_tokens", 0) or 0) + (usage.get("cache_creation_input_tokens", 0) or 0)

# For session_end: parse transcript to sum ALL tokens in the session
session_tokens = 0
if event_type == "session_end":
    transcript_path = hook.get("transcript_path", "")
    if transcript_path and os.path.exists(transcript_path):
        try:
            total = 0
            with open(transcript_path) as tf:
                for line in tf:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                        msg = entry.get("message", {})
                        if isinstance(msg, dict):
                            u = msg.get("usage", {})
                            if isinstance(u, dict):
                                total += (u.get("input_tokens", 0) or 0) + (u.get("output_tokens", 0) or 0)
                    except:
                        continue
            if total > 0:
                session_tokens = total
        except:
            pass
    tokens = 0

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
    "session_tokens": session_tokens if session_tokens > 0 else None,
    "cwd": hook.get("cwd", os.getcwd()) or None,
    "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
}
data = {k: v for k, v in data.items() if v is not None}
payload = json.dumps(data).encode()

# Debug: log payload
debug_path = os.path.expanduser("~/.fyso/debug")
if os.path.exists(debug_path):
    log_path = os.path.expanduser("~/.fyso/hook-debug.log")
    with open(log_path, "a") as dl:
        dl.write(f"PAYLOAD: {payload.decode()}\n")

# Send
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
    resp = urllib.request.urlopen(req, timeout=5)
    resp_body = resp.read().decode()
    if os.path.exists(debug_path):
        with open(log_path, "a") as dl:
            dl.write(f"RESPONSE: {resp.status} {resp_body[:200]}\n\n")
except Exception as e:
    if os.path.exists(debug_path):
        log_path = os.path.expanduser("~/.fyso/hook-debug.log")
        with open(log_path, "a") as dl:
            dl.write(f"ERROR: {e}\n\n")
PYEOF

# Cleanup
rm -f "$TMPFILE" 2>/dev/null
exit 0
