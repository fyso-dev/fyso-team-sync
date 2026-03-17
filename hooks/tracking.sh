#!/bin/bash
# Fyso Team Sync — Usage tracking hook
# Sends usage events to the Fyso API for team analytics
# Reads credentials from ~/.fyso/config.json

CONFIG="$HOME/.fyso/config.json"

if [ ! -f "$CONFIG" ]; then
  exit 0
fi

TOKEN=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('token',''))" 2>/dev/null)
TENANT=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('tenant_id',''))" 2>/dev/null)
API_URL=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('api_url','https://api.fyso.dev'))" 2>/dev/null)
TEAM_ID=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('team_id',''))" 2>/dev/null)
TEAM_NAME=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('team_name',''))" 2>/dev/null)
USER_EMAIL=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('user_email',''))" 2>/dev/null)

if [ -z "$TOKEN" ] || [ -z "$TENANT" ]; then
  exit 0
fi

EVENT_TYPE="${1:-session}"
TOOL_NAME="${CLAUDE_TOOL_NAME:-unknown}"
AGENT_NAME=""
TOKENS_USED=0
SESSION_ID="${CLAUDE_SESSION_ID:-$(python3 -c "import uuid; print(str(uuid.uuid4())[:8])" 2>/dev/null)}"

if [ -n "$CLAUDE_TOOL_INPUT" ]; then
  AGENT_NAME=$(echo "$CLAUDE_TOOL_INPUT" | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  print(d.get('subagent_type','') or d.get('name','') or '')
except:
  print('')
" 2>/dev/null)
fi

# Capture token usage from tool output if available
if [ -n "$CLAUDE_TOOL_OUTPUT" ]; then
  TOKENS_USED=$(echo "$CLAUDE_TOOL_OUTPUT" | python3 -c "
import sys,json,re
try:
  text = sys.stdin.read()
  m = re.search(r'total_tokens[\":\s]+(\d+)', text)
  if m: print(m.group(1))
  else: print(0)
except:
  print(0)
" 2>/dev/null)
fi

PAYLOAD=$(python3 -c "
import json, datetime, os
data = {
  'event': '$EVENT_TYPE',
  'tool': '$TOOL_NAME',
  'agent': '$AGENT_NAME',
  'team_name': '$TEAM_NAME',
  'user': '$USER_EMAIL',
  'session_id': '$SESSION_ID',
  'tokens': int('$TOKENS_USED') if '$TOKENS_USED'.isdigit() and int('$TOKENS_USED') > 0 else None,
  'cwd': os.getcwd(),
  'timestamp': datetime.datetime.utcnow().isoformat() + 'Z'
}
data = {k: v for k, v in data.items() if v is not None and v != ''}
print(json.dumps(data))
" 2>/dev/null)

curl -s -X POST "$API_URL/api/entities/tracking/records" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" >/dev/null 2>&1 &

exit 0
