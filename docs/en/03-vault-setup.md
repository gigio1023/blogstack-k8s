# 03. Vault Initialization and Secret Injection

## Prerequisites

- 02-argocd-setup.md completed
- Vault Pod Running (0/1 uninitialized)
- Vault CLI installed

## Initialize Vault

### Port-forward

```bash
cd ~/blogstack-k8s
kubectl port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR=http://127.0.0.1:8200
```

### Run Initialization

```bash
cd security/vault/init-scripts
chmod +x 01-init-unseal.sh
./01-init-unseal.sh
cd ~/blogstack-k8s
```

Important: Back up init-output.json. Never commit to Git.

### Verify Status

```bash
kubectl get pods -n vault  # 1/1 Ready
kubectl exec -n vault vault-0 -- vault status  # Sealed: false
```

## Enable KV v2 Engine

```bash
export VAULT_TOKEN=$(jq -r .root_token security/vault/init-scripts/init-output.json)
vault secrets enable -path=kv kv-v2
vault secrets list | grep "^kv/"
```

## Create Policies

```bash
vault policy write ghost security/vault/policies/ghost.hcl
vault policy write mysql security/vault/policies/mysql.hcl
vault policy write cloudflared security/vault/policies/cloudflared.hcl
```

## Configure Kubernetes Auth

```bash
# Setup
K8S_HOST="https://kubernetes.default.svc:443"
TOKEN_REVIEWER_JWT=$(kubectl create token vault -n vault --duration=8760h)
K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

vault write auth/kubernetes/config \
    token_reviewer_jwt="$TOKEN_REVIEWER_JWT" \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CA_CERT" \
    disable_local_ca_jwt=true

# Create roles
vault write auth/kubernetes/role/blog \
    bound_service_account_names=vault-reader,default \
    bound_service_account_namespaces=blog,vso \
    policies=ghost,mysql,cloudflared \
    ttl=24h

vault write auth/kubernetes/role/cloudflared \
    bound_service_account_names=vault-reader \
    bound_service_account_namespaces=cloudflared \
    policies=cloudflared \
    ttl=24h
```

## Inject Secrets

### Ghost

```bash
# Check siteUrl in config/prod.env
grep "siteUrl" config/prod.env

vault kv put kv/blog/prod/ghost \
  url="https://yourdomain.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="YOUR_DB_PASSWORD" \
  database__connection__database="ghost"
```

### MySQL

```bash
vault kv put kv/blog/prod/mysql \
  root_password="YOUR_ROOT_PASSWORD" \
  user="ghost" \
  password="YOUR_DB_PASSWORD" \
  database="ghost"
```

Important: Ghost and MySQL passwords must match.

### Cloudflared

```bash
vault kv put kv/blog/prod/cloudflared \
  token="YOUR_CLOUDFLARE_TUNNEL_TOKEN"
```

### Verify

```bash
vault kv list kv/blog/prod  # cloudflared, ghost, mysql
```

## Verify VSO Secret Sync

```bash
# Wait 10-30 seconds for secret creation
kubectl get secrets -n blog  # ghost-env, mysql-secret
kubectl get secrets -n cloudflared  # cloudflared-token

# If not created, restart VSO
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
kubectl get secrets -n blog  # Check after 30s
```

## Optional Features

### SMTP Email

```bash
vault kv put kv/blog/prod/ghost \
  url="https://yourdomain.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="YOUR_DB_PASSWORD" \
  database__connection__database="ghost" \
  mail__transport="SMTP" \
  mail__options__service="Mailgun" \
  mail__options__host="smtp.mailgun.org" \
  mail__options__port="587" \
  mail__options__auth__user="postmaster@mg.yourdomain.com" \
  mail__options__auth__pass="YOUR_SMTP_PASSWORD"

kubectl rollout restart deployment/ghost -n blog
```

### OCI Backup

```bash
vault kv put kv/blog/prod/backup \
  AWS_ACCESS_KEY_ID="YOUR_OCI_ACCESS_KEY" \
  AWS_SECRET_ACCESS_KEY="YOUR_OCI_SECRET_KEY" \
  AWS_ENDPOINT_URL_S3="https://YOUR_NAMESPACE.compat.objectstorage.YOUR_REGION.oraclecloud.com" \
  BUCKET_NAME="blog-backups"

kubectl apply -f security/vso/secrets/optional/backup.yaml
kustomize build apps/ghost/optional | kubectl apply -f -
```

## Next Steps

Next: [03-1-ingress-setup.md](./03-1-ingress-setup.md)
