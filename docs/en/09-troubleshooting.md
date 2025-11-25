# 09. Troubleshooting

## Vault

### Pod CrashLoopBackOff

```bash
kubectl logs -n vault vault-0
kubectl get pvc -n vault
# Check Bound status
```

### Sealed State

```bash
kubectl exec -n vault vault-0 -- vault operator unseal <KEY1>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY2>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY3>
```

### Token Expired

```bash
export VAULT_TOKEN=$(jq -r .root_token ~/blogstack-k8s/security/vault/init-scripts/init-output.json)
```

## Ingress-nginx

### Ingress Not Created (x509 error)

```bash
CA=$(kubectl get secret ingress-nginx-admission -n ingress-nginx -o jsonpath='{.data.ca}')
kubectl patch validatingwebhookconfiguration ingress-nginx-admission \
  --type='json' \
  -p='[{"op": "add", "path": "/webhooks/0/clientConfig/caBundle", "value":"'$CA'"}]'

kubectl patch application ghost -n argocd \
  -p '{"operation": {"sync": {"revision": "HEAD"}}}' --type merge
```

## Cloudflared

### Verify with Docker Before Deploy

```bash
TUNNEL_TOKEN=$(kubectl get secret cloudflared-token -n cloudflared -o jsonpath='{.data.token}' | base64 -d)
echo "Token length: ${#TUNNEL_TOKEN}"  # 184

docker run --rm docker.io/cloudflare/cloudflared:2025.10.0 \
  tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"
# Should see: Connection registered
```

With metrics:
```bash
docker run --rm -p 2000:2000 \
  -e TUNNEL_METRICS=0.0.0.0:2000 \
  docker.io/cloudflare/cloudflared:2025.10.0 \
  tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"

curl http://localhost:2000/metrics
```

### Pod CrashLoopBackOff

```bash
kubectl logs -n cloudflared -l app=cloudflared

# Common causes:
# - Invalid token
# - Tunnel deleted (check Cloudflare Dashboard)
```

## Ghost

### CrashLoopBackOff

```bash
kubectl logs -n blog deployment/ghost --tail=100

# Common causes:
# - MySQL connection failed
# - database__connection__password mismatch

# Check MySQL passwords
kubectl get secret -n blog ghost-env -o jsonpath='{.data.database__connection__password}' | base64 -d
kubectl get secret -n blog mysql-secret -o jsonpath='{.data.password}' | base64 -d
# Must match
```

### 503 Service Unavailable

```bash
kubectl get pods -n blog
kubectl get ingress -n blog
kubectl describe ingress ghost -n blog
```

### "Failed to send email"

```bash
kubectl logs -n blog deployment/ghost | grep -i mail

# Check SMTP config
kubectl get secret -n blog ghost-env -o jsonpath='{.data.mail__options__auth__pass}' | base64 -d

# Check Vault
vault kv get -format=json kv/blog/prod/ghost | jq -r '.data.data | keys | .[]' | grep mail__
```

## MySQL

### Pod Pending

```bash
kubectl describe pod mysql-0 -n blog
# Events: Check PVC Bound

kubectl get pvc -n blog
# STATUS: Bound
```

### Connection Failed

```bash
kubectl exec -n blog mysql-0 -- mysql \
  -u root \
  -p$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.root_password}' | base64 -d) \
  -e "SELECT 1;"
```

## Argo CD

### Application OutOfSync

```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd | grep -A 10 "Message:"

# Manual sync
kubectl patch application <app-name> -n argocd \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}' --type merge
```

### "project blog which does not exist"

```bash
kubectl apply -f ./clusters/prod/project.yaml
kubectl delete application blogstack-root -n argocd
kubectl apply -f ./iac/argocd/root-app.yaml
```

## Monitoring / CRD

### ServiceMonitor/Probe failures due to missing Prometheus Operator/Grafana CRDs

```bash
kubectl get crd \
  servicemonitors.monitoring.coreos.com \
  prometheusrules.monitoring.coreos.com \
  prometheuses.monitoring.coreos.com \
  alertmanagers.monitoring.coreos.com \
  podmonitors.monitoring.coreos.com \
  probes.monitoring.coreos.com
# If any NotFound appears, CRDs are missing.

# Sync observers with ServerSideApply enabled
kubectl patch application observers -n argocd \
  -p '{"spec":{"syncPolicy":{"syncOptions":["CreateNamespace=true","PruneLast=true","SkipDryRunOnMissingResource=true","ServerSideApply=true"]}}}' \
  --type merge
kubectl patch application observers -n argocd -p '{"operation":{"sync":{"revision":"HEAD"}}}' --type merge
```

### ingress-nginx ServiceMonitor ID conflict

```bash
# Helm already creates the ServiceMonitor via values, so the overlay manifest must be removed.
# Symptom: "namespace transformation produces ID conflict"

# Fix: remove apps/ingress-nginx/overlays/prod/servicemonitor.yaml
#      and drop it from the kustomization resources list
```

## VSO

### Secrets Not Created

```bash
kubectl get vaultstaticsecret -n vso
kubectl describe vaultstaticsecret <name> -n vso

# Restart VSO
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator

# Check after 30s
kubectl get secrets -n blog
```

## Network

### External Access Failed

```bash
# Check DNS
dig yourdomain.com +short

# Check Cloudflare Tunnel
kubectl logs -n cloudflared -l app=cloudflared | grep "Connection registered"

# Check ingress
kubectl get ingress -n blog

# Check Ghost pod
kubectl get pods -n blog
```

### Internal DNS Failed

```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup mysql.blog.svc.cluster.local
```

## Disk Space

```bash
df -h /var/lib/rancher/k3s/storage
# Clean if <50GB free

# Remove unused images
sudo k3s crictl rmi --prune
```

## Collect Logs

```bash
# All pod status
kubectl get pods -A > pods-status.txt

# Specific pod logs
kubectl logs -n <namespace> <pod-name> > pod-log.txt

# Events
kubectl get events -A --sort-by='.lastTimestamp' > events.txt
```
