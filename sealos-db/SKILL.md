---
name: sealos-db
description: >-
  Use when someone needs to manage databases on Sealos: create, list, update, scale,
  delete, start, stop, restart, check status, get connection info, or enable/disable
  public access. Triggers on "I need a database", "create a PostgreSQL on sealos",
  "scale my database", "delete the database", "show my databases",
  or "my app needs a database connection".
---

## Fixed Execution Order

**ALWAYS follow these steps in this exact order. No skipping, no reordering.**

```
Step 1: Authenticate        (get kubeconfig path, validate identity, derive API URL)
Step 2: Route                (determine which operation the user wants)
Step 3: Execute operation    (follow the operation-specific steps below)
```

Skip Step 1 if already authenticated in this conversation.

---

## Step 1: Authenticate

### 1a. Get kubeconfig file path

Ask exactly this:
> Please save your Sealos user kubeconfig to a file and tell me the path.
> Download from Sealos Console > Settings > Kubeconfig, save it (e.g., `~/sealos-kc.yaml`).
> **Do not paste the content** — just give me the file path.

**If user pastes content:** Explain that the API needs the original YAML byte-for-byte
and terminal pasting corrupts it. Ask them to save to a file instead.

**If user says `~/.kube/config`:** That's fine, proceed to 1b.

### 1b. Validate identity

Read the kubeconfig file. Parse the YAML to extract:
- `server` URL (from `clusters[0].cluster.server`)
- **User context name** (from `users[0].name` or `contexts[0].context.user`)

If user is `kubernetes-admin` or any cluster admin identity → **STOP**:
> This is a cluster admin kubeconfig. The DB API needs a Sealos user kubeconfig
> (download from Sealos Console > Settings > Kubeconfig).

### 1c. Derive API URL

Extract domain from server URL (e.g., `https://usw.sailos.io` → `usw.sailos.io`).
Set `API_URL=https://dbprovider.{domain}/api/v2alpha`.

### 1d. Validate connection

Run `sealos-db.sh list`. If 401 → kubeconfig expired, re-download.

---

## Step 2: Route

Determine the operation from user intent:

| Intent | Operation |
|--------|-----------|
| "create/deploy/set up a database" | Create |
| "list/show my databases" | List |
| "check status/connection info" | Get |
| "scale/resize/update resources" | Update |
| "delete/remove database" | Delete |
| "start/stop/restart/public access" | Action |

If ambiguous, ask one clarifying question.

---

## Step 3: Operations

### Create

**3a. Scan project context** (parallel with 3b)

Check the working directory for project files (package.json, go.mod, requirements.txt,
Cargo.toml, etc.) to understand the tech stack.

**3b. Fetch versions**

Run `sealos-db.sh list-versions` to get available database versions.

**3c. Recommend and collect config**

Based on project context, present ONE recommendation with all fields filled in:

```
Recommended database for your [framework] project:
  Type:        postgresql
  Name:        [project-name]-pg
  CPU:         1 core
  Memory:      1 GB
  Storage:     3 GB
  Replicas:    1
  Version:     postgresql-16.4.0
  Termination: delete (keeps data volumes on deletion)

Adjust anything, or confirm to create?
```

Database type recommendations:
- Web apps (Next.js, Rails, Django) → PostgreSQL
- Caching/sessions → Redis
- Flexible schemas → MongoDB
- Streaming → Kafka
- Vector/AI → Qdrant/Milvus/Weaviate

Resource tiers:
- Dev: 1 CPU, 1 GB RAM, 3 GB storage, 1 replica
- Small prod: 2 CPU, 2 GB RAM, 10 GB storage, 1 replica
- Prod HA: 2 CPU, 4 GB RAM, 20 GB storage, 3 replicas

Constraints:
- Name pattern: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`, max 63 chars
- MySQL type is `apecloud-mysql`, not `mysql`
- Termination policy (`delete` or `wipeout`) is set at creation and cannot be changed later

**3d. Create and wait**

Build JSON body:
```json
{"name":"my-db","type":"postgresql","version":"postgresql-16.4.0","quota":{"cpu":1,"memory":1,"storage":3,"replicas":1},"terminationPolicy":"delete"}
```

Run `sealos-db.sh create '<json>'`. On 201, poll `sealos-db.sh get <name>` every
5 seconds until `running`. Timeout after 2 minutes.

**3e. Show connection info and integrate**

Display connection details (host, port, username, password, connection string).
Ask if user wants them written to `.env` (append, don't overwrite), `docker-compose.yml`,
or framework config.

---

### List

Run `sealos-db.sh list`. Format as table:

```
Name            Type        Version             Status    CPU  Mem  Storage  Replicas
my-app-db       postgresql  postgresql-14.8.0   Running   1    2GB  5GB      1
cache           redis       redis-7.0.6         Running   1    1GB  3GB      1
```

Highlight abnormal statuses (Failed, Stopped).

---

### Get

If no name given, run List first, then ask which one.
Run `sealos-db.sh get {name}`. Display: name, type, version, status, quota, connection info.

---

### Update

**3a.** If no name given → List, ask which one.
**3b.** Run `sealos-db.sh get {name}`, show current specs.
**3c.** Ask what to change. Constraints:
- CPU: `1, 2, 3, 4, 5, 6, 7, 8`
- Memory: `1, 2, 4, 6, 8, 12, 16, 32` GB
- Storage: `1-300` GB, **expand only**
- Replicas: `1-20`

**3d.** Show before/after diff, confirm.
**3e.** Run `sealos-db.sh update {name} '{json}'`.

---

### Delete

**This is destructive. Maximum friction.**

**3a.** If no name given → List, ask which one.
**3b.** Run `sealos-db.sh get {name}`, show full details + termination policy.
**3c.** Explain consequences:
- `delete` policy: cluster removed, data volumes kept
- `wipeout` policy: everything removed, irreversible

**3d.** Require user to type the database name to confirm.
**3e.** Run `sealos-db.sh delete {name}`.

---

### Action (Start/Pause/Restart/Public Access)

**3a.** If no name given → List, ask which one.
**3b.** Confirm the action. For `enable-public`, warn about internet exposure.
**3c.** Run `sealos-db.sh {action} {name}`.
**3d.** For `start`: poll `sealos-db.sh get {name}` until `running`.
For `enable-public`: re-fetch and display `publicConnection`.

---

## Script

Single entry point: `scripts/sealos-db.sh`. All commands include connect/read timeouts.

| Variable | Description | Default |
|----------|-------------|---------|
| `API_URL` | Database API base URL (including `/api/v2alpha`) | (required) |
| `KUBECONFIG_PATH` | Path to kubeconfig YAML file | `~/.kube/config` |

```bash
API_URL="..." bash scripts/sealos-db.sh list-versions                                     # no auth
KUBECONFIG_PATH=~/sealos-kc.yaml API_URL="..." bash scripts/sealos-db.sh list
KUBECONFIG_PATH=~/sealos-kc.yaml API_URL="..." bash scripts/sealos-db.sh create '{...}'
KUBECONFIG_PATH=~/sealos-kc.yaml API_URL="..." bash scripts/sealos-db.sh get my-db
KUBECONFIG_PATH=~/sealos-kc.yaml API_URL="..." bash scripts/sealos-db.sh update my-db '{...}'
KUBECONFIG_PATH=~/sealos-kc.yaml API_URL="..." bash scripts/sealos-db.sh delete my-db
KUBECONFIG_PATH=~/sealos-kc.yaml API_URL="..." bash scripts/sealos-db.sh start my-db
```

## Reference Files

- `references/api-reference.md` — Condensed API reference. Read first.
- `references/openapi.json` — Complete OpenAPI spec. Read only for edge cases.

## Error Handling

**Treat each error independently.** Do NOT chain unrelated errors.

| Scenario | Action |
|----------|--------|
| Kubeconfig not found | Guide user to download from Sealos Console |
| Auth error (401) | Kubeconfig expired; re-download |
| Name conflict (409) | Suggest alternative name |
| Invalid specs | Explain constraint, suggest valid value |
| Storage shrink | Refuse, K8s limitation |
| Creation timeout (>2 min) | Offer to keep polling or check console |
| "Unsupported version" (500) | Retry WITHOUT version field |
| "namespace not found" (500) | Cluster admin kubeconfig; need Sealos user kubeconfig |

## Rules

- NEVER accept pasted kubeconfig — API requires exact original YAML; pasting corrupts it
- NEVER write kubeconfig to `~/.kube/config` — may overwrite user's existing config
- NEVER echo kubeconfig content to output
- NEVER delete without explicit name confirmation
- NEVER construct curl commands inline — always use `scripts/sealos-db.sh`
- When writing to `.env`, append, don't overwrite
- Version must come from `sealos-db.sh list-versions`. If rejected, retry without version field
- MySQL type is `apecloud-mysql`, not `mysql`
- Storage can only expand, never shrink
