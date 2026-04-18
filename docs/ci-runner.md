# CI Runner — Gitea act runner

Self-hosted Gitea Actions runner deployed in-cluster so agent repos (Toothy, Lux, and future agents) can build and push Docker images without relying on GitHub Actions.

Source manifests: [`apps/platform/gitea-runner/`](../apps/platform/gitea-runner/)

---

## Architecture

```
git tag v0.x.x && git push --tags
        │
        ▼
Gitea webhook → act_runner (gitea-runner namespace)
        │
        ▼
Job pod spun up inside DinD sidecar
        │
        ├─► docker/setup-buildx-action
        ├─► docker/login-action  (REGISTRY_TOKEN secret → Gitea registry)
        ├─► docker/build-push-action  (linux/amd64, semver tag, no :latest)
        │
        ▼
Image pushed to git.madavigo.com/madavigo/<repo>:<version>
Digest printed to job log → manually update chart/values.yaml
```

---

## Components

| Component | Details |
|-----------|---------|
| Runner image | `gitea/act_runner:0.2.11` |
| DinD sidecar | `docker:27.5.1-dind` (privileged) |
| Namespace | `gitea-runner` |
| PVCs | `dind-storage` 20 Gi (layer cache), `runner-data` 1 Gi (`.runner` state) |
| Storage class | `truenas-nfs` |
| Runner labels | `ubuntu-latest`, `self-hosted` |
| Job concurrency | 2 |

---

## Security posture

### Namespace PodSecurity label: `privileged`

The DinD sidecar requires `securityContext.privileged: true` — Docker-in-Docker must
manage its own kernel namespaces and cgroups. Kubernetes PodSecurity admission offers
only three levels (`restricted` / `baseline` / `privileged`); there is no way to
allow a single privileged container while enforcing everything else. The `gitea-runner`
namespace is therefore labeled `privileged`.

Mitigating controls that bound the blast radius:

- **NetworkPolicy** — egress is restricted to DNS, Gitea at `10.10.67.1`, and external
  internet (Docker Hub, ghcr.io). The pod cannot reach the Kubernetes API server
  (`10.96.0.0/12`) or any in-cluster services (`10.244.0.0/16`).
- **`automountServiceAccountToken: false`** — even if network were breached, the runner
  has no K8s API credentials.
- **Dedicated namespace** — nothing else runs in `gitea-runner`.
- **Scoped registry tokens** — each repo's `REGISTRY_TOKEN` secret is a Gitea API token
  with `packages:write` scope only (stored in Vault under `secret/resilience-lab/<repo>`).

### Multi-tenancy path

The current DinD setup is appropriate for a single-team private cluster. If multi-tenancy
is needed in the future:

- Switch act_runner to the **Kubernetes executor** (`container.backend: kubernetes`).
  Each workflow job spawns its own isolated K8s pod; no DinD, no privileged namespace.
- Replace `docker/build-push-action` with **Kaniko** for rootless image builds inside
  those job pods.
- The namespace can then be labeled `baseline` or `restricted`.
- Workflow files (`.gitea/workflows/`) require only the build step change; overall
  structure stays the same.

---

## Registration

The runner registers with Gitea once on first start using a token stored in Vault. The
`.runner` state file is persisted on the `runner-data` PVC so re-registration is skipped
on pod restarts (avoids stale runner entries in Gitea).

To re-register from scratch (e.g. after a token rotation):

```bash
# Delete the state file and let the pod restart
kubectl exec -n gitea-runner deploy/gitea-runner -c runner -- rm /data/.runner
kubectl rollout restart deployment/gitea-runner -n gitea-runner
```

To rotate the registration token:

```bash
# 1. Generate new token in Gitea: Site Admin → Runners → Create new runner
# 2. Update Vault
vault kv patch secret/resilience-lab/gitea-runner registration-token=<new-token>
# 3. ExternalSecret will refresh within 1h, or force it:
kubectl annotate externalsecret gitea-runner-secrets -n gitea-runner \
  force-sync=$(date +%s) --overwrite
# 4. Delete .runner state and restart
kubectl exec -n gitea-runner deploy/gitea-runner -c runner -- rm /data/.runner
kubectl rollout restart deployment/gitea-runner -n gitea-runner
```

---

## Adding CI to a new agent repo

1. Copy `.gitea/workflows/release.yaml` from Toothy or Lux.
2. Update `IMAGE` env var to the new repo path.
3. In Vault, store a `packages:write` Gitea token:
   ```bash
   vault kv patch secret/resilience-lab/<repo> <repo>-git-runner-token=<token>
   ```
4. Set the Gitea repo secret (requires a `write:repository` token):
   ```bash
   curl -X PUT https://git.madavigo.com/api/v1/repos/madavigo/<repo>/actions/secrets/REGISTRY_TOKEN \
     -H "Authorization: token <write-repo-token>" \
     -H "Content-Type: application/json" \
     -d "{\"data\":\"<packages-write-token>\"}"
   ```
5. Tag a release — `git tag v0.1.0 && git push --tags` — and the workflow fires.
6. Copy the printed digest into `chart/values.yaml` and commit.

---

## Secrets

| Secret | Location | Scope |
|--------|----------|-------|
| Runner registration token | `secret/resilience-lab/gitea-runner` → `registration-token` | Gitea runner registration |
| Lux registry token | `secret/resilience-lab/lux` → `lux-git-runner-token` | `packages:write` on `madavigo/lux` |
| Toothy registry token | `secret/resilience-lab/toothy` → `toothy-git-runner-token` | `packages:write` on `madavigo/toothy` |
