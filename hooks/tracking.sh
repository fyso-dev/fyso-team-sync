#!/bin/bash
# Fyso Team Sync — Usage tracking hook v1.5
# Reads hook data from stdin (JSON) and sends to Fyso API

CONFIG="$HOME/.fyso/config.json"
[ ! -f "$CONFIG" ] && exit 0

# Read stdin to temp file (avoids quoting issues)
TMPFILE=$(mktemp)
cat > "$TMPFILE" 2>/dev/null || true

EVENT_TYPE="${1:-session}"

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

# Tokens: search everywhere in tool_response
tokens = 0
response_text = ""
if isinstance(tool_response, str):
    response_text = tool_response
elif isinstance(tool_response, dict):
    # Check nested usage
    usage = tool_response.get("usage", {})
    if isinstance(usage, dict):
        tokens = usage.get("total_tokens", 0) or 0
    # Flatten all string values to search
    for v in tool_response.values():
        if isinstance(v, str):
            response_text += v + " "
        elif isinstance(v, dict):
            for vv in v.values():
                if isinstance(vv, (str, int)):
                    response_text += str(vv) + " "

# Regex search for total_tokens in any text
if response_text:
    for pattern in [
        r"total_tokens[\":\s]+(\d+)",
        r"<total_tokens>(\d+)",
        r"total_tokens:\s*(\d+)",
    ]:
        m = re.search(pattern, response_text)
        if m:
            found = int(m.group(1))
            if found > tokens:
                tokens = found

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
