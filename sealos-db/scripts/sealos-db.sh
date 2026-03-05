#!/bin/bash
# Sealos Database CLI - single entry point for all database operations.
#
# Usage: KUBECONFIG_PATH=<path> API_URL=<url> ./sealos-db.sh <command> [args...]
#
# Auth: KUBECONFIG_PATH - path to kubeconfig YAML file (default: ~/.kube/config)
#
# Commands:
#   create <json_body>              Create a new database
#   list                            List all databases
#   list-versions                   List available database versions (no auth needed)
#   get <name>                      Get database details and connection info
#   update <name> <json_body>       Update database resources
#   delete <name>                   Delete a database
#   start <name>                    Start a stopped database
#   pause <name>                    Pause a running database
#   restart <name>                  Restart a database
#   enable-public <name>            Enable public access
#   disable-public <name>           Disable public access
set -euo pipefail

API_URL="${API_URL:?ERROR: API_URL environment variable is required}"
CMD="${1:?ERROR: Command required. Use: create|list|list-versions|get|update|delete|start|pause|restart|enable-public|disable-public}"
shift

# --- helpers ---

get_encoded_kubeconfig() {
  local kc_path="${KUBECONFIG_PATH:-$HOME/.kube/config}"
  if [ ! -f "$kc_path" ]; then
    echo "ERROR: Kubeconfig not found at $kc_path" >&2
    exit 1
  fi
  python3 -c "
import urllib.parse, sys
with open(sys.argv[1]) as f:
    print(urllib.parse.quote(f.read(), safe=''))
" "$kc_path"
}

api_call() {
  local method="$1" endpoint="$2" expected_code="$3"
  shift 3
  # remaining args passed to curl (e.g. -H "Content-Type: ..." -d "...")
  local response http_code body

  response=$(curl -s --connect-timeout 10 --max-time 30 \
    -w "\n%{http_code}" -X "$method" "${API_URL}${endpoint}" "$@")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_code" = "$expected_code" ]; then
    if [ -n "$body" ]; then
      echo "$body" | jq . 2>/dev/null || echo "$body"
    fi
    return 0
  else
    echo "ERROR: HTTP $http_code" >&2
    if [ -n "$body" ]; then
      echo "$body" | jq . 2>/dev/null || echo "$body"
    fi >&2
    return 1
  fi
}

require_name() {
  if [ $# -eq 0 ] || [ -z "$1" ]; then
    echo "ERROR: Database name required" >&2
    exit 1
  fi
  echo "$1"
}

validate_json() {
  echo "$1" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null || {
    echo "ERROR: Invalid JSON body" >&2
    exit 1
  }
}

auth_header() {
  echo "Authorization: $(get_encoded_kubeconfig)"
}

# --- commands ---

case "$CMD" in
  list-versions)
    api_call GET "/databases/versions" 200
    ;;

  list)
    api_call GET "/databases" 200 -H "$(auth_header)"
    ;;

  get)
    name=$(require_name "${1:-}")
    result=$(api_call GET "/databases/${name}" 200 -H "$(auth_header)")
    echo "$result" | jq '{
      name, type, version, status, quota, connection
    }' 2>/dev/null || echo "$result"
    ;;

  create)
    json="${1:?ERROR: JSON body required}"
    validate_json "$json"
    api_call POST "/databases" 201 \
      -H "$(auth_header)" \
      -H "Content-Type: application/json" \
      -d "$json"
    ;;

  update)
    name=$(require_name "${1:-}")
    json="${2:?ERROR: JSON body required}"
    validate_json "$json"
    api_call PATCH "/databases/${name}" 204 \
      -H "$(auth_header)" \
      -H "Content-Type: application/json" \
      -d "$json"
    echo "SUCCESS: Database update initiated"
    ;;

  delete)
    name=$(require_name "${1:-}")
    api_call DELETE "/databases/${name}" 204 -H "$(auth_header)"
    echo "SUCCESS: Database '${name}' deleted"
    ;;

  start|pause|restart|enable-public|disable-public)
    name=$(require_name "${1:-}")
    api_call POST "/databases/${name}/${CMD}" 204 -H "$(auth_header)"
    echo "SUCCESS: Action '${CMD}' on '${name}' completed"
    ;;

  *)
    echo "ERROR: Unknown command '$CMD'" >&2
    echo "Commands: create|list|list-versions|get|update|delete|start|pause|restart|enable-public|disable-public" >&2
    exit 1
    ;;
esac
