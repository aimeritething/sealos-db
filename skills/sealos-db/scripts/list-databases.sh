#!/bin/bash
# Lists databases or available versions.
# Usage: API_URL=<url> [KUBECONFIG_PATH=<path>] ./list-databases.sh [--versions]
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-$HOME/.kube/config}"
API_URL="${API_URL:?ERROR: API_URL environment variable is required}"

if [ ! -f "$KUBECONFIG_PATH" ]; then
  echo "ERROR: Kubeconfig not found at $KUBECONFIG_PATH"
  exit 1
fi

ENCODED_KC=$(KUBECONFIG_PATH="$KUBECONFIG_PATH" python3 -c "
import urllib.parse, os
with open(os.environ['KUBECONFIG_PATH']) as f:
    print(urllib.parse.quote(f.read(), safe=''))
")

if [ "${1:-}" = "--versions" ]; then
  ENDPOINT="${API_URL}/databases/versions"
else
  ENDPOINT="${API_URL}/databases"
fi

RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$ENDPOINT" \
  -H "Authorization: ${ENCODED_KC}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY_RESPONSE=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
  echo "$BODY_RESPONSE" | jq . 2>/dev/null || echo "$BODY_RESPONSE"
else
  echo "ERROR: HTTP $HTTP_CODE"
  echo "$BODY_RESPONSE" | jq . 2>/dev/null || echo "$BODY_RESPONSE"
  exit 1
fi
