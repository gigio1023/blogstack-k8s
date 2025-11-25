# 02. Argo CD Setup

Install Argo CD and deploy App-of-Apps pattern for GitOps.

## Overview

- Argo CD: Git-based declarative deployment tool
- Applications: Split into 8 parts for CRD dependency resolution
- Expected time: 15 minutes

## Prerequisites

- k3s installed (01-infrastructure.md)
- VM SSH connected
- Project directory: `~/blogstack-k8s`
- All commands should be run from the project root

### Verify Git URL Change (Required)

```bash
cd ~/blogstack-k8s

# Check for your-org (should be empty)
grep -r "your-org/blogstack-k8s" iac/ clusters/prod/
# No output = OK
```

If output exists → see CUSTOMIZATION.md

## Installation Steps

### 1. Create Namespace

```bash
kubectl create namespace argocd
```

### 2. Install Argo CD

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 3. Wait for Pods (2-3 min)

```bash
# Real-time monitoring
kubectl get pods -n argocd -w
# Ctrl+C to exit

# Or wait command
kubectl wait --for=condition=available --timeout=300s deployment -n argocd --all
```

Verify:
```bash
kubectl get pods -n argocd
# All Running
```

### 4. Get Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

### 5. Configure Argo CD (Kustomize Helm Support)

```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm --load-restrictor LoadRestrictionsNone"}}'

kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd
```

### 6. Create AppProject

```bash
kubectl apply -f ./clusters/prod/project.yaml
```

Verify:
```bash
kubectl get appproject blog -n argocd

# Check destinations (argocd namespace required)
kubectl get appproject blog -n argocd -o yaml | grep -A 15 "destinations:"
```

### 7. Deploy Root App

```bash
kubectl apply -f ./iac/argocd/root-app.yaml
```

Verify:
```bash
kubectl get applications -n argocd
```

Expected output (after 30s):
```
NAME               SYNC STATUS   HEALTH STATUS   
blogstack-root     Synced        Healthy
observers          Synced        Progressing
observers-probes   Synced        Progressing
ingress-nginx      Synced        Progressing
cloudflared        Synced        Progressing
vault              Synced        Progressing
vso-operator       Synced        Progressing
vso-resources      Synced        Progressing
ghost              Synced        Progressing
```

## Wait for Applications Sync

Sync Wave Order (Total 5-10 min):

| Wave | App | Purpose | Time |
|------|-----|---------|------|
| `-2` | observers | Prometheus, Grafana, Loki | 3-5m |
| `-1` | observers-probes | Blackbox Exporter | 30s |
| `-1` | ingress-nginx | Ingress Controller | 1-2m |
| `0` | cloudflared | Cloudflare Tunnel | 1m |
| `1` | vault | HashiCorp Vault | 1-2m |
| `2` | vso-operator | Vault Secrets Operator | 1m |
| `3` | vso-resources | Vault connection & secret mapping | 30s |
| `4` | ghost | Ghost + MySQL | 2-3m |

Real-time monitoring:
```bash
watch -n 5 kubectl get applications -n argocd
```

Expected final state (after 10m):
```bash
kubectl get applications -n argocd

# NAME               SYNC STATUS   HEALTH STATUS
# blogstack-root     Synced        Healthy
# observers          Synced        Healthy
# observers-probes   Synced        Healthy
# ingress-nginx      Synced        Healthy
# cloudflared        Synced        Degraded      ← Normal (waiting for Vault secrets)
# vault              Synced        Progressing   ← Normal (not initialized)
# vso-operator       Synced        Healthy
# vso-resources      Synced        Healthy
# ghost              Synced        Degraded      ← Normal (waiting for Vault secrets)
```

Degraded/Progressing: Vault not initialized yet (fixed in next step)

### Verify Monitoring Stack Deployment

Verify that the `observers` application has been deployed correctly.

```bash
# Verify Prometheus Operator CRDs
kubectl get crd | grep monitoring.coreos.com

# Expected output:
# prometheuses.monitoring.coreos.com
# servicemonitors.monitoring.coreos.com
# probes.monitoring.coreos.com
# podmonitors.monitoring.coreos.com

# Verify Prometheus Pod
kubectl get pods -n observers -l app.kubernetes.io/name=prometheus

# Expected output:
# prometheus-kube-prometheus-stack-prometheus-0   2/2   Running
```

> [!NOTE]
> The monitoring stack is required for configuring ServiceMonitors in [10-monitoring.md](./10-monitoring.md).

Pod status:
```bash
kubectl get pods -A | grep -E "NAMESPACE|blog|vault|cloudflared"

# vault/vault-0: 0/1 Running (Sealed - not initialized)
# cloudflared/cloudflared-*: 0/1 CreateContainerConfigError (no secrets)
# blog/mysql-0: 0/1 CreateContainerConfigError (no secrets)
# blog/ghost-*: 0/1 CreateContainerConfigError (no secrets)
```

CreateContainerConfigError is normal (Vault not initialized, secrets not created)

## Verify Installation

```bash
echo "=== Argo CD Check ==="

# Argo CD Pods
kubectl get pods -n argocd --no-headers | awk '{print $1 " - " $3}'

# Vault Pod
kubectl get pods -n vault --no-headers | awk '{print $1 " - " $3}'

# Applications
kubectl get applications -n argocd --no-headers | awk '{print $1 " - " $2 " - " $3}'

echo "=== Done ==="
```

Ready to proceed conditions:
- All Argo CD pods Running
- Vault pod Running (0/1 normal - not initialized)
- All Applications Synced (9 total)
- vault, cloudflared, ghost Degraded/Progressing (normal)

## Troubleshooting

### Root App "project blog which does not exist"

```bash
kubectl apply -f ./clusters/prod/project.yaml
kubectl delete application blogstack-root -n argocd
kubectl apply -f ./iac/argocd/root-app.yaml
```

### "do not match any of the allowed destinations"

Cause: AppProject destinations missing argocd namespace

```bash
kubectl get appproject blog -n argocd -o yaml | grep -A 15 "destinations:"

# If argocd missing, fix file then:
kubectl apply -f ./clusters/prod/project.yaml
kubectl delete application blogstack-root -n argocd
kubectl apply -f ./iac/argocd/root-app.yaml
```

### "must specify --enable-helm"

```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm --load-restrictor LoadRestrictionsNone"}}'

kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd

# Application refresh
kubectl patch application observers -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Git URL "your-org"

```bash
kubectl delete application blogstack-root -n argocd

cd ~/blogstack-k8s
OLD_URL="https://github.com/your-org/blogstack-k8s"
NEW_URL="https://github.com/<your-account>/blogstack-k8s"

sed -i "s|$OLD_URL|$NEW_URL|g" iac/argocd/root-app.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/apps.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/project.yaml

git add iac/ clusters/
git commit -m "Fix: Update Git URL"
git push origin main

git pull origin main
kubectl apply -f ./iac/argocd/root-app.yaml
```

### Helm Chart Download Failed

```bash
curl -I https://prometheus-community.github.io/helm-charts
# OCI Security List: Egress 0.0.0.0/0:443 required
```

### ImagePullBackOff

```bash
curl -I https://registry.hub.docker.com
# Wait for auto-retry
```

## Argo CD UI Access (Optional)

VM:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

Local:
```bash
ssh -L 8080:localhost:8080 -i ~/.ssh/oci_key ubuntu@<VM_IP>
```

Browser: `https://localhost:8080`
- Username: `admin`
- Password: (from step 4)

## Next Steps

Argo CD installation complete.

Current state:
- Argo CD installed
- All Applications deployed (Synced)
- VSO resources created
- Vault pod Running (0/1 - not initialized)
- cloudflared, ghost pods waiting for secrets

Next required step: Initialize Vault and inject secrets

→ [03-vault-setup.md](./03-vault-setup.md) - Vault init & secrets
