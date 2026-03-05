#!/bin/bash
# Performs a database action (start, pause, restart, enable-public, disable-public).
# Usage: API_URL=<url> [KUBECONFIG_PATH=<path>] ./database-action.sh <database_name> <action>
#
# Actions: start, pause, restart, enable-public, disable-public
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-$HOME/.kube/config}"
API_URL="${API_URL:?ERROR: API_URL environment variable is required}"
DB_NAME="${1:?ERROR: Database name argument is required}"
ACTION="${2:?ERROR: Action argument is required (start|pause|restart|enable-public|disable-public)}"

case "$ACTION" in
  start|pause|restart|enable-public|disable-public) ;;
  *)
    echo "ERROR: Invalid action '$ACTION'. Must be one of: start, pause, restart, enable-public, disable-public"
    exit 1
    ;;
esac

if [ ! -f "$KUBECONFIG_PATH" ]; then
  echo "ERROR: Kubeconfig not found at $KUBECONFIG_PATH"
  exit 1
fi

ENCODED_KC=$(KUBECONFIG_PATH="$KUBECONFIG_PATH" python3 -c "
import urllib.parse, os
with open(os.environ['KUBECONFIG_PATH']) as f:
    print(urllib.parse.quote(f.read(), safe=''))
")

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/databases/${DB_NAME}/${ACTION}" \
  -H "Authorization: ${ENCODED_KC}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY_RESPONSE=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "204" ]; then
  echo "SUCCESS: Action '${ACTION}' on '${DB_NAME}' completed"
else
  echo "ERROR: HTTP $HTTP_CODE"
  echo "$BODY_RESPONSE" | jq . 2>/dev/null || echo "$BODY_RESPONSE"
  exit 1
fi
