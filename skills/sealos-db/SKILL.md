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

1. Check if `~/.kube/config` exists by reading it
   - **Exists**: Parse the YAML to extract `server` URL (from `clusters[0].cluster.server`)
   - **Missing**: Ask user to paste content or download from Sealos console (Settings > Kubeconfig)

2. Derive API base URL from kubeconfig server:
   - Extract domain from server URL (e.g., `https://usw.sailos.io` -> `usw.sailos.io`)
   - API URL: `https://dbprovider.{domain}/api/v2alpha`
   - If format is unclear, ask the user

3. Validate auth by running `list-databases.sh`
   - Auth error (401) -> kubeconfig expired, suggest re-downloading

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

**Version** (optional): Omit to auto-select latest.

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

Run `create-database.sh`. On success (201), poll with `get-database.sh` every 5 seconds until status is `running`. Timeout after 2 minutes with guidance to check console.

### Step 4: Show Connection Info and Integrate

Display connection details (host, port, username, password, connection string).
Ask if user wants them written to `.env`, `docker-compose.yml`, or framework config.
When writing to `.env`, check if file exists and append, don't overwrite.

---

## Op B: List Databases

Run `list-databases.sh` and format output as a readable table:

```
Name            Type        Version             Status    CPU  Mem  Storage  Replicas
my-app-db       postgresql  postgresql-14.8.0   Running   1    2GB  5GB      1
cache           redis       redis-7.0.6         Running   1    1GB  3GB      1
```

Highlight abnormal statuses (Failed, Stopped) so user notices them.

Pass `--versions` flag to show available database versions instead.

---

## Op C: Get Database Details

Run `get-database.sh {name}`. If no name specified, list databases first and ask which one.

Display: name, type, version, status, quota, and full connection info (private + public if enabled).

---

## Op D: Update Database

### Step 1: Identify Target

If no database name specified, list databases and ask which one.

### Step 2: Show Current Specs

Run `get-database.sh {name}` and display current resource allocation.

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

Run `update-database.sh {name} '{json}'`. Returns 204 on success.

---

## Op E: Delete Database

**This is destructive. Apply maximum friction.**

### Step 1: Identify Target

If no name specified, list databases and ask which one.

### Step 2: Show What Will Be Deleted

Run `get-database.sh {name}` and display full details so user sees what they're losing.

### Step 3: Show Termination Policy

Run `get-database.sh {name}` to check the current `terminationPolicy`:
- `delete`: Cluster removed but **persistent volumes kept** (data recoverable)
- `wipeout`: **Everything including data removed** (irreversible)

Tell the user which policy is set so they understand the consequences.

### Step 4: Require Explicit Confirmation

Ask the user to type the database name to confirm:
"To confirm deletion, please type the database name: **my-app-db**"

### Step 5: Execute

Run `delete-database.sh {name}`. Returns 204 on success.

---

## Op F: Simple Actions (Start/Pause/Restart/Public Access)

All handled by `database-action.sh {name} {action}`.

### Start / Pause / Restart

1. If no name specified, list databases and ask which one
2. Confirm the action
3. Run `database-action.sh {name} start|pause|restart`
4. For **start**: poll `get-database.sh` until status is `running`

### Enable Public Access

1. If no name specified, list databases and ask which one
2. **Warn**: "This will expose your database to the internet. Are you sure?"
3. Run `database-action.sh {name} enable-public`
4. Re-fetch details with `get-database.sh` and display the `publicConnection` string

### Disable Public Access

1. Confirm with user
2. Run `database-action.sh {name} disable-public`

---

## Scripts

All scripts are in `scripts/` relative to this skill file.
Common environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `KUBECONFIG_PATH` | Path to kubeconfig file | `~/.kube/config` |
| `API_URL` | Database API base URL (including `/api/v2alpha`) | (required) |

### scripts/create-database.sh

```bash
API_URL="..." bash scripts/create-database.sh '{"name":"my-db","type":"postgresql","quota":{"cpu":1,"memory":1,"storage":3,"replicas":1}}'
```

### scripts/get-database.sh

```bash
API_URL="..." bash scripts/get-database.sh my-db
```

### scripts/list-databases.sh

```bash
API_URL="..." bash scripts/list-databases.sh           # list databases
API_URL="..." bash scripts/list-databases.sh --versions # list available versions
```

### scripts/update-database.sh

```bash
API_URL="..." bash scripts/update-database.sh my-db '{"quota":{"cpu":2,"memory":4}}'
```

### scripts/delete-database.sh

```bash
API_URL="..." bash scripts/delete-database.sh my-db
```

### scripts/database-action.sh

```bash
API_URL="..." bash scripts/database-action.sh my-db start
API_URL="..." bash scripts/database-action.sh my-db pause
API_URL="..." bash scripts/database-action.sh my-db restart
API_URL="..." bash scripts/database-action.sh my-db enable-public
API_URL="..." bash scripts/database-action.sh my-db disable-public
```

## Reference Files

- `references/api-reference.md` -- Condensed API reference for daily use. Read this first
  when you need to verify allowed values or understand response formats.
- `references/openapi.json` -- Complete OpenAPI spec (source of truth). Only read this
  when `api-reference.md` doesn't cover an edge case.

## Error Handling

| Scenario | Action |
|----------|--------|
| kubeconfig not found | Guide user to download from Sealos console |
| Auth error (401) | Kubeconfig expired; suggest re-downloading |
| Name conflict (409) | Suggest alternative name or list existing databases |
| Invalid specs | Explain the constraint and suggest valid values |
| Storage shrink requested | Refuse, explain it's a K8s limitation |
| Creation timeout (>2 min) | Inform user, offer to keep polling or check console |
| Delete without confirmation | NEVER proceed without explicit name confirmation |

## Important Notes

- NEVER hardcode or log passwords outside of the connection info display
- Always use the scripts in `scripts/` for API calls; don't construct curl commands inline
- The kubeconfig is sensitive -- never echo or write it to output
- When writing to `.env`, check if file exists and append, don't overwrite
- MySQL type is `apecloud-mysql`, not `mysql`
- Storage can only be expanded, never shrunk
- Delete always requires the user to type the database name to confirm
