---
name: sealos-template
description: >-
  Use when someone needs to deploy applications from templates on Sealos: browse
  templates, view template details, deploy from catalog, or deploy custom YAML.
  Triggers on "deploy perplexica", "show available templates", "deploy from template",
  "list Sealos apps", "deploy this YAML", or "what apps can I deploy on Sealos".
---

## Interaction Principle — MANDATORY

**NEVER output a question as plain text. ALWAYS use `AskUserQuestion` with an `options` array.**

This is a hard rule with zero exceptions:
- Every time you need user input → call `AskUserQuestion` with `options`
- Do NOT write a question as text output and wait — the user MUST see clickable options
- Do NOT output explanatory prose and then ask a question as text — call `AskUserQuestion` instead
- Keep text output before `AskUserQuestion` to one short sentence max (status update only)

**BAD** (never do this):
```
Please save your Sealos kubeconfig to a file and tell me the path.
Download from Sealos Console > Settings > Kubeconfig...
```

**GOOD** (always do this):
```
AskUserQuestion(header="Kubeconfig", question="Where is your Sealos kubeconfig?", options=[...])
```

`AskUserQuestion` always adds an implicit "Other / Type something" option automatically,
so the user can still type custom input when none of the options fit.

**Free-text matching:** When the user types free text instead of clicking an option,
match it to the closest option by intent. Examples:
- "show all", "browse all" → treat as "Browse all"
- "deploy it", "yes deploy" → treat as "Deploy now"
- "perplexica", "perplexica template" → treat as selecting that template

Never re-ask the same question because the wording didn't match exactly.

## Fixed Execution Order

**ALWAYS follow these steps in this exact order. No skipping, no reordering.**

```
Step 0: Check Memory       (try to restore auth from previous session)
Step 1: Authenticate        (only if Step 0 has no valid memory)
Step 2: Route               (determine which operation the user wants)
Step 3: Execute operation   (follow the operation-specific steps below)
Step 4: Update Memory       (save state for next session)
```

---

## Step 0: Check Memory

Check for a memory file named `sealos-template.md` in the project's auto memory directory
(the path is provided by the system environment, e.g. `~/.claude/projects/.../memory/sealos-template.md`).

**If memory file exists and contains `kubeconfig_path` + `api_url`:**
1. Verify the kubeconfig file still exists at the saved path
2. If memory has a `profile` field, ensure the script's active profile matches:
   run `node scripts/sealos-template.mjs profiles` and compare. If different,
   run `node scripts/sealos-template.mjs use <profile>` to switch first.
3. Run `node scripts/sealos-template.mjs list` (auto-loads config) to test connection
4. If works → skip Step 1. Greet with context:
   > Connected to Sealos (`{profile}`). {N} templates available.
5. If fails → proceed to Step 1, mention connection issue

**If no memory file or missing auth fields** → proceed to Step 1.

**Note:** Browsing is public (no auth needed). Auth is only validated on deploy operations.
If memory has `api_url` but no `kubeconfig_path`, browsing still works — only prompt for
kubeconfig when the user wants to deploy.

---

## Step 1: Authenticate

Run this step only if Step 0 found no valid memory.

### 1a. Get kubeconfig file path

Check if these common paths exist: `~/.kube/config`, `~/sealos-kc.yaml`, `~/kubeconfig.yaml`

**STOP. Do NOT read any kubeconfig file yet. Do NOT proceed to Step 1b.**
**You MUST call `AskUserQuestion` first and WAIT for the user to confirm which file.**

`AskUserQuestion`:
- header: "Kubeconfig"
- question: "Where is your Sealos kubeconfig file?"
- useDescription: "Download from Sealos Console > Settings > Kubeconfig, save to a file. Do not paste content."
- options: list any of the above paths that **exist on disk**, then always add:
  - `"I'll save it now — tell me where"`
- Example (if `~/.kube/config` exists):
  ```
  ["~/.kube/config", "I'll save it now — tell me where"]
  ```
- Example (if none exist):
  ```
  ["I'll save it now — tell me where"]
  ```

**Only after the user picks or types a path → proceed to Step 1b.**

**If user pastes kubeconfig content instead of a path:** Explain that the API needs the
original YAML byte-for-byte and terminal pasting corrupts it. Ask them to save to a file.

### 1b. Validate identity

Read the kubeconfig file. Parse the YAML to extract:
- `server` URL (from `clusters[0].cluster.server`)
- **User context name** (from `users[0].name` or `contexts[0].context.user`)

If user is `kubernetes-admin` or any cluster admin identity → **STOP**:
> This is a cluster admin kubeconfig. The Template API needs a Sealos user kubeconfig
> (download from Sealos Console > Settings > Kubeconfig).

### 1c. Init (derive API URL + validate connection)

Run `node scripts/sealos-template.mjs init <kubeconfig_path>`. This single command:
- Parses the kubeconfig, extracts the server URL
- **Auto-probes** candidate API URLs (tries `template.<domain>` with subdomain
  variations) and uses the first one that responds successfully
- Saves config to `~/.config/sealos-template/config.json`
- Fetches template count to verify connection

**If auto-detection fails** (error mentions "Could not auto-detect API URL"):
`AskUserQuestion`:
- header: "API URL"
- question: "Could not auto-detect API URL. What is your Sealos domain?"
- useDescription: "Find it in your browser URL bar when logged into Sealos Console (e.g., usw.sailos.io)"
- options: ["I'll check my Sealos Console"]

Then run: `node scripts/sealos-template.mjs init <kubeconfig_path> https://template.<domain>`

**If `init` succeeds:**
The response includes `profileName` and `templateCount`. Display:
> Connected to Sealos (`{profileName}`). {templateCount} templates available.

---

## Step 2: Route

Determine the operation from user intent:

| Intent | Operation |
|--------|-----------|
| "list/show/browse templates" | Browse |
| "what apps can I deploy" | Browse |
| "deploy X" / "I need X" | Deploy |
| "deploy this YAML" / "deploy custom template" | Deploy Raw |
| "show template details" / "what does X need" | Details |
| "switch cluster/profile/account" | Profile |

If ambiguous, ask one clarifying question.

---

## Step 3: Operations

### Browse

1. Run `node scripts/sealos-template.mjs list` command, get template array + `menuKeys` categories
2. If categories exist (`menuKeys` is non-empty), group templates by category, sort by `deployCount` within each
3. Display categorized list: name, description, deployCount
4. `AskUserQuestion`: top 4 categories as options (header: "Category", question: "Browse by category?")
5. After user picks category → show templates in that category
6. `AskUserQuestion`: top 4 templates as options (header: "Template", question: "Which template?")
7. After selection → proceed to Details

---

### Details

1. Run `node scripts/sealos-template.mjs get <name>` command
2. Display all fields:
   - Name, description, categories, gitRepo
   - Resource quota: CPU, Memory, Storage, NodePort
   - Required args: name, description, type (highlight required with no default)
   - Optional args: name, description, type, default value
   - Deploy count
3. `AskUserQuestion`: "Deploy this template" / "Browse more" / "Done"

---

### Deploy (`POST /templates/instances`)

1. If template name not known → run Browse first
2. Run `node scripts/sealos-template.mjs get <name>` to fetch template details with quota and args
3. Show resource requirements (quota from API response):
   ```
   Resource requirements:
     CPU:      1 vCPU
     Memory:   2.25 GiB
     Storage:  2 GiB
     NodePort: 0
   ```

4. **Ensure auth:** If not yet authenticated (no kubeconfig), run Step 1 now.
   Browse is public but deploy requires auth.

5. Collect required args (where `required: true` AND `default` is empty string):
   - For each: `AskUserQuestion` with arg description and type
   - Password/secret types (type is `"password"` or name contains KEY, SECRET, TOKEN, PASSWORD):
     no pre-filled options, user must type
   - Boolean types: options `["true", "false"]`
   - String with obvious values: suggest up to 4 options
6. Show optional args with their defaults, `AskUserQuestion`: "Use defaults (Recommended)" / "Customize"
   - If customize: iterate through optional args one by one
7. Ask instance name: `AskUserQuestion` with 2-3 suggestions (`my-{template}`, `{project}-{template}`)
   - **User can type any name — passed to API exactly as typed**
   - Constraint shown in question: lowercase, alphanumeric + hyphens, 1-63 chars
8. Display confirmation summary:
   - Template name, instance name, all args (mask password/secret values: first 3 chars + `*****`)
   - Resource requirements
9. `AskUserQuestion`: "Deploy now" / "Edit args" / "Cancel"
10. Run `node scripts/sealos-template.mjs create '<json>'` with exact `{name, template, args}` — **no modification of any values**
11. Display API response: instance name, uid, createdAt, resources list with quotas

---

### Deploy Raw (`POST /templates/raw`)

1. `AskUserQuestion`: "From a file in my project" / "I'll provide it"
2. If file → ask path, read file content as YAML string
3. `AskUserQuestion`: "Dry-run first (Recommended)" / "Deploy directly" (maps to `dryRun: true/false`)
4. If template YAML has required args without defaults → collect via `AskUserQuestion`
5. Build the JSON body: `{yaml, args, dryRun}` — **no modification**
6. Run `node scripts/sealos-template.mjs create-raw '<json>'`
   - For large JSON bodies, write to a temp file and pass the file path instead
7. If dry-run → show preview (200 response: auto-generated name, resources), then confirm actual deploy
8. If deploy → show result (201 response)

---

### Profile (Switch Cluster)

The script supports multiple Sealos clusters via named profiles. Each `init` auto-creates
a profile named after the domain (e.g., `usw.sailos`). Existing profiles are preserved.

**List profiles:** Run `node scripts/sealos-template.mjs profiles`. Display as table:

```
Profile       API URL                                          Active
usw.sailos    https://template.usw.sailos.io/api/v2alpha       ✓
cn.sailos     https://template.cn.sailos.io/api/v2alpha
```

**Switch profile:** `AskUserQuestion` with profile names as options
(header: "Profile", question: "Which cluster?"). Then run:
`node scripts/sealos-template.mjs use <name>`

**Add new cluster:** Run Step 1 (Authenticate) with a new kubeconfig.
`init` auto-creates a new profile from the domain without removing existing ones.

---

## Step 4: Update Memory

After every successful operation, update the memory file named `sealos-template.md`
in the project's auto memory directory.

**What to save and when:**

| Event | Save |
|-------|------|
| Successful auth (Step 1) | `profile`, `kubeconfig_path`, `api_url` |
| After deploy | Add instance to recent deploys |
| After browse/details | Update last browsed info |

**Memory file format:**

```markdown
# Sealos Template Memory

## Auth
- profile: usw.sailos
- kubeconfig_path: ~/sealos-kc.yaml
- api_url: https://template.usw.sailos.io/api/v2alpha

## Recent Deploys
- my-perplexica: perplexica, 2026-01-28
- my-nocodb: nocodb, 2026-01-25
```

**Rules:**
- Create the file if it doesn't exist
- Use Edit tool to update specific sections, don't overwrite the whole file unnecessarily

---

## Script

Single entry point: `scripts/sealos-template.mjs` (relative to this skill's directory).
Zero external dependencies (Node.js only).
TLS certificate verification is disabled (`rejectUnauthorized: false`) because Sealos
clusters may use self-signed certificates. See `references/api-reference.md` for details.

**The script is bundled with this skill — do NOT check if it exists. Just run it.**

**Path resolution:** This skill's directory is listed in "Additional working directories"
in the system environment. Use that path to locate the script. For example, if the
additional working directory is `/Users/x/project/.claude/skills/sealos-template/scripts`,
then run: `node /Users/x/project/.claude/skills/sealos-template/scripts/sealos-template.mjs <command>`.

**Config auto-load priority:**
1. `KUBECONFIG_PATH` + `API_URL` env vars (backwards compatible)
2. `~/.config/sealos-template/config.json` (saved by `init`)
3. Error with hint to run `init`

```bash
# Use the absolute path from "Additional working directories" — examples below use SCRIPT as placeholder
SCRIPT="/path/from/additional-working-dirs/sealos-template.mjs"

# First-time setup — auto-probes API URL, saves config, returns template count
node $SCRIPT init ~/sealos-kc.yaml

# First-time setup with manual API URL (if auto-probe fails)
node $SCRIPT init ~/sealos-kc.yaml https://template.your-domain.com

# After init, no env vars needed — config is auto-loaded
node $SCRIPT list                          # list all templates (public, no auth)
node $SCRIPT list --language=zh            # list in Chinese
node $SCRIPT get perplexica                # get template details (public, no auth)
node $SCRIPT get perplexica --language=zh  # get details in Chinese
node $SCRIPT create '{"name":"my-app","template":"perplexica","args":{"OPENAI_API_KEY":"sk-xxx"}}'
node $SCRIPT create-raw '{"yaml":"apiVersion: app.sealos.io/v1\nkind: Template\n...","dryRun":true}'
node $SCRIPT create-raw /path/to/body.json  # read JSON body from file

# Multi-cluster profile management
node $SCRIPT profiles               # list all saved profiles
node $SCRIPT use usw.sailos          # switch active profile
```

## Reference Files

- `references/api-reference.md` — API endpoints, instance name constraints, error formats. Read first.
- `references/defaults.md` — Display rules, arg collection rules, masking. Read for deploy operations.
- `references/openapi.json` — Complete OpenAPI spec. Read only for edge cases.

## Error Handling

**Treat each error independently.** Do NOT chain unrelated errors.

| HTTP Status | Error Code | Action |
|-------------|------------|--------|
| 400 | INVALID_PARAMETER | Show which field is invalid from details array, re-ask |
| 400 | INVALID_VALUE | Show validation message (e.g., name format rules), re-ask |
| 401 | AUTHENTICATION_REQUIRED | Kubeconfig invalid/expired → re-auth flow |
| 403 | PERMISSION_DENIED | Show details, suggest checking permissions |
| 404 | NOT_FOUND | Template doesn't exist in catalog, show list for user to pick |
| 409 | ALREADY_EXISTS | Instance name taken, ask for alternative name |
| 422 | INVALID_RESOURCE_SPEC | Show K8s rejection reason from details |
| 500 | KUBERNETES_ERROR / INTERNAL_ERROR | Show error message and details |
| 503 | SERVICE_UNAVAILABLE | Cluster unreachable, retry later |

## Rules

- NEVER ask a question as plain text — ALWAYS use `AskUserQuestion` with options
- NEVER read `~/.kube/config` or any kubeconfig without asking the user first via `AskUserQuestion`
- NEVER run `test -f` on the skill script — it is always present, just run it
- NEVER accept pasted kubeconfig — API requires exact original YAML; pasting corrupts it
- NEVER write kubeconfig to `~/.kube/config` — may overwrite user's existing config
- NEVER echo kubeconfig content to output
- NEVER construct HTTP requests inline — always use `scripts/sealos-template.mjs`
- NEVER modify user-provided values (name, args) before passing to API
- Mask password/secret arg values in display only (pass real values to API)
- Instance name passed to API exactly as user provides it
