# Application Restart

Restart Argo CD Applications

## When to Use

- Applications stuck OutOfSync
- Clean redeploy after manifest changes
- Start fresh after persistent errors

## Quick Restart (Recommended)

### Automated Script

```bash
# Run from project directory
cd ~/blogstack-k8s
./scripts/quick-reset.sh
```

## Manual Restart

Without script:

### 1. Go to Project Directory

```bash
cd ~/blogstack-k8s
```

### 2. Pull Latest

```bash
git pull origin main
```

### 3. Delete Root App

```bash
# Root app deletion cascades to child apps
kubectl delete application blogstack-root -n argocd
```

Note: This deletes Applications only. Workloads (pods, services) take time to delete.

### 4. Verify Deletion (Optional)

```bash
# Check applications
kubectl get applications -n argocd

# Watch pods terminate
kubectl get pods -A --watch
```

Press Ctrl+C to exit

### 5. Redeploy Root App

```bash
kubectl apply -f ./iac/argocd/root-app.yaml
```

### 6. Watch Auto-Deploy

```bash
watch -n 5 kubectl get applications -n argocd
```

Sync waves:
```
Wave -2: observers
Wave -1: observers-probes, ingress-nginx
Wave  0: cloudflared
Wave  1: vault
Wave  2: vso-operator
Wave  3: vso-resources
Wave  4: ghost
```

Expected time: 5-10 minutes

Expected final state:
```
blogstack-root     Synced  Healthy
observers          Synced  Healthy
observers-probes   Synced  Healthy
ingress-nginx      Synced  Healthy
cloudflared        Synced  Healthy
vault              Synced  Progressing   ← Normal (needs init/unseal)
vso-operator       Synced  Healthy
vso-resources      Synced  Healthy
ghost              Synced  Degraded      ← Normal (needs Vault)
```

## Troubleshooting

### 1. Applications Not Deleted

```bash
# Check finalizers
kubectl get application <app-name> -n argocd -o yaml | grep finalizers

# Force delete if stuck
kubectl patch application <app-name> -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete application <app-name> -n argocd
```

### 2. Child Apps Not Created

```bash
# Check Root App status
kubectl describe application blogstack-root -n argocd | grep -A 20 "Message:"

# Common causes:
# - Git URL not updated (still "your-org")
# - AppProject not created
# - Kustomize build failed

# Fix Git URL (if needed)
grep -r "your-org" iac/ clusters/prod/
```

### 3. Apps Still OutOfSync

```bash
# Hard refresh
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Or manual sync
kubectl patch application <app-name> -n argocd \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}' --type merge
```

### 4. Workloads Not Fully Deleted

```bash
# Check stuck pods
kubectl get pods -A | grep Terminating

# Namespace stuck deleting
kubectl get namespace <ns> -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/<ns>/finalize" -f -
```

Tip: Wait 5-10 minutes before force-deleting

## Full Reset (Extreme)

Complete teardown and rebuild:

```bash
# Delete Root App
kubectl delete application blogstack-root -n argocd

# Wait for all pods to terminate
kubectl get pods -A --watch

# Delete namespaces (except argocd, kube-system)
kubectl delete namespace blog cloudflared vault vso observers ingress-nginx

# Wait for namespace deletion
kubectl get namespaces --watch

# Redeploy
kubectl apply -f ./clusters/prod/project.yaml
kubectl apply -f ./iac/argocd/root-app.yaml
```

Note: PVCs (MySQL data) preserved unless manually deleted

## FAQ

### Q: Will data be deleted?

No. MySQL PVC persists. Only pods/services restart.

### Q: Need to re-init Vault?

No. Vault data persists on PVC. May need unseal if pod restarted.

### Q: How often should I restart?

Rarely. Only when debugging deployment issues.

