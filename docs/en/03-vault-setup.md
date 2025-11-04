# 03. Vault Initialization and Secret Injection

HashiCorp Vault initialization and secret configuration via Vault Secrets Operator.

---

## Prerequisites

- Argo CD installed and all Applications Synced
- Vault Pod Running (0/1 normal - Sealed state)
- Prepared credentials:
  - Cloudflare Tunnel Token
  - MySQL passwords (2)
  - (Optional) OCI S3 credentials
  - (Optional) SMTP credentials

---

## Overview

1. Port-forward Vault service
2. Initialize Vault (get unseal keys and root token)
3. Unseal Vault
4. Enable KV v2 secret engine
5. Configure Kubernetes auth
6. Create policies
7. Inject secrets

Estimated time: 15 minutes

---

## Step 1: Port-forward Vault

### Terminal 1 (VM)

```bash
kubectl port-forward -n vault svc/vault 8200:8200
```

Keep this terminal open.

### Terminal 2 (VM)

```bash
# Set Vault address
export VAULT_ADDR=http://127.0.0.1:8200

# Verify connection
curl -s $VAULT_ADDR/v1/sys/health | jq
# Expected: "initialized":false, "sealed":true
```

---

## Step 2: Initialize Vault

```bash
cd security/vault/init-scripts

# Execute initialization script
./01-init-unseal.sh
```

**Important**: Save `init-output.json` to secure location immediately!

```bash
# Backup init-output.json
cp init-output.json ~/vault-init-backup.json
chmod 600 ~/vault-init-backup.json

# Display keys
cat init-output.json | jq
```

init-output.json contains:
- `unseal_keys_b64`: 5 unseal keys
- `root_token`: Root token

---

## Step 3: Enable KV v2 Secret Engine

```bash
# Set root token
export VAULT_TOKEN=$(jq -r .root_token init-output.json)

# Enable KV v2
vault secrets enable -path=kv kv-v2

# Verify
vault secrets list
# Expected: kv/ listed with type kv
```

---

## Step 4: Configure Kubernetes Auth

### 1. Enable Kubernetes auth

```bash
vault auth enable kubernetes
```

### 2. Get Kubernetes SA token

Kubernetes 1.24+ does not auto-create tokens:

```bash
# Create token (valid for 1 year)
kubectl create token vault -n vault --duration=8760h > /tmp/vault-sa-token

# Get Kubernetes API URL
KUBERNETES_HOST=$(kubectl config view --raw -o json | jq -r '.clusters[0].cluster.server')

echo "Kubernetes Host: $KUBERNETES_HOST"
```

### 3. Configure Vault Kubernetes auth

```bash
vault write auth/kubernetes/config \
  token_reviewer_jwt=@/tmp/vault-sa-token \
  kubernetes_host="$KUBERNETES_HOST" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  disable_local_ca_jwt=true
```

Verification:
```bash
vault read auth/kubernetes/config
```

---

## Step 5: Create Policies

```bash
cd security/vault/policies

# Create VSO policy
vault policy write vso-policy vso-policy.hcl

# Verify
vault policy list
# Expected: vso-policy listed
```

---

## Step 6: Create Kubernetes Auth Role

```bash
vault write auth/kubernetes/role/vso \
  bound_service_account_names=vault-secrets-operator \
  bound_service_account_namespaces=vso \
  policies=vso-policy \
  ttl=24h
```

Verification:
```bash
vault read auth/kubernetes/role/vso
```

---

## Step 7: Inject Secrets

### Ghost Secret (Basic - without SMTP)

```bash
vault kv put kv/blog/prod/ghost \
  url="https://yourdomain.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="YOUR_DB_PASSWORD" \
  database__connection__database="ghost"
```

Field descriptions:

| Field | Source | Note |
|-------|--------|------|
| url | Your domain | Must match actual domain |
| database__client | Fixed | `mysql` |
| database__connection__host | Fixed | Kubernetes service DNS |
| database__connection__user | Fixed | `ghost` |
| database__connection__password | Self-generated | 8+ characters |
| database__connection__database | Fixed | `ghost` |

### MySQL Secret

```bash
vault kv put kv/blog/prod/mysql \
  root_password="YOUR_MYSQL_ROOT_PASSWORD" \
  password="YOUR_DB_PASSWORD"
```

**Important**: `password` must match Ghost's `database__connection__password`

| Field | Source | Note |
|-------|--------|------|
| root_password | Self-generated | 8+ characters |
| password | Same as Ghost DB password | Must match |

### Cloudflare Tunnel Token

```bash
vault kv put kv/blog/prod/cloudflared \
  token="YOUR_CLOUDFLARE_TUNNEL_TOKEN"
```

| Field | Source | Note |
|-------|--------|------|
| token | Cloudflare Zero Trust | From 00-prerequisites.md Step 2.3 |

---

## Step 8: Verify Secret Injection

### 1. Check Vault secrets

```bash
# List secrets
vault kv list kv/blog/prod/

# Expected output:
# cloudflared
# ghost
# mysql

# Read secret (verify)
vault kv get kv/blog/prod/ghost
```

### 2. Check VSO VaultAuth

```bash
kubectl get vaultauth -n vso

# Expected:
# NAME       STATUS
# vso-auth   Ready
```

If not Ready:
```bash
kubectl describe vaultauth vso-auth -n vso
# Check Conditions for error messages
```

### 3. Check Kubernetes Secrets (created by VSO)

```bash
# Ghost secret
kubectl get secret ghost-env -n blog

# MySQL secret
kubectl get secret mysql-env -n blog

# Cloudflared secret
kubectl get secret cloudflared-token -n cloudflared
```

All secrets should exist. If missing:
```bash
# Check VSO logs
kubectl logs -n vso -l app.kubernetes.io/name=vault-secrets-operator
```

---

## Step 9: Verify Application Health

### 1. Check Pod status

```bash
kubectl get pods -A | grep -E "blog|cloudflared"

# Expected:
# blog          mysql-0                    1/1     Running
# blog          ghost-xyz                  1/1     Running
# cloudflared   cloudflared-xyz            1/1     Running
# cloudflared   cloudflared-abc            1/1     Running
```

### 2. Check Argo CD Application status

```bash
kubectl get applications -n argocd

# Expected:
# NAME             SYNC STATUS   HEALTH STATUS
# blogstack-root   Synced        Healthy
# observers        Synced        Healthy
# ingress-nginx    Synced        Healthy
# cloudflared      Synced        Healthy  ← Changed from Degraded
# vault            Synced        Healthy
# vso              Synced        Healthy
# ghost            Synced        Healthy  ← Changed from Degraded
```

All applications should be Healthy.

---

## Step 10: Configure Cloudflare Public Hostname

### 1. Access Cloudflare Zero Trust

Navigate to: https://one.dash.cloudflare.com/

### 2. Add Public Hostname

1. Networks → Tunnels
2. Click your tunnel: `blogstack-tunnel`
3. Public Hostname tab → Add a public hostname

Configuration:
```
Domain: yourdomain.com
Service: http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
```

### 3. Verify

```bash
# From local PC
curl -I https://yourdomain.com

# Expected: HTTP/2 200 or 30x
```

---

## Optional Features

### A. SMTP Email (Optional)

To enable Ghost email features:

```bash
# Update Ghost secret with SMTP fields
vault kv patch kv/blog/prod/ghost \
  mail__transport="SMTP" \
  mail__options__service="Mailgun" \
  mail__options__host="smtp.mailgun.org" \
  mail__options__port="587" \
  mail__options__auth__user="postmaster@mg.yourdomain.com" \
  mail__options__auth__pass="YOUR_SMTP_PASSWORD"

# Restart Ghost pods to apply
kubectl rollout restart deployment ghost -n blog
```

SMTP field descriptions:

| Field | Example | Note |
|-------|---------|------|
| mail__transport | `SMTP` | Fixed |
| mail__options__service | `Mailgun` | Provider name |
| mail__options__host | `smtp.mailgun.org` | SMTP server |
| mail__options__port | `587` | SMTP port |
| mail__options__auth__user | `postmaster@mg.yourdomain.com` | SMTP username |
| mail__options__auth__pass | (password) | SMTP password |

See 00-prerequisites.md Section B for SMTP setup.

### B. Backup (Optional)

To enable automatic backup to OCI Object Storage:

```bash
# Add backup secret
vault kv put kv/blog/prod/backup \
  AWS_ENDPOINT="https://namespace.compat.objectstorage.region.oraclecloud.com" \
  AWS_ACCESS_KEY_ID="YOUR_ACCESS_KEY" \
  AWS_SECRET_ACCESS_KEY="YOUR_SECRET_KEY" \
  BUCKET_NAME="blog-backups" \
  AWS_REGION="us-phoenix-1"

# Apply optional backup CronJob
kubectl apply -f ./apps/ghost/optional/

# Apply VSO secret for backup
kubectl apply -f ./security/vso/secrets/optional/
```

See `apps/ghost/optional/README.md` for details.

---

## Troubleshooting

### 1. Vault Pod 0/1 (Sealed)

**Symptom**: Vault Pod Running but 0/1

**Cause**: Normal - Vault is sealed after restart

**Solution**: Unseal manually
```bash
export VAULT_ADDR=http://127.0.0.1:8200

vault operator unseal <unseal-key-1>
vault operator unseal <unseal-key-2>
vault operator unseal <unseal-key-3>

# Check status
vault status
# Expected: Sealed: false
```

### 2. VaultAuth Not Ready

**Symptom**:
```bash
kubectl get vaultauth -n vso
# NAME       STATUS
# vso-auth   NotReady
```

**Solution**:
```bash
# Check VaultAuth details
kubectl describe vaultauth vso-auth -n vso

# Common causes:
# - Vault address incorrect
# - Kubernetes auth not configured
# - Service account token expired

# Recreate SA token
kubectl create token vault -n vault --duration=8760h > /tmp/vault-sa-token

# Reconfigure Kubernetes auth
vault write auth/kubernetes/config \
  token_reviewer_jwt=@/tmp/vault-sa-token \
  kubernetes_host="$KUBERNETES_HOST" \
  disable_local_ca_jwt=true
```

### 3. VSO Not Creating Secrets

**Symptom**: Kubernetes secrets not created

**Solution**:
```bash
# Check VSO logs
kubectl logs -n vso -l app.kubernetes.io/name=vault-secrets-operator

# Check VaultDynamicSecret resources
kubectl get vaultdynamicsecret -A

# Verify Vault secrets exist
vault kv list kv/blog/prod/
```

### 4. Ghost Cannot Connect to MySQL

**Symptom**: Ghost pod logs show database connection error

**Solution**:
```bash
# Verify password match
vault kv get kv/blog/prod/ghost | grep password
vault kv get kv/blog/prod/mysql | grep password
# Both must be identical

# Check MySQL pod
kubectl logs -n blog mysql-0
```

---

## Next Steps

Vault setup complete.

Current state:
- Vault initialized and unsealed
- All secrets injected
- VSO creating Kubernetes secrets
- All applications Healthy

Next: [04-operations.md](./04-operations.md) - Operations and monitoring (reference)

---

## Security Notes

- **init-output.json**: Store securely (contains unseal keys and root token)
- **Root token**: Use only for initial setup
- **Unseal keys**: Distribute to multiple secure locations
- **Backup**: Back up Vault data PVC regularly

---

## References

- [Vault Official Documentation](https://developer.hashicorp.com/vault/docs)
- [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/platform/k8s/vso)
- [Vault Kubernetes Auth](https://developer.hashicorp.com/vault/docs/auth/kubernetes)

