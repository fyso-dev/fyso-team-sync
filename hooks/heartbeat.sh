#!/bin/bash
# Fyso Team Sync — Heartbeat: periodic activity summary
# Started by SessionStart hook, runs in background every 5 minutes
# Reads transcript, summarizes recent activity, sends as tracking event

CONFIG="$HOME/.fyso/config.json"
[ ! -f "$CONFIG" ] && exit 0

# Read session info from stdin (SessionStart JSON)
STDIN_DATA=$(cat 2>/dev/null || true)

SESSION_ID=$(echo "$STDIN_DATA" | python3 -c "import sys,json; print(json.loads(sys.stdin.read().strip()).get('session_id',''))" 2>/dev/null)
TRANSCRIPT=$(echo "$STDIN_DATA" | python3 -c "import sys,json; print(json.loads(sys.stdin.read().strip()).get('transcript_path',''))" 2>/dev/null)
CWD=$(echo "$STDIN_DATA" | python3 -c "import sys,json; print(json.loads(sys.stdin.read().strip()).get('cwd',''))" 2>/dev/null)

[ -z "$SESSION_ID" ] && exit 0
[ -z "$TRANSCRIPT" ] && exit 0

# Write PID file so Stop hook can kill us
PIDFILE="$HOME/.fyso/heartbeat.pid"
echo $$ > "$PIDFILE"

# Heartbeat loop
while true; do
  sleep 300  # 5 minutes

  # Check if transcript still exists (session alive)
  [ ! -f "$TRANSCRIPT" ] && break

  python3 << 'PYEOF'
import json, os, sys, datetime

config_path = os.path.expanduser("~/.fyso/config.json")
try:
    cfg = json.load(open(config_path))
except:
    sys.exit(0)

token = cfg.get("token", "")
tenant = cfg.get("tenant_id", "")
api_url = cfg.get("api_url", "https://api.fyso.dev")
team_name = cfg.get("team_name", "")
user_email = cfg.get("user_email", "")
session_id = os.environ.get("SESSION_ID", "")
transcript = os.environ.get("TRANSCRIPT", "")
cwd = os.environ.get("CWD", "")

if not token or not tenant or not transcript:
    sys.exit(0)

# Read last 50 lines of transcript to understand recent activity
try:
    lines = []
    with open(transcript) as f:
        for line in f:
            lines.append(line.strip())
    recent = lines[-50:] if len(lines) > 50 else lines
except:
    sys.exit(0)

# Extract recent tool calls and assistant messages
tools_used = []
last_text = ""
for line in recent:
    try:
        entry = json.loads(line)
        msg = entry.get("message", {})
        if not isinstance(msg, dict):
            continue
        content = msg.get("content", [])
        if isinstance(content, list):
            for c in content:
                if isinstance(c, dict):
                    if c.get("type") == "tool_use":
                        name = c.get("name", "")
                        if name and name not in tools_used[-3:]:
                            tools_used.append(name)
                    if c.get("type") == "text" and msg.get("role") == "assistant":
                        t = c.get("text", "").strip()
                        if t and len(t) > 5:
                            last_text = t[:100]
    except:
        continue

# Build short summary
parts = []
if tools_used:
    recent_tools = tools_used[-5:]
    parts.append(", ".join(recent_tools))
if last_text:
    summary = last_text.split("\n")[0][:80]
    parts.append(summary)

detail = " | ".join(parts) if parts else "idle"
if len(detail) > 200:
    detail = detail[:200]

# Count tokens since session start
total_tokens = 0
for line in lines:
    try:
        entry = json.loads(line)
        msg = entry.get("message", {})
        if isinstance(msg, dict):
            u = msg.get("usage", {})
            if isinstance(u, dict):
                total_tokens += (u.get("input_tokens", 0) or 0) + (u.get("output_tokens", 0) or 0)
    except:
        continue

import urllib.request
data = {
    "event": "heartbeat",
    "detail": detail,
    "team_name": team_name or None,
    "user": user_email or os.environ.get("USER", ""),
    "session_id": session_id or None,
    "tokens": total_tokens if total_tokens > 0 else None,
    "cwd": cwd or None,
    "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
}
data = {k: v for k, v in data.items() if v is not None}

try:
    req = urllib.request.Request(
        f"{api_url}/api/entities/tracking/records",
        data=json.dumps(data).encode(),
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

done

# Cleanup
rm -f "$PIDFILE" 2>/dev/null
