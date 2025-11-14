# 08. Operations Guide

Daily operations, monitoring, maintenance

## Service Access

### Ghost Admin

- URL: `https://yourdomain.com/ghost`
- Cloudflare Zero Trust auth (if configured)

### Grafana

```bash
kubectl port-forward -n observers svc/kube-prometheus-stack-grafana 3000:80 &
# http://localhost:3000
# admin / admin (default)
```

### Argo CD

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443 &
# https://localhost:8080
```

## Monitoring

### Prometheus Targets

```bash
kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090 &
# http://localhost:9090/targets
```

Check:
- ingress-nginx (port 10254)
- cloudflared (port 2000)
- vault (sys/metrics)
- blackbox/blog-external (external health)

### Grafana Dashboards

Built-in:
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace (Pods)
- NGINX Ingress Controller

Add custom:
1. Grafana → Dashboards → Import
2. IDs: `7587` (nginx), `11159` (Cloudflare), `12904` (Vault)

### External Health Check

```promql
probe_success{job="blog-external"}
# 1: healthy, 0: down
```

### Logs (Loki)

Grafana → Explore → Loki

```logql
# Ghost logs
{namespace="blog", app="ghost"}

# MySQL errors
{namespace="blog", app="mysql"} |= "error"

# Cloudflared
{namespace="cloudflared"}
```

## Common Issues

### Ghost Login Loop

Cause: X-Forwarded-Proto not set

```bash
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o jsonpath='{.data.use-forwarded-headers}'
# true

kubectl get ingress -n blog ghost -o jsonpath='{.spec.ingressClassName}'
# nginx
```

### Pod CrashLoopBackOff

```bash
kubectl get pods -A | grep -v Running | grep -v Completed
kubectl logs -n <namespace> <pod-name> --tail=50

# Previous container logs
kubectl logs -n <namespace> <pod-name> --previous
```

### 502 Bad Gateway

```bash
kubectl get pods -n blog
kubectl get ingress -n blog
kubectl describe ingress ghost -n blog

# Ghost health check
kubectl exec -n blog deployment/ghost -- wget -qO- http://localhost:2368
```

### CreateContainerConfigError

```bash
kubectl describe pod <pod-name> -n <namespace>
# Events: Secret "xxx" not found

# Check Vault
kubectl get pods -n vault
vault kv list kv/blog/prod

# Restart VSO
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
```

## Updates

### System Packages

```bash
ssh ubuntu@<VM_IP>
sudo apt update && sudo apt upgrade -y
```

### kubectl Plugins

```bash
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## Backups

### Manual MySQL Backup

```bash
kubectl exec -n blog mysql-0 -- mysqldump -u root -p$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.root_password}' | base64 -d) --all-databases > backup.sql
```

### Ghost Content Backup

```bash
kubectl cp blog/ghost-xxx:/var/lib/ghost/content ./ghost-content-backup
```

### Automated Backups

See `apps/ghost/optional/README.md`

## Git Sync

### Pull Changes

```bash
cd ~/blogstack-k8s
git pull origin main

# Argo CD auto-sync (wait 3m)
kubectl get applications -n argocd
```

### Manual Sync

```bash
kubectl patch application <app-name> -n argocd \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}' --type merge
```

## Vault Management

### Renew Token

```bash
export VAULT_TOKEN=$(jq -r .root_token ~/blogstack-k8s/security/vault/init-scripts/init-output.json)
```

### Update Secrets

```bash
kubectl port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR=http://127.0.0.1:8200

vault kv patch kv/blog/prod/ghost \
  url="https://newdomain.com"
```

### Unseal (After Reboot)

```bash
kubectl exec -n vault vault-0 -- vault operator unseal <KEY1>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY2>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY3>
```

## Resource Usage

### Cluster-wide

```bash
kubectl top nodes
kubectl top pods -A --sort-by=memory
kubectl top pods -A --sort-by=cpu
```

### By Namespace

```bash
kubectl top pods -n blog
kubectl top pods -n observers
```

## Change SMTP Settings

See docs/07-smtp-setup.md

```bash
vault kv patch kv/blog/prod/ghost \
  mail__from="'New Name' <newemail@yourdomain.com>"

kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
kubectl rollout restart deployment ghost -n blog
```

## Change Cloudflare Tunnel

```bash
# Generate new token (Cloudflare Dashboard)
vault kv patch kv/blog/prod/cloudflared token="NEW_TOKEN"

kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
kubectl rollout restart deployment cloudflared -n cloudflared
```

## Full Restart

```bash
cd ~/blogstack-k8s
./scripts/quick-reset.sh
```

See RESET.md for details

