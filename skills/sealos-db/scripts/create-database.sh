#!/bin/bash
# Creates a new database instance on Sealos.
# Usage: API_URL=<url> [KUBECONFIG_PATH=<path>] ./create-database.sh '<json_body>'
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-$HOME/.kube/config}"
API_URL="${API_URL:?ERROR: API_URL environment variable is required}"
JSON_BODY="${1:?ERROR: JSON body argument is required}"

if [ ! -f "$KUBECONFIG_PATH" ]; then
  echo "ERROR: Kubeconfig not found at $KUBECONFIG_PATH"
  exit 1
fi

ENCODED_KC=$(KUBECONFIG_PATH="$KUBECONFIG_PATH" python3 -c "
import urllib.parse, os
with open(os.environ['KUBECONFIG_PATH']) as f:
    print(urllib.parse.quote(f.read(), safe=''))
")

echo "$JSON_BODY" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null || {
  echo "ERROR: Invalid JSON body"
  exit 1
}

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/databases" \
  -H "Authorization: ${ENCODED_KC}" \
  -H "Content-Type: application/json" \
  -d "$JSON_BODY")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY_RESPONSE=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "201" ]; then
  echo "SUCCESS"
  echo "$BODY_RESPONSE" | jq . 2>/dev/null || echo "$BODY_RESPONSE"
else
  echo "ERROR: HTTP $HTTP_CODE"
  echo "$BODY_RESPONSE" | jq . 2>/dev/null || echo "$BODY_RESPONSE"
  exit 1
fi
