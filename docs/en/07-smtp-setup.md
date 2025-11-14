# 07. SMTP Email Setup

SMTP config for Ghost password resets, invites, and notifications

## Prerequisites

- 03-vault-setup.md completed
- Ghost pod Running
- Mailgun account ready (00-prerequisites.md)

## Why Required

Ghost requires email for staff device verification and password resets:
- Password reset won't work
- Can't invite admins
- Login may show "Failed to send email"

## Get Mailgun SMTP Info

### 1. Mailgun Dashboard

Log in to https://app.mailgun.com/

### 2. SMTP Credentials

Sending → Domains → `mg.yourdomain.com` → SMTP Credentials

| Item | Example | Notes |
|------|---------|-------|
| Host | `smtp.mailgun.org` | US (EU: `smtp.eu.mailgun.org`) |
| Port | `587` | TLS |
| Username | `postmaster@mg.yourdomain.com` | SMTP username |
| Password | `abc123xyz...` | SMTP password |

### 3. From Email

- `noreply@yourdomain.com` (recommended)
- `hello@yourdomain.com`
- `admin@yourdomain.com`

Must use Mailgun verified domain

## Add SMTP to Vault

### 1. Port-forward Vault

```bash
kubectl port-forward -n vault svc/vault 8200:8200 > /dev/null 2>&1 &
sleep 2
```

### 2. Set Environment

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r .root_token security/vault/init-scripts/init-output.json)
```

### 3. Add SMTP Config

Replace UPPERCASE with your Mailgun info:

```bash
vault kv patch kv/blog/prod/ghost \
  mail__transport="SMTP" \
  mail__options__service="Mailgun" \
  mail__options__host="smtp.mailgun.org" \
  mail__options__port="587" \
  mail__options__secure="false" \
  mail__options__auth__user="postmaster@mg.yourdomain.com" \
  mail__options__auth__pass="YOUR_MAILGUN_PASSWORD" \
  mail__from="'Your Blog Name' <noreply@yourdomain.com>"
```

Example (EU region):
```bash
vault kv patch kv/blog/prod/ghost \
  mail__transport="SMTP" \
  mail__options__service="Mailgun" \
  mail__options__host="smtp.eu.mailgun.org" \
  mail__options__port="587" \
  mail__options__secure="false" \
  mail__options__auth__user="postmaster@mg.yourdomain.com" \
  mail__options__auth__pass="your-password-here" \
  mail__from="'My Blog' <noreply@yourdomain.com>"
```

### 4. Verify Config

```bash
vault kv get -format=json kv/blog/prod/ghost | jq -r '.data.data' | grep mail__
```

## Restart VSO & Ghost

### 1. Restart VSO Pod

```bash
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator

# Wait for pod recreation (10s)
kubectl get pods -n vso -w
# Ctrl+C to exit

# Verify secret sync (wait 30s)
kubectl get secret ghost-env -n blog -o jsonpath='{.data.mail__options__auth__pass}' | base64 -d
# Should output Mailgun password
```

### 2. Restart Ghost Pod

```bash
kubectl rollout restart deployment ghost -n blog
kubectl rollout status deployment ghost -n blog

# Check status
kubectl get pods -n blog
# ghost-xxx: 1/1 Running
```

## Test Email

### 1. Access Ghost Admin

Visit `https://yourdomain.com/ghost/`

### 2. Send Test Email

Ghost Admin → Settings → Labs → Send test email

Enter recipient email → Send

### 3. Check Inbox

- Check for Ghost test email
- From address: what you set in `mail__from`
- Also check spam folder

### 4. Test Password Reset

Log out → Forgot password → Enter email → Check for reset link

## Troubleshooting

### "Failed to send email"

```bash
# Check Ghost logs
kubectl logs -n blog deployment/ghost --tail=50 | grep -i mail

# Common causes:
# - Typo in mail__options__auth__pass
# - Wrong mail__options__host (smtp.mailgun.org vs smtp.eu.mailgun.org)
# - Mailgun domain not verified
```

### Secret Not Syncing

```bash
# Check VaultStaticSecret
kubectl describe vaultstaticsecret ghost -n vso

# Restart VSO
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
kubectl get pods -n vso -w
```

### Ghost Pod CrashLoopBackOff

```bash
kubectl logs -n blog deployment/ghost --tail=100

# Check MySQL connection
kubectl exec -n blog mysql-0 -- mysql -u ghost -p$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.password}' | base64 -d) ghost -e "SELECT 1;"
```

### Mailgun Auth Failure

Mailgun Dashboard:
- Domain verification: Check Verified status
- SMTP credentials: Re-verify username, password
- Sending limits: Check monthly quota

Cloudflare DNS:
- Verify SPF, DKIM, MX records
- Proxy Status: DNS only (gray cloud)

## Next Steps

→ [08-operations.md](./08-operations.md) - Operations & maintenance
