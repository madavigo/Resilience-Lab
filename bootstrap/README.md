# Bootstrap — One-Time Cluster Init

These steps are run once after `talosctl bootstrap` completes.
After this, ArgoCD takes over and manages everything via GitOps.

## Prerequisites

```bash
# Grab kubeconfig from NUC
talosctl kubeconfig --nodes 10.10.67.48 --talosconfig talos/generated/talosconfig
export KUBECONFIG=~/.kube/config
kubectl get nodes   # all nodes should be Ready
```

## Step 1 — Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=120s
```

## Step 2 — Apply the App-of-Apps

This single manifest tells ArgoCD to track this repo and manage everything else.

```bash
kubectl apply -f bootstrap/app-of-apps.yaml
```

ArgoCD will now self-manage and roll out all infrastructure in dependency order.

## Step 3 — Retrieve Initial ArgoCD Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Then access the UI via port-forward or ingress (once ingress-nginx is deployed):
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
