#!/bin/bash
# Fyso Team Sync — Usage tracking hook
# Reads hook data from stdin (JSON) and sends to Fyso API

CONFIG="$HOME/.fyso/config.json"

if [ ! -f "$CONFIG" ]; then
  exit 0
fi

# Read stdin JSON (may be empty for SessionStart/Stop)
STDIN_DATA=$(timeout 1 cat 2>/dev/null || true)

# Read all config values in one python call
eval $(python3 -c "
import json, os
c = json.load(open(os.path.expanduser('~/.fyso/config.json')))
print(f'TOKEN={c.get(\"token\",\"\")}')
print(f'TENANT={c.get(\"tenant_id\",\"\")}')
print(f'API_URL={c.get(\"api_url\",\"https://api.fyso.dev\")}')
print(f'TEAM_NAME=\"{c.get(\"team_name\",\"\")}\"')
print(f'USER_EMAIL=\"{c.get(\"user_email\",\"\")}\"')
" 2>/dev/null)

if [ -z "$TOKEN" ] || [ -z "$TENANT" ]; then
  exit 0
fi

EVENT_TYPE="${1:-session}"

PAYLOAD=$(python3 -c "
import json, re, datetime, os, hashlib

stdin_text = '''$STDIN_DATA'''.strip()
hook = {}
if stdin_text:
    try:
        hook = json.loads(stdin_text)
    except:
        pass

# Session ID: from hook stdin, or generate deterministic one from PID+date
session_id = hook.get('session_id', '')
if not session_id:
    # Use parent PID + date as stable session identifier
    key = f'{os.getppid()}-{datetime.date.today().isoformat()}'
    session_id = hashlib.md5(key.encode()).hexdigest()[:12]

tool_name = hook.get('tool_name', '')
tool_input = hook.get('tool_input', {})
tool_response = hook.get('tool_response', {})
cwd = hook.get('cwd', os.getcwd())

# Extract agent name from tool input
agent = ''
if isinstance(tool_input, dict):
    agent = tool_input.get('subagent_type', '') or tool_input.get('name', '') or tool_input.get('description', '') or ''

# Extract tokens from tool_response
tokens = 0
if isinstance(tool_response, dict):
    usage = tool_response.get('usage', {})
    if isinstance(usage, dict):
        tokens = usage.get('total_tokens', 0)
    msg = str(tool_response.get('message', '')) + str(tool_response.get('result', ''))
    m = re.search(r'total_tokens[\":\s]+(\d+)', msg)
    if m and int(m.group(1)) > tokens:
        tokens = int(m.group(1))

# User: from config, hook data, or system username
user = '$USER_EMAIL'
if not user and isinstance(hook, dict):
    user = hook.get('user', '')
if not user:
    import getpass
    user = getpass.getuser()

data = {
    'event': '$EVENT_TYPE',
    'tool': tool_name or None,
    'agent': agent or None,
    'team_name': '$TEAM_NAME' or None,
    'user': user or None,
    'session_id': session_id or None,
    'tokens': tokens if tokens > 0 else None,
    'cwd': cwd or None,
    'timestamp': datetime.datetime.utcnow().isoformat() + 'Z'
}
data = {k: v for k, v in data.items() if v is not None}
print(json.dumps(data))
" 2>/dev/null)

if [ -n "$PAYLOAD" ]; then
  curl -s -X POST "$API_URL/api/entities/tracking/records" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Tenant-ID: $TENANT" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" >/dev/null 2>&1 &
fi

exit 0
