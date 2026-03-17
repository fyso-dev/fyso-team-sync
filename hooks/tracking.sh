#!/bin/bash
# Fyso Team Sync — Usage tracking hook
# Reads hook data from stdin (JSON) and sends to Fyso API

CONFIG="$HOME/.fyso/config.json"

if [ ! -f "$CONFIG" ]; then
  exit 0
fi

# Read stdin JSON
STDIN_DATA=$(cat)

# Read config
TOKEN=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('token',''))" 2>/dev/null)
TENANT=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('tenant_id',''))" 2>/dev/null)
API_URL=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('api_url','https://api.fyso.dev'))" 2>/dev/null)
TEAM_NAME=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('team_name',''))" 2>/dev/null)
USER_EMAIL=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('user_email',''))" 2>/dev/null)

if [ -z "$TOKEN" ] || [ -z "$TENANT" ]; then
  exit 0
fi

EVENT_TYPE="${1:-session}"

PAYLOAD=$(echo "$STDIN_DATA" | python3 -c "
import sys, json, re, datetime, os

stdin_text = sys.stdin.read().strip()
hook = {}
if stdin_text:
    try:
        hook = json.loads(stdin_text)
    except:
        pass

session_id = hook.get('session_id', '')
tool_name = hook.get('tool_name', 'unknown')
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
    # Check for usage in response
    usage = tool_response.get('usage', {})
    if isinstance(usage, dict):
        tokens = usage.get('total_tokens', 0)
    # Check for tokens in message/result text
    msg = str(tool_response.get('message', '')) + str(tool_response.get('result', ''))
    m = re.search(r'total_tokens[\":\s]+(\d+)', msg)
    if m and int(m.group(1)) > tokens:
        tokens = int(m.group(1))

data = {
    'event': '$EVENT_TYPE',
    'tool': tool_name,
    'agent': agent,
    'team_name': '$TEAM_NAME',
    'user': '$USER_EMAIL',
    'session_id': session_id,
    'tokens': tokens if tokens > 0 else None,
    'cwd': cwd,
    'timestamp': datetime.datetime.utcnow().isoformat() + 'Z'
}
data = {k: v for k, v in data.items() if v is not None and v != ''}
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
