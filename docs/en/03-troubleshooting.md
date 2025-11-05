# 03. Troubleshooting

## Vault

### Pod CrashLoopBackOff

```bash
kubectl logs -n vault vault-0
kubectl get pvc -n vault  # Verify Bound
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

kubectl patch application ghost -n argocd -p '{"operation": {"sync": {"revision": "HEAD"}}}' --type merge
```

## Cloudflared

### Pre-deployment Docker Validation

Validate cloudflared commands locally before deployment.

#### Extract Token

```bash
TUNNEL_TOKEN=$(kubectl get secret cloudflared-token -n cloudflared -o jsonpath='{.data.token}' | base64 -d)
echo "Token length: ${#TUNNEL_TOKEN}"  # 184 characters
```

#### Minimal Test

```bash
docker run --rm docker.io/cloudflare/cloudflared:2025.10.0 \
  tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"
```

Expected: `Connection registered`

#### Metrics Test

```bash
docker run --rm \
  -p 2000:2000 \
  -e TUNNEL_METRICS=0.0.0.0:2000 \
  docker.io/cloudflare/cloudflared:2025.10.0 \
  tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"
```

Verify in another terminal:
```bash
curl http://localhost:2000/metrics  # Prometheus metrics output
```

#### Apply Validated Args to YAML

Apply successful Docker args to `apps/cloudflared/base/deployment.yaml`:

```yaml
args:
  - tunnel
  - --no-autoupdate
  - run
  - --token
  - $(TUNNEL_TOKEN)
env:
  - name: TUNNEL_METRICS
    value: "0.0.0.0:2000"
```

```bash
git add apps/cloudflared/base/deployment.yaml
git commit -m "fix: validated cloudflared args"
git push
```

#### Validate Individual Flags

Check if specific flags are supported:

```bash
docker run --rm docker.io/cloudflare/cloudflared:2025.10.0 tunnel run --help | grep "metrics"
docker run --rm docker.io/cloudflare/cloudflared:2025.10.0 tunnel run --help | grep "\[$"
# Flags ending with [$ can be set via environment variables
```

### CrashLoopBackOff (--metrics error)

Fix `apps/cloudflared/base/deployment.yaml`:

```yaml
args:
  - tunnel
  - --no-autoupdate
  - run
  - --token
  - $(TUNNEL_TOKEN)
  - --metrics=0.0.0.0:2000  # Use = operator
```

```bash
git add apps/cloudflared/base/deployment.yaml
git commit -m "Fix cloudflared metrics flag"
git push
kubectl patch application cloudflared -n argocd -p '{"operation": {"sync": {"revision": "HEAD"}}}' --type merge
```

### Error 1033

```bash
kubectl logs -n cloudflared -l app=cloudflared --tail=50
kubectl exec -n cloudflared -l app=cloudflared -- \
  nc -zv ingress-nginx-controller.ingress-nginx.svc.cluster.local 80
```

Verify Cloudflare Tunnel configuration (Service: `http://ingress-nginx-controller...`)

## Ghost

### CrashLoopBackOff (Migration Lock)

```bash
# Check Ingress
kubectl get ingress -n blog

# Release lock
kubectl exec -n blog mysql-0 -- mysql \
  -u root -p$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.root_password}' | base64 -d) \
  ghost -e "UPDATE migrations_lock SET locked=0 WHERE lock_key='km01';"

kubectl rollout restart deployment/ghost -n blog
```

### URL Configuration Error

```bash
grep siteUrl config/prod.env
vault kv get -field=url kv/blog/prod/ghost
# Values must match

vault kv patch kv/blog/prod/ghost url="https://yourdomain.com"
kubectl rollout restart deployment/ghost -n blog
```

## MySQL

### Password Mismatch

```bash
vault kv get -field=database__connection__password kv/blog/prod/ghost
vault kv get -field=password kv/blog/prod/mysql
# Must be identical

NEW_PASSWORD="your-password"
vault kv patch kv/blog/prod/ghost database__connection__password="$NEW_PASSWORD"
vault kv patch kv/blog/prod/mysql password="$NEW_PASSWORD"
kubectl rollout restart deployment/ghost -n blog
```

## VSO

### Secret Not Created

```bash
kubectl describe vaultstaticsecret ghost-env -n blog | tail -20
kubectl logs -n vso -l app.kubernetes.io/name=vault-secrets-operator --tail=50

# Restart VSO
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
kubectl get secrets -n blog  # Check after 30s
```

### VaultAuth Invalid

```bash
vault read auth/kubernetes/config

TOKEN_REVIEWER_JWT=$(kubectl create token vault -n vault --duration=8760h)
vault write auth/kubernetes/config \
    token_reviewer_jwt="$TOKEN_REVIEWER_JWT" \
    kubernetes_host="https://kubernetes.default.svc:443" \
    kubernetes_ca_cert="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)" \
    disable_local_ca_jwt=true

kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
```

## Network

### Inter-Pod Communication Failure

```bash
kubectl exec -n blog -l app=ghost -- nslookup mysql.blog.svc.cluster.local
kubectl exec -n blog -l app=ghost -- nc -zv mysql.blog.svc.cluster.local 3306
kubectl get networkpolicy -A
```

## Log Collection

```bash
mkdir -p ~/debug-logs
kubectl logs -n blog -l app=ghost --tail=200 > ~/debug-logs/ghost.log
kubectl logs -n blog mysql-0 --tail=200 > ~/debug-logs/mysql.log
kubectl logs -n cloudflared -l app=cloudflared --tail=200 > ~/debug-logs/cloudflared.log
kubectl logs -n vso -l app.kubernetes.io/name=vault-secrets-operator --tail=200 > ~/debug-logs/vso.log
tar -czf debug-logs-$(date +%Y%m%d-%H%M%S).tar.gz ~/debug-logs/
```

## Event Inspection

```bash
kubectl get events -A --sort-by='.lastTimestamp' | grep -E "Warning|Error"
kubectl get events -n blog --sort-by='.lastTimestamp'
```

