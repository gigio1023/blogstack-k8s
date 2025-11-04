# 02. Argo CD Installation and Configuration

Argo CD installation for GitOps and App-of-Apps pattern deployment

---

## Overview

- Argo CD: Git-based declarative deployment tool
- Manual installation recommended (transparency, learning, debugging)
- Estimated time: 15 minutes

---

## Prerequisites

- k3s installation complete ([01-infrastructure.md](./01-infrastructure.md))
- SSH connection to VM established
- Project directory: `~/blogstack-k8s`
- **All commands should be run from project root directory (`~/blogstack-k8s`)**

### Git URL Verification (Required)

Verify `your-org` is not present in 3 files:

```bash
cd ~/blogstack-k8s

# 1. Root App
grep "repoURL" iac/argocd/root-app.yaml

# 2. Child Apps (6 applications)
grep "repoURL" clusters/prod/apps.yaml

# 3. Project
grep "sourceRepos" clusters/prod/project.yaml

# Check all at once
grep -r "your-org/blogstack-k8s" iac/ clusters/prod/
# No output = OK
```

If not changed → See [CUSTOMIZATION.md](./CUSTOMIZATION.md)

---

## Installation Steps

### 1. Create Namespace

```bash
kubectl create namespace argocd
```

### 2. Install Argo CD

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Creates approximately 30-50 resources (CustomResourceDefinition, ServiceAccount, Deployment, etc.)

### 3. Wait for Pod Deployment (2-3 minutes)

```bash
# Real-time monitoring
kubectl get pods -n argocd -w
# Exit with Ctrl+C

# Or use wait command
kubectl wait --for=condition=available --timeout=300s deployment -n argocd --all
```

Verify all pods are Running:

```bash
kubectl get pods -n argocd

# Expected output:
# NAME                                  READY   STATUS    RESTARTS   AGE
# argocd-application-controller-0       1/1     Running   0          2m
# argocd-dex-server-xyz                 1/1     Running   0          2m
# argocd-redis-xyz                      1/1     Running   0          2m
# argocd-repo-server-xyz                1/1     Running   0          2m
# argocd-server-xyz                     1/1     Running   0          2m
```

### 4. Get Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

Save password (optional):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d > ~/argocd-password.txt
```

### 5. Configure Argo CD (Kustomize Helm Support)

Enable Helm Chart usage in Kustomize and allow parent directory file references:

```bash
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"kustomize.buildOptions":"--enable-helm --load-restrictor LoadRestrictionsNone"}}'
```

Apply configuration:

```bash
kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd
```

### 6. Create AppProject

Create Project before Root App:

```bash
kubectl apply -f ./clusters/prod/project.yaml
```

Verify:

```bash
kubectl get appproject blog -n argocd

# Check AppProject destinations
kubectl get appproject blog -n argocd -o yaml | grep -A 15 "destinations:"
```

**Important**: `destinations` must include `argocd` namespace:
```yaml
destinations:
  - namespace: argocd  # ← Required (for Root App to create child Applications)
    server: https://kubernetes.default.svc
  - namespace: blog
    server: https://kubernetes.default.svc
  # ... other namespaces
```

### 7. Deploy Root App

```bash
kubectl apply -f ./iac/argocd/root-app.yaml
```

Verify:

```bash
kubectl get applications -n argocd

# Expected output (after ~30 seconds):
# NAME              SYNC STATUS   HEALTH STATUS   
# blogstack-root    Synced        Healthy
# observers         Synced        Progressing
# ingress-nginx     Synced        Progressing
# cloudflared       Synced        Progressing
# vault             Synced        Progressing
# vso               Synced        Progressing
# ghost             Synced        Progressing
```

---

## Application Synchronization

Auto-deployment by Sync Wave order (total 5-10 minutes):

| Wave | App | Role | Time |
|------|-----|------|------|
| `-2` | observers | Prometheus, Grafana, Loki | 3-5 min |
| `-1` | ingress-nginx | Ingress Controller | 1-2 min |
| `0` | cloudflared | Cloudflare Tunnel | 1 min |
| `1` | vault | HashiCorp Vault | 1-2 min |
| `2` | vso | Vault Secrets Operator | 1 min |
| `3` | ghost | Ghost + MySQL | 2-3 min |

### Real-time Monitoring

```bash
# Update every 5 seconds
watch -n 5 kubectl get applications -n argocd
```

### Expected Final State (after 10 minutes)

```bash
kubectl get applications -n argocd

# NAME              SYNC STATUS   HEALTH STATUS
# blogstack-root    Synced        Healthy
# observers         Synced        Healthy
# ingress-nginx     Synced        Healthy
# cloudflared       Synced        Degraded      ⚠️ Normal
# vault             Synced        Healthy
# vso               Synced        Healthy
# ghost             Synced        Degraded      ⚠️ Normal
```

Degraded reason: Vault secrets not yet injected (resolved in next step)

```bash
# Check pod status
kubectl get pods -A | grep -E "NAMESPACE|blog|vault|cloudflared"

# Expected:
# vault/vault-0: Running (0/1 normal - Sealed state)
# cloudflared/cloudflared-*: CrashLoopBackOff (waiting for secrets)
# blog/mysql-0: Running
# blog/ghost-*: CrashLoopBackOff (waiting for secrets)
```

---

## Installation Verification

```bash
echo "=== Argo CD Check ==="

# Argo CD Pods
kubectl get pods -n argocd --no-headers | awk '{print $1 " - " $3}'

# Vault Pod
kubectl get pods -n vault --no-headers | awk '{print $1 " - " $3}'

# Applications
kubectl get applications -n argocd --no-headers | awk '{print $1 " - " $2 " - " $3}'

echo "=== Check Complete ==="
```

Proceed if:
- All Argo CD Pods Running
- Vault Pod Running (0/1 normal)
- All Applications Synced
- Only cloudflared, ghost Degraded

---

## Troubleshooting

### 1. Root App "project blog which does not exist"

**Symptom:**
```bash
kubectl get application blogstack-root -n argocd
# NAME             SYNC STATUS   HEALTH STATUS
# blogstack-root   Unknown       Unknown

kubectl describe application blogstack-root -n argocd
# Message: Application referencing project blog which does not exist
```

**Cause**: AppProject not created

**Solution:**
```bash
kubectl apply -f ./clusters/prod/project.yaml
kubectl delete application blogstack-root -n argocd
kubectl apply -f ./iac/argocd/root-app.yaml
```

### 2. "do not match any of the allowed destinations"

**Symptom:**
```bash
kubectl describe application blogstack-root -n argocd
# Message: application destination server '...' and namespace 'argocd' 
#          do not match any of the allowed destinations in project 'blog'
```

**Cause**: AppProject destinations missing `argocd` namespace

**Solution:**
```bash
# Check clusters/prod/project.yaml
kubectl get appproject blog -n argocd -o yaml | grep -A 15 "destinations:"

# If argocd namespace missing, add it
# After file modification:
kubectl apply -f ./clusters/prod/project.yaml
kubectl delete application blogstack-root -n argocd
kubectl apply -f ./iac/argocd/root-app.yaml
```

### 3. "must specify --enable-helm"

**Symptom:**
```bash
kubectl get application observers -n argocd
# NAME        SYNC STATUS   HEALTH STATUS
# observers   Unknown       Healthy

kubectl describe application observers -n argocd
# Message: must specify --enable-helm
```

**Cause**: Kustomize Helm support not configured

**Solution:**
```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm --load-restrictor LoadRestrictionsNone"}}'

kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd

# Refresh application
kubectl patch application observers -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### 4. "is not in or below" (Load Restriction)

**Symptom:**
```bash
kubectl describe application observers -n argocd
# Message: file 'config/prod.env' is not in or below 'apps/observers/overlays/prod'
```

**Cause**: Kustomize blocking parent directory file reference

**Solution:** Same as #3 (add `--load-restrictor LoadRestrictionsNone`)

### 5. Argo CD Pod Pending

```bash
kubectl describe pod -n argocd <pod-name>

# Check Events:
# - Insufficient cpu/memory → VM resource shortage
# - Failed to pull image → Network issue
```

### 6. Root App OutOfSync

```bash
# Wait for auto-sync (3 min) or manual sync
kubectl patch application blogstack-root -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'
```

### 7. Git URL Still "your-org"

```bash
# 1. Delete Root App
kubectl delete application blogstack-root -n argocd

# 2. Check all Git URLs
cd ~/blogstack-k8s
grep -r "your-org/blogstack-k8s" iac/ clusters/prod/

# 3. Change Git URL (see CUSTOMIZATION.md)
# 3 files to change:
# - iac/argocd/root-app.yaml
# - clusters/prod/apps.yaml (6 locations)
# - clusters/prod/project.yaml (1 location)

OLD_URL="https://github.com/your-org/blogstack-k8s"
NEW_URL="https://github.com/<your-account>/blogstack-k8s"

sed -i "s|$OLD_URL|$NEW_URL|g" iac/argocd/root-app.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/apps.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/project.yaml

# 4. Verify
grep -r "your-org" iac/ clusters/prod/
# No output = OK

# 5. Git commit & push
git add iac/ clusters/
git commit -m "Fix: Update Git URL to personal repository"
git push origin main

# 6. Pull from VM
git pull origin main

# 7. Redeploy Root App
kubectl apply -f ./iac/argocd/root-app.yaml
```

### 8. Helm Chart Download Failure

```bash
# Network check
curl -I https://prometheus-community.github.io/helm-charts

# OCI Security List: Egress 0.0.0.0/0, TCP/443 required

# DNS check
nslookup prometheus-community.github.io
```

### 9. ImagePullBackOff

```bash
# Network check
curl -I https://registry.hub.docker.com

# Wait for automatic retry
```

---

## Argo CD UI Access (Optional)

### Port-forward Setup

VM:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

Local PC:
```bash
ssh -L 8080:localhost:8080 -i ~/.ssh/oci_key ubuntu@<VM_IP>
```

Browser: `https://localhost:8080`
- Username: `admin`
- Password: `cat ~/argocd-password.txt`

---

## Next Steps

Argo CD installation complete

Current state:
- Argo CD installed
- All Applications deployed (Synced)
- Vault Pod Running (Sealed)
- cloudflared, ghost waiting for secrets (normal)

Next: [03-vault-setup.md](./03-vault-setup.md) - Vault initialization and secret injection (15 min)

---

## Appendix: Quick Install Script

For reinstallation or test environment setup:

```bash
cd ~/blogstack-k8s

# Verify Git URL (important)
grep -r "your-org" iac/ clusters/prod/
# No output required

# Execute script
chmod +x ./scripts/bootstrap.sh
./scripts/bootstrap.sh
```

Note: Manual installation recommended for first-time setup (better learning and debugging)

---

## References

- [Argo CD Official Documentation](https://argo-cd.readthedocs.io/)
- [App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)

