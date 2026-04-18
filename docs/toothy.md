# Toothy — AI Code Review Agent

Toothy is a webhook-driven agent that reviews pull requests opened in Gitea repositories. It runs as a Kubernetes `Deployment` in the `toothy` namespace and has read-only access to both the cluster and Gitea.

Source: [`git.madavigo.com/madavigo/toothy`](https://git.madavigo.com/madavigo/toothy)

---

## Architecture

```
Gitea webhook (PR opened / @toothy mention)
    │
    ▼
FastAPI receiver  ─── HMAC-SHA256 verify ───► 401 if invalid
    │
    ▼  (event enqueued, HTTP 200 returned immediately)
asyncio.Queue
    │
    ▼
Worker loop
    │
    ├─► format_event_as_prompt()
    │
    └─► anthropic.AsyncAnthropic.messages.create()  ← Claude API
            │
            │  tool_use loop (up to MAX_TURNS=30)
            ├─► kube_get / kube_describe / kube_logs
            ├─► gitea_read_repo / gitea_list_prs / gitea_get_pr_diff / gitea_get_issue
            ├─► search_code  (ripgrep over shallow-cloned repo)
            ├─► memory_read / memory_write  (PVC-backed notes)
            │
            └─► gitea_post_comment  ◄── only write capability
                    │
                    ▼
              PR review comment posted as toothy-bot
```

The FastAPI server lives in `src/toothy/server.py`. The agent loop lives in `src/toothy/agent.py`. Tools are in `src/toothy/tools/`.

---

## Webhook Flow

1. **Gitea fires** on `pull_request` (action `opened`) or `issue_comment` containing `@toothy`.
2. **Server** receives `POST /webhooks/gitea`, reads `X-Gitea-Signature-256`, and verifies the HMAC-SHA256 against `GITEA_WEBHOOK_SECRET`. Returns 401 immediately on mismatch.
3. **`parse_event()`** extracts repo, PR/issue number, title, and kind (`pull_request_opened` or `issue_mention`). Returns `None` for events it doesn't handle (e.g., PR synchronized, PR closed) — those get a 200 with body `{"status":"ignored"}`.
4. **Event is enqueued** in the in-process `asyncio.Queue`. The HTTP response returns `{"status":"queued"}` before any AI work starts, so Gitea never times out.
5. **Background worker** dequeues the event, calls `run_toothy(event)`, and drains the async iterator (each yield is one Claude API round-trip).
6. When Claude calls `gitea_post_comment`, the review is posted to the PR via the `toothy-bot` Gitea account.

---

## Tool Inventory

| Tool | Category | Description |
|------|----------|-------------|
| `gitea_read_repo` | Gitea (read) | Repository metadata: description, default branch, open issues, language |
| `gitea_list_prs` | Gitea (read) | List PRs by state (open/closed/all) |
| `gitea_get_pr_diff` | Gitea (read) | Unified diff for a PR; capped at `DIFF_CAP` chars (head+tail preserved) |
| `gitea_get_issue` | Gitea (read) | Issue or PR body + all comments (up to 50) |
| `gitea_post_comment` | Gitea (**write**) | Post a Markdown comment on an issue or PR — **only write operation** |
| `kube_get` | Kubernetes (read) | Get or list resources: pods, deployments, statefulsets, daemonsets, services, jobs, cronjobs, configmaps, nodes, PVCs, PVs, namespaces |
| `kube_describe` | Kubernetes (read) | Resource detail + recent events from `CoreV1Api.list_namespaced_event` |
| `kube_logs` | Kubernetes (read) | Pod logs (tail N lines); capped at `LOG_CAP` chars |
| `search_code` | Codebase | ripgrep over a shallow-cloned Gitea repo; results cached on PVC. **Requires `GITEA_TOKEN` to have `repo:read` scope on the target repo** — clone will fail silently if the token lacks access (see [Common failure modes](#common-failure-modes)). |
| `memory_read` | Memory | Read a persistent note by key from PVC (`/var/lib/toothy/memory/<key>.md`) |
| `memory_write` | Memory | Write/update a persistent note (atomic `os.replace`) |

### Output caps

Large tool outputs are truncated before being sent back to Claude, preventing context blowout:

| Config var | Default | Fallback logic |
|---|---|---|
| `TOOTHY_DIFF_CAP` | 50 000 chars | `or "50000"` so `0` / empty falls back to default |
| `TOOTHY_LOG_CAP` | 20 000 chars | `or "20000"` so `0` / empty falls back to default |

`_cap_diff()` preserves the first and last `cap//2` characters so both the opening and closing hunks of a large diff stay visible.

> **Security note:** Caps also reduce prompt-injection exposure. A diff containing adversarial instructions embedded in comments or strings is truncated before it can dominate the context window. Never remove these caps as "just an optimization."

---

## Slim Serializers

Raw Kubernetes API objects are enormous. Pod objects include `managed_fields`, null-padded spec trees, volume mounts, and environment variable arrays that can inflate a single `kube_get` response to tens of thousands of tokens.

Toothy uses two slim serializers and a managed-fields stripper:

- **`_slim_pod(obj)`** — extracts: name, namespace, phase, node name, per-container (name, image, ready, restart_count, state), conditions.
- **`_slim_workload(obj)`** — extracts: name, namespace, replicas, ready_replicas, available_replicas, conditions.
- **`_strip_managed_fields(d)`** — pops `metadata.managed_fields` from any dict; applied to all non-slim paths.

---

## Audit Log

Every Claude API round-trip is appended to a JSONL file at `/var/lib/toothy/audit/<YYYY-MM-DD>.jsonl`.

Fields per line:

```json
{
  "ts": "2026-03-18T12:34:56.789Z",
  "event_kind": "pull_request_opened",
  "repo": "madavigo/Resilience-Lab",
  "model": "claude-sonnet-4-6-20250514",
  "stop_reason": "tool_use",
  "input_tokens": 4321,
  "output_tokens": 512,
  "cache_read_tokens": 3800,
  "cache_creation_tokens": 0
}
```

To inspect today's audit log from outside the pod:

```bash
kubectl exec -n toothy deploy/toothy -- cat /var/lib/toothy/audit/$(date +%F).jsonl | jq .
```

---

## RBAC

Toothy runs as ServiceAccount `toothy-readonly` in namespace `toothy`. The ClusterRole bound to it has only `get`, `list`, and `watch` verbs — no `create`, `update`, `patch`, `delete`. The exact resources are defined in `chart/templates/rbac.yaml`.

```
ClusterRole: toothy-readonly
  verbs: [get, list, watch]
  resources: [pods, services, deployments, replicasets, statefulsets, daemonsets,
              nodes, namespaces, persistentvolumeclaims, persistentvolumes,
              configmaps, events, jobs, cronjobs]
```

The Gitea bot account (`toothy-bot`) has **no push rights** and no organization-level write access. It can only post comments.

---

## Secret Management

Secrets are never committed to git. All three required secrets are pulled from Vault via External Secrets Operator at deploy time.

| K8s Secret | ESO ExternalSecret | Vault path |
|---|---|---|
| `anthropic-api-key` / `api-key` | `anthropic-api-key` | `secret/resilience-lab/toothy` → `anthropic_api_key` |
| `gitea-token` / `token` | `gitea-token` | `secret/resilience-lab/toothy` → `gitea_token` |
| `webhook-secret` / `secret` | `webhook-secret` | `secret/resilience-lab/toothy` → `webhook_secret` |

The Helm chart references these secrets by name; it never contains values.

To write the Vault secret (requires Vault token with `update` capability on the path):

```bash
kubectl exec -n vault vault-0 -- \
  vault kv put secret/resilience-lab/toothy \
    anthropic_api_key=<value> \
    gitea_token=<value> \
    webhook_secret=<value>
```

---

## Configuration

All config is set via environment variables in `chart/values.yaml` under `env:`:

| Variable | Default | Description |
|---|---|---|
| `TOOTHY_MODEL` | `claude-sonnet-4-6` | Claude model identifier |
| `TOOTHY_MAX_TURNS` | `30` | Max tool-use turns per event |
| `TOOTHY_HANDLE` | `@toothy` | Mention string that triggers issue_mention events |
| `TOOTHY_DIFF_CAP` | `50000` | Max chars returned by `gitea_get_pr_diff` |
| `TOOTHY_LOG_CAP` | `20000` | Max chars returned by `kube_logs` |
| `GITEA_BASE_URL` | `https://git.madavigo.com` | Gitea instance base URL |

---

## Persistence

A 10 Gi PVC (`truenas-nfs` StorageClass) is mounted at `/var/lib/toothy` and contains:

```
/var/lib/toothy/
├── audit/          JSONL audit logs (one file per day)
├── cache/          Shallow-cloned repos (search_code cache)
└── memory/         Persistent notes (memory_read / memory_write)
```

The cache directory is append-only — repos are cloned once and reused. To force a fresh clone, delete the repo subdirectory:

```bash
kubectl exec -n toothy deploy/toothy -- rm -rf /var/lib/toothy/cache/madavigo/Resilience-Lab
```

---

## Operational Runbook

### Check if Toothy is running

```bash
kubectl get pods -n toothy
kubectl logs -n toothy deploy/toothy --tail=100
```

### Inspect a webhook delivery

In Gitea: **repo → Settings → Webhooks → (webhook) → Recent Deliveries**. Each delivery shows the request payload, response code, and response body. A `200 {"status":"queued"}` means Toothy accepted the event. Look in pod logs for the agent output.

> **Single-replica note:** Toothy runs at `replicaCount: 1` intentionally — a code-review agent does not need HA, and running two replicas would cause duplicate reviews. Gitea retries failed webhook deliveries automatically (up to 5 attempts, each a few minutes apart — configurable in **Site Administration → Settings**). If Toothy is mid-rollout when a PR opens, Gitea will retry and the next attempt will succeed once the new pod is ready. For a missed event after all retries are exhausted, use **Recent Deliveries → Redeliver** or comment `@toothy` to trigger an `issue_mention`.

### Re-trigger a PR review

In Gitea: **webhook → Recent Deliveries → Redeliver**. Or comment `@toothy` on the PR to trigger an `issue_mention` event.

### Manual test webhook

```bash
BODY='{"action":"opened","number":1,"pull_request":{"title":"test"},"repository":{"full_name":"madavigo/Resilience-Lab"}}'
SIG="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "<webhook-secret>" | awk '{print $2}')"
curl -s -X POST https://toothy.madavigo.com/webhooks/gitea \
  -H "Content-Type: application/json" \
  -H "X-Gitea-Event: pull_request" \
  -H "X-Gitea-Signature-256: $SIG" \
  -d "$BODY"
```

### Rebuild and redeploy the image

```bash
# From the toothy repo root (requires docker buildx with amd64 support)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  -t git.madavigo.com/madavigo/toothy:0.2.0 \
  .

# Get the new multi-arch manifest digest
docker buildx imagetools inspect git.madavigo.com/madavigo/toothy:0.2.0 \
  | grep -m1 'Digest:'

# Update chart/values.yaml: image.tag and image.digest
# Bump chart/Chart.yaml: version and appVersion
# Commit and push — ArgoCD auto-syncs the Deployment
```

### Check prompt cache efficiency

```bash
kubectl exec -n toothy deploy/toothy -- \
  cat /var/lib/toothy/audit/$(date +%F).jsonl | jq '{
    input: .input_tokens,
    cached: .cache_read_tokens,
    pct_cached: (.cache_read_tokens / .input_tokens * 100 | round)
  }'
```

The system prompt is marked `cache_control: ephemeral` so it is cached across turns in the same session (5-minute TTL). Expect `cache_read_tokens` ≈ `input_tokens` on turns 2+.

### Common failure modes

**`search_code` clone failure** — If Toothy logs `fatal: could not read Username for 'https://git.madavigo.com': terminal prompts disabled`, the `GITEA_TOKEN` in the `gitea-token` secret lacks `repo:read` access to the target repository. This happens when a new private repo is added after the token was last set, or if the token was scoped only to specific repos. Fix:
1. Verify the token has access: `curl -H "Authorization: token <token>" https://git.madavigo.com/api/v1/repos/<owner>/<repo>` — should return 200.
2. If the token is scoped correctly, force a resync of the ExternalSecret: `kubectl annotate externalsecret -n toothy gitea-token force-sync=$(date +%s) --overwrite`.
3. If the token needs broader scope, rotate it in Gitea (User Settings → Applications), update Vault at `secret/resilience-lab/toothy`, and resync ESO.

**Webhook 401 bad signature** — The `GITEA_WEBHOOK_SECRET` in the cluster does not match the secret configured in Gitea's webhook settings. Verify the Gitea webhook secret (Settings → Webhooks → Edit → Secret), then check the K8s secret value: `kubectl get secret -n toothy webhook-secret -o jsonpath='{.data.secret}' | base64 -d`.

**Agent posts no comment after queued** — The event was parsed as `None` (wrong action type, e.g., PR synchronized instead of opened). Check pod logs for `parse_event returned None`. To trigger a review manually, comment `@toothy` on the PR.

---

## Network Policy

A `NetworkPolicy` in the chart restricts Toothy's egress:

- **Egress allowed:** Anthropic API (`api.anthropic.com`), Gitea (`git.madavigo.com`), cluster DNS (port 53), Kubernetes API server.
- **Ingress allowed:** ingress-nginx → port 8080.
- All other ingress/egress is denied.
