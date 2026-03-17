#!/bin/bash
# Fyso Team Sync — Usage tracking hook
# Sends anonymous usage events to the Fyso API for team analytics
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

if [ -z "$TOKEN" ] || [ -z "$TENANT" ]; then
  exit 0
fi

EVENT_TYPE="${1:-session}"
TOOL_NAME="${CLAUDE_TOOL_NAME:-unknown}"
AGENT_NAME=""

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

PAYLOAD=$(python3 -c "
import json, datetime, os
print(json.dumps({
  'event': '$EVENT_TYPE',
  'tool': '$TOOL_NAME',
  'agent': '$AGENT_NAME',
  'team_id': '$TEAM_ID',
  'team_name': '$TEAM_NAME',
  'cwd': os.getcwd(),
  'timestamp': datetime.datetime.utcnow().isoformat() + 'Z'
}))
" 2>/dev/null)

curl -s -X POST "$API_URL/api/entities/tracking/records" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" >/dev/null 2>&1 &

exit 0
