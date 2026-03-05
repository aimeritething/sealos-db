---
name: sealos-db
description: >-
  Use when someone needs to manage databases on Sealos: create, list, update, scale,
  delete, start, stop, restart, check status, get connection info, or enable/disable
  public access. Triggers on "I need a database", "create a PostgreSQL on sealos",
  "scale my database", "delete the database", "show my databases",
  or "my app needs a database connection".
---

## What This Skill Does

Manages database instances on the Sealos platform. Supports the full lifecycle:
create, list, inspect, update, delete, start/stop/restart, and public access control.

## Your Role

You are NOT just executing scripts. You add value at every step:

- **Understand intent**: "I want to deploy a blog" -> recognize they need a database, guide them
- **Smart recommendations**: Based on project context, recommend database type and resource specs
- **Post-creation integration**: Write connection info into `.env`, `docker-compose.yml`, or framework config
- **Error explanation**: Explain failures and suggest next steps, don't show raw errors
- **Safety**: Destructive operations (delete, wipeout) require explicit confirmation

## Operation Routing

Based on user intent, perform the matching operation:

| Intent | Operation | Section |
|--------|-----------|---------|
| "create/deploy/set up a database" | Create | Op A |
| "list/show my databases" | List | Op B |
| "check status/connection info" | Detail | Op C |
| "scale/resize/update resources" | Update | Op D |
| "delete/remove database" | Delete | Op E |
| "start/resume database" | Start | Op F |
| "stop/pause database" | Pause | Op F |
| "restart database" | Restart | Op F |
| "enable public/external access" | Enable Public | Op F |
| "disable public access" | Disable Public | Op F |

If intent is ambiguous, ask one clarifying question.

---

## Shared: Kubeconfig Setup

Every operation starts here. Skip if already done in this conversation.

**CRITICAL: Do NOT write kubeconfig to any file.** The script accepts kubeconfig
via stdin using a heredoc -- no temp files, no disk writes.

### Step 1: Get kubeconfig

Ask: "Do you have a Sealos user kubeconfig? It's usually downloaded from
Sealos Console > Settings > Kubeconfig. You can paste it here or point me to the file."

Three possible inputs:
- **User pastes URL-encoded content** (starts with `apiVersion%3A`): Decode to raw YAML first.
- **User pastes raw YAML** (starts with `apiVersion:`): Use directly.
- **User gives a file path**: Use `KUBECONFIG_PATH=<path>` instead of stdin.

For pasted content, pass via heredoc to the script. This avoids writing any files:
```bash
API_URL="..." bash scripts/sealos-db.sh list <<'KUBECONFIG'
apiVersion: v1
clusters:
  ...
KUBECONFIG
```

**NEVER pass large kubeconfig strings through shell variables or env vars** -- they
get corrupted by terminal line wrapping and shell quoting.
Always use heredocs (`<<'KUBECONFIG'`) which handle large content reliably.

### Step 2: Validate identity

Parse the kubeconfig YAML (decode if needed) to extract:
a. `server` URL (from `clusters[0].cluster.server`)
b. **User context name** (from `users[0].name` or `contexts[0].context.user`).
   If the user is `kubernetes-admin` or any other cluster admin identity,
   **STOP immediately** and tell the user:
   > This is a cluster admin kubeconfig, not a Sealos user kubeconfig.
   > The DB API needs a Sealos user kubeconfig (download from Sealos Console > Settings > Kubeconfig).

   Do NOT proceed with API calls -- they will fail with "namespace not found".

### Step 3: Derive API URL

Extract domain from server URL (e.g., `https://usw.sailos.io` -> `usw.sailos.io`).
API URL: `https://dbprovider.{domain}/api/v2alpha`. If format is unclear, ask the user.

### Step 4: Validate auth

Run `sealos-db.sh list`.
- Auth error (401) -> kubeconfig expired, suggest re-downloading
- **Empty array `[]` is NOT proof of valid auth** -- the API may return empty
  for non-existent namespaces without erroring. Rely on step 2b for validation.

---

## Op A: Create Database

### Step 1: Collect Configuration

Gather through conversation with smart defaults:

**Database type** (required):
- Common: `postgresql`, `mongodb`, `apecloud-mysql`, `redis`
- All: `postgresql`, `mongodb`, `apecloud-mysql`, `redis`, `kafka`, `qdrant`, `nebula`, `weaviate`, `milvus`, `pulsar`, `clickhouse`
- Recommend by stack: Rails/Django -> PostgreSQL, caching -> Redis, streaming -> Kafka, AI/vector -> Qdrant/Milvus/Weaviate

**Instance name** (required):
- Suggest default from project name or type (e.g., `my-project-pg`)
- Pattern: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`, max 63 chars

**Resource specs** (use defaults unless user specifies):
- Dev: 1 CPU, 1 GB RAM, 3 GB storage, 1 replica
- Small prod: 2 CPU, 2 GB RAM, 10 GB storage, 1 replica
- Prod HA: 2 CPU, 4 GB RAM, 20 GB storage, 3 replicas

**Version** (optional):
- Run `sealos-db.sh list-versions` (no auth required) to get available versions.
- Pick the latest version for the chosen database type from the list.
- If omitted, the API auto-selects latest, but specifying it explicitly is preferred
  so the user sees exactly what will be deployed.
- The version string must match a value from the versions list exactly.

**Termination policy** (optional, default `delete`):
- `delete`: On future deletion, removes the cluster but **keeps persistent volumes** (data recoverable)
- `wipeout`: On future deletion, removes **everything including data** (irreversible)
- Set at creation time and **cannot be changed later**. Explain the difference and ask if the default is acceptable.

### Step 2: Confirm

Show summary and ask for confirmation:

```
Database Configuration:
  Type:     postgresql
  Name:     my-app-db
  CPU:      1 core
  Memory:   1 GB
  Storage:  3 GB
  Replicas: 1
  Version:  (latest)
```

### Step 3: Create and Wait

Build the full JSON body including the `version` field from the versions list:

```json
{"name":"my-db","type":"postgresql","version":"postgresql-14.8.0","quota":{"cpu":1,"memory":1,"storage":3,"replicas":1},"terminationPolicy":"delete"}
```

Run `sealos-db.sh create '<json>'`. On success (201), poll with `sealos-db.sh get` every 5 seconds until status is `running`. Timeout after 2 minutes with guidance to check console.

### Step 4: Show Connection Info and Integrate

Display connection details (host, port, username, password, connection string).
Ask if user wants them written to `.env`, `docker-compose.yml`, or framework config.
When writing to `.env`, check if file exists and append, don't overwrite.

---

## Op B: List Databases

Run `sealos-db.sh list` and format output as a readable table:

```
Name            Type        Version             Status    CPU  Mem  Storage  Replicas
my-app-db       postgresql  postgresql-14.8.0   Running   1    2GB  5GB      1
cache           redis       redis-7.0.6         Running   1    1GB  3GB      1
```

Highlight abnormal statuses (Failed, Stopped) so user notices them.

Use `sealos-db.sh list-versions` to show available database versions instead.

---

## Op C: Get Database Details

Run `sealos-db.sh get {name}`. If no name specified, list databases first and ask which one.

Display: name, type, version, status, quota, and full connection info (private + public if enabled).

---

## Op D: Update Database

### Step 1: Identify Target

If no database name specified, list databases and ask which one.

### Step 2: Show Current Specs

Run `sealos-db.sh get {name}` and display current resource allocation.

### Step 3: Collect Changes

Ask what to change. Explain constraints:
- **CPU**: allowed values `1, 2, 3, 4, 5, 6, 7, 8`
- **Memory**: allowed values `1, 2, 4, 6, 8, 12, 16, 32` GB
- **Storage**: `1-300` GB, **can only expand, never shrink**
- **Replicas**: `1-20`

If user requests shrinking storage, refuse and explain it's a Kubernetes limitation.

### Step 4: Confirm with Before/After

```
Resource Update for "my-app-db":
              Before    After
  CPU:        1 core    2 cores
  Memory:     1 GB      4 GB
  Storage:    3 GB      (unchanged)
  Replicas:   1         (unchanged)
```

### Step 5: Execute

Run `sealos-db.sh update {name} '{json}'`. Returns 204 on success.

---

## Op E: Delete Database

**This is destructive. Apply maximum friction.**

### Step 1: Identify Target

If no name specified, list databases and ask which one.

### Step 2: Show What Will Be Deleted

Run `sealos-db.sh get {name}` and display full details so user sees what they're losing.

### Step 3: Show Termination Policy

Run `sealos-db.sh get {name}` to check the current `terminationPolicy`:
- `delete`: Cluster removed but **persistent volumes kept** (data recoverable)
- `wipeout`: **Everything including data removed** (irreversible)

Tell the user which policy is set so they understand the consequences.

### Step 4: Require Explicit Confirmation

Ask the user to type the database name to confirm:
"To confirm deletion, please type the database name: **my-app-db**"

### Step 5: Execute

Run `sealos-db.sh delete {name}`. Returns 204 on success.

---

## Op F: Simple Actions (Start/Pause/Restart/Public Access)

All handled by `sealos-db.sh {action} {name}`.

### Start / Pause / Restart

1. If no name specified, list databases and ask which one
2. Confirm the action
3. Run `sealos-db.sh start|pause|restart {name}`
4. For **start**: poll `sealos-db.sh get {name}` until status is `running`

### Enable Public Access

1. If no name specified, list databases and ask which one
2. **Warn**: "This will expose your database to the internet. Are you sure?"
3. Run `sealos-db.sh enable-public {name}`
4. Re-fetch details with `sealos-db.sh get {name}` and display the `publicConnection` string

### Disable Public Access

1. Confirm with user
2. Run `sealos-db.sh disable-public {name}`

---

## Script

Single entry point: `scripts/sealos-db.sh`. All commands include connect/read timeouts.

Environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `API_URL` | Database API base URL (including `/api/v2alpha`) | (required) |
| `KUBECONFIG_PATH` | Path to kubeconfig file (fallback when stdin not used) | `~/.kube/config` |
| stdin | Raw kubeconfig YAML piped via heredoc (preferred) | |

Usage with stdin (preferred -- no files written):

```bash
API_URL="..." bash scripts/sealos-db.sh list <<'KUBECONFIG'
<raw kubeconfig YAML>
KUBECONFIG

API_URL="..." bash scripts/sealos-db.sh create '{"name":"my-db",...}' <<'KUBECONFIG'
<raw kubeconfig YAML>
KUBECONFIG
```

Usage with file path (when user points to an existing file):

```bash
API_URL="..." bash scripts/sealos-db.sh list-versions                          # no auth needed
KUBECONFIG_PATH="/path/to/kc.yaml" API_URL="..." bash scripts/sealos-db.sh list
```
```

## Reference Files

- `references/api-reference.md` -- Condensed API reference for daily use. Read this first
  when you need to verify allowed values or understand response formats.
- `references/openapi.json` -- Complete OpenAPI spec (source of truth). Only read this
  when `api-reference.md` doesn't cover an edge case.

## Error Handling

**CRITICAL: Treat each error independently.** When a retry also fails, analyze the
NEW error message on its own merits. Do NOT chain unrelated errors into a single
conclusion. Each API call failure should be diagnosed from its own error response.

| Scenario | Action |
|----------|--------|
| kubeconfig not found | Guide user to download from Sealos console |
| Auth error (401) | Kubeconfig expired; suggest re-downloading |
| Name conflict (409) | Suggest alternative name or list existing databases |
| Invalid specs | Explain the constraint and suggest valid values |
| Storage shrink requested | Refuse, explain it's a K8s limitation |
| Creation timeout (>2 min) | Inform user, offer to keep polling or check console |
| Delete without confirmation | NEVER proceed without explicit name confirmation |
| "Unsupported version" (500) | Server-side issue with a listed version; retry WITHOUT the version field to let API auto-select |
| "namespace not found" (500) | Kubeconfig is a cluster admin kubeconfig, not a Sealos user kubeconfig. Ask user to download their user kubeconfig from Sealos Console > Settings > Kubeconfig |

## Important Notes

- NEVER hardcode or log passwords outside of the connection info display
- Always use `scripts/sealos-db.sh` for API calls; don't construct curl commands inline
- **NEVER write kubeconfig to any file** -- pass via stdin heredoc to the script
- **NEVER pass large strings through shell variables** -- use heredocs instead
- The kubeconfig is sensitive -- never echo it to output
- When writing to `.env`, check if file exists and append, don't overwrite
- Version must come from `sealos-db.sh list-versions` output. If a listed version is rejected by the server, retry without the version field
- When an API call fails, diagnose that specific error. Do NOT assume a second failure has the same root cause as the first
- MySQL type is `apecloud-mysql`, not `mysql`
- Storage can only be expanded, never shrunk
- Delete always requires the user to type the database name to confirm
