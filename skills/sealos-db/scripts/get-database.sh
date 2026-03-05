#!/bin/bash
# Gets database details and connection info.
# Usage: API_URL=<url> [KUBECONFIG_PATH=<path>] ./get-database.sh <database_name>
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-$HOME/.kube/config}"
API_URL="${API_URL:?ERROR: API_URL environment variable is required}"
DB_NAME="${1:?ERROR: Database name argument is required}"

if [ ! -f "$KUBECONFIG_PATH" ]; then
  echo "ERROR: Kubeconfig not found at $KUBECONFIG_PATH"
  exit 1
fi

ENCODED_KC=$(KUBECONFIG_PATH="$KUBECONFIG_PATH" python3 -c "
import urllib.parse, os
with open(os.environ['KUBECONFIG_PATH']) as f:
    print(urllib.parse.quote(f.read(), safe=''))
")

RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${API_URL}/databases/${DB_NAME}" \
  -H "Authorization: ${ENCODED_KC}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY_RESPONSE=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
  STATUS=$(echo "$BODY_RESPONSE" | jq -r '.status // empty')
  if [ -z "$STATUS" ]; then
    echo "ERROR: Unable to parse response"
    echo "$BODY_RESPONSE" | jq . 2>/dev/null || echo "$BODY_RESPONSE"
    exit 1
  fi
  echo "$BODY_RESPONSE" | jq '{
    name: .name,
    type: .type,
    version: .version,
    status: .status,
    quota: .quota,
    connection: .connection
  }' 2>/dev/null || echo "$BODY_RESPONSE"
else
  echo "ERROR: HTTP $HTTP_CODE"
  echo "$BODY_RESPONSE" | jq . 2>/dev/null || echo "$BODY_RESPONSE"
  exit 1
fi
