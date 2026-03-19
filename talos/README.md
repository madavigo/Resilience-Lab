# Talos Machine Configurations

## Phase 1 — Generate Configs

```bash
talosctl gen config Resilience-Lab https://10.10.67.48:6443 \
  --output-dir ./talos/generated \
  --with-secrets ./talos/secrets/secrets.yaml
```

> **Note:** `generated/` is gitignored. Only patches live in this directory.

## Phase 2 — Apply Control Plane (NUC)

```bash
talosctl apply-config --insecure \
  --nodes 10.10.67.48 \
  --file talos/generated/controlplane.yaml \
  --config-patch @talos/patches/nuc-patch.yaml

talosctl bootstrap --nodes 10.10.67.48 \
  --talosconfig talos/generated/talosconfig
```

## Phase 3 — Apply Workers (Dells)

Persistent storage nodes (d01–d03):
```bash
for NODE in 10.10.67.40 10.10.67.41 10.10.67.42; do
  talosctl apply-config --insecure \
    --nodes $NODE \
    --file talos/generated/worker.yaml \
    --config-patch @talos/patches/worker-storage-patch.yaml
done
```

Ephemeral nodes (d04–d06):
```bash
for NODE in 10.10.67.43 10.10.67.44 10.10.67.45; do
  talosctl apply-config --insecure \
    --nodes $NODE \
    --file talos/generated/worker.yaml \
    --config-patch @talos/patches/worker-ephemeral-patch.yaml
done
```

## Node IP Map

| Hostname        | Role          | IP            |
|-----------------|---------------|---------------|
| resilience-nuc  | Control Plane | 10.10.67.48   |
| resilience-d01  | Worker (Ceph) | 10.10.67.40   |
| resilience-d02  | Worker (Ceph) | 10.10.67.41   |
| resilience-d03  | Worker (Ceph) | 10.10.67.42   |
| resilience-d04  | Worker (Eph)  | 10.10.67.43   |
| resilience-d05  | Worker (Eph)  | 10.10.67.44   |
| resilience-d06  | Worker (Eph)  | 10.10.67.45   |
