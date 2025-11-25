# Restart Applications

Procedure for restarting Argo CD Applications.

## When to use?

- When Applications are stuck in OutOfSync and cannot recover
- When you want a clean redeploy after modifying manifests
- When persistent errors occur and you want to start fresh

---

## Quick Restart (Recommended)

### Using Automated Script

```bash
# Run from project directory
cd ~/blogstack-k8s
./scripts/quick-reset.sh
```

---

## Manual Restart

Execute directly without script:

### 1. Go to Project Directory

```bash
cd ~/blogstack-k8s
```

### 2. Pull Latest Code

```bash
git pull origin main
```

### 3. Delete Root App

```bash
# Delete Root App (Child applications will be automatically deleted)
kubectl delete application blogstack-root -n argocd
```

**Note**: This command only deletes Applications. Actual workloads (Pods, Services, etc.) take some time to be deleted.

### 4. Verify Deletion (Optional)

```bash
# Wait until all Applications disappear
kubectl get applications -n argocd
# OK if only blogstack-root remains or nothing is left
```

### 5. Redeploy Root App

```bash
kubectl apply -f iac/argocd/root-app.yaml
```

### 6. Monitor Auto-Deployment

```bash
# Real-time monitoring
watch -n 5 kubectl get applications -n argocd
```

**Deployment Order** (Automated):
1. Wave -2 (3~5 min): observers
2. Wave -1 (1~2 min): observers-probes, ingress-nginx
3. Wave 0~1 (2~3 min): cloudflared, vault
4. Wave 2~3 (1~2 min): vso-operator, vso-resources
5. Wave 4 (2~3 min): ghost

**Expected Final State** (After 10 min):
```
NAME               SYNC STATUS   HEALTH STATUS
blogstack-root     Synced        Healthy
observers          Synced        Healthy
observers-probes   Synced        Healthy
ingress-nginx      Synced        Healthy
cloudflared        Synced        Degraded      ⚠️ Normal (Waiting for Vault secrets)
vault              Synced        Healthy       (0/1 Sealed Normal)
vso-operator       Synced        Healthy
vso-resources      Synced        Healthy
ghost              Synced        Degraded      ⚠️ Normal (Waiting for Vault secrets)
```

---

## Troubleshooting

### 1. Applications Not Deleted

**Symptom:**
```bash
kubectl delete application blogstack-root -n argocd
# Command hangs
```

**Fix:**
```bash
# Force delete
kubectl delete application blogstack-root -n argocd --grace-period=0 --force
```

### 2. Child Applications Not Created

**Symptom:**
```bash
kubectl get applications -n argocd
# Only blogstack-root exists, other applications are missing
```

**Cause**: AppProject missing or Git URL issue

**Fix:**
```bash
# Check AppProject
kubectl get appproject blog -n argocd

# Create if missing
kubectl apply -f clusters/prod/project.yaml

# Recreate Root App
kubectl delete application blogstack-root -n argocd
kubectl apply -f iac/argocd/root-app.yaml
```

### 3. Applications Stuck in OutOfSync

**Cause**: Previous operation is retrying

**Fix:**
```bash
# Delete and recreate the specific application (Root App will auto-recreate it)
kubectl delete application observers -n argocd

# Or recreate all
kubectl delete application blogstack-root -n argocd
sleep 10
kubectl apply -f iac/argocd/root-app.yaml
```

### 4. Workloads Not Fully Deleted

If workloads remain in the namespace:

```bash
# Delete specific namespace
kubectl delete namespace observers --grace-period=30

# Delete multiple namespaces at once
kubectl delete namespace observers blog vault vso cloudflared ingress-nginx --wait=false
```

**Note**: Deleting namespaces is not mandatory. Redeploying Applications will automatically clean up.

---

## Full Reset (Extreme Case)

Use only when the above methods fail:

```bash
# 1. Delete all applications
kubectl delete application --all -n argocd

# 2. Delete namespaces
kubectl delete namespace observers blog vault vso cloudflared ingress-nginx

# 3. Recreate AppProject
kubectl delete appproject blog -n argocd
kubectl apply -f clusters/prod/project.yaml

# 4. Redeploy Root App
kubectl apply -f iac/argocd/root-app.yaml
```

---

## FAQ

### Q: Will data be deleted?

**A**: Restarting Applications alone does not delete PVC data.
Deleting the namespace will delete PVCs.

### Q: Do I need to re-initialize Vault?

**A**:
- Restarting Applications only: Vault data persists, re-initialization NOT required.
- Deleting namespace: Vault PVC deleted, re-initialization REQUIRED ([03-vault-setup.md](./03-vault-setup.md), [07-smtp-setup.md](./07-smtp-setup.md)).

### Q: How often should I restart?

**A**:
- Normal operation: No restart needed (automated sync works).
- After Manifest changes: Just Git push for auto sync.
- On Error: Use this guide.

---

## References

- [02-argocd-setup.md](./02-argocd-setup.md): Initial Installation Guide
- [03-vault-setup.md](./03-vault-setup.md): Vault Initialization
- [07-smtp-setup.md](./07-smtp-setup.md): SMTP Email Setup
- [08-operations.md](./08-operations.md): Operations Guide
