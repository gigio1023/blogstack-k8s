# Customization Guide

Instructions for customizing blogstack-k8s for your blog.

---

## 5-Minute Quick Start

Minimum modifications required for deployment after forking (execute inside VM)

---

### Prerequisites

- Completed 00-prerequisites.md (all external services ready)
- SSH connection to VM established
- Required information: Domain (Cloudflare Registrar recommended), Git repository URL

Tip: Purchasing domain from Cloudflare Registrar eliminates nameserver configuration

---

### Step 1: Clone Repository (Inside VM)

```bash
# SSH into VM
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>

# Navigate to working directory
cd ~

# Clone repository (your forked repository)
git clone https://github.com/YOUR_GITHUB_USERNAME/blogstack-k8s.git
cd blogstack-k8s

# Verify current location
pwd
# Expected output: /home/ubuntu/blogstack-k8s
```

Note: Clone your forked repository, not the original

---

### Step 2: Batch Update Git URLs

```bash
# Check current URL
grep "repoURL" iac/argocd/root-app.yaml

# Set variables (change to actual values)
OLD_URL="https://github.com/your-org/blogstack-k8s"
NEW_URL="https://github.com/YOUR_GITHUB_USERNAME/blogstack-k8s"

# Batch update (Linux - on VM)
sed -i "s|$OLD_URL|$NEW_URL|g" \
  iac/argocd/root-app.yaml \
  clusters/prod/apps.yaml \
  clusters/prod/project.yaml

# Verify change
grep "repoURL" iac/argocd/root-app.yaml
# Expected output: repoURL: https://github.com/YOUR_GITHUB_USERNAME/blogstack-k8s
```

Real example:
```bash
# Example: GitHub username is "johndoe"
OLD_URL="https://github.com/your-org/blogstack-k8s"
NEW_URL="https://github.com/johndoe/blogstack-k8s"

sed -i "s|$OLD_URL|$NEW_URL|g" \
  iac/argocd/root-app.yaml \
  clusters/prod/apps.yaml \
  clusters/prod/project.yaml
```

---

### Step 3: Update Domain

```bash
# Edit config/prod.env file
vi config/prod.env
```

Before:
```env
domain=yourdomain.com
siteUrl=https://yourdomain.com
email=admin@yourdomain.com
timezone=Asia/Seoul
```

After (actual example):
```env
domain=myblog.com
siteUrl=https://myblog.com
email=admin@myblog.com
timezone=Asia/Seoul
```

Save and exit: `ESC` → `:wq`

Verify change:
```bash
cat config/prod.env | grep -E "^domain=|^siteUrl=|^email="

# Expected output:
# domain=myblog.com
# siteUrl=https://myblog.com
# email=admin@myblog.com
```

---

### Step 4: Commit & Push

```bash
# Git configuration (first time only)
git config --global user.name "Your Name"
git config --global user.email "your-email@example.com"

# Check changes
git status

# Expected output:
# modified:   iac/argocd/root-app.yaml
# modified:   clusters/prod/apps.yaml
# modified:   clusters/prod/project.yaml
# modified:   config/prod.env

# Stage
git add iac/argocd/root-app.yaml \
        clusters/prod/apps.yaml \
        clusters/prod/project.yaml \
        config/prod.env

# Commit
git commit -m "Customize: Update Git URL and domain to myblog.com"

# Push (GitHub authentication required)
git push origin main
```

GitHub authentication:
```bash
# Use Personal Access Token (recommended)
# GitHub → Settings → Developer settings → Personal access tokens → Generate new token
# Scopes: repo (full)

# On push Username: YOUR_GITHUB_USERNAME
# Password: (generated Personal Access Token)
```

---

### Step 5: Verify External Services

Confirm **all** of the following are ready:

```bash
# Checklist (copy and use in terminal)
cat << 'EOF'
External services verification:
□ Cloudflare Tunnel Token copied
□ MySQL passwords generated (Root, Ghost)

Optional (if needed):
□ OCI S3 Access Key/Secret Key copied (for backup)
□ SMTP credentials copied (for email)
EOF
```

---

### Complete

Proceed to next step:

→ [01-infrastructure.md](./01-infrastructure.md) - Install k3s (5 min)

---

## Design Principles

**Centralized configuration**: All personalization settings managed in one place: `config/prod.env`. No domain or personal information hardcoded in Kubernetes resources.

**Reusable infrastructure**: Anyone can fork this repository and use it by only modifying `config/prod.env`.

## Step 1: Modify config/prod.env

Open `config/prod.env` at repository root and modify these values:

```env
# Basic settings
domain=yourdomain.com                    # Change to actual domain
siteUrl=https://yourdomain.com           # Match domain
email=admin@yourdomain.com               # Admin email
timezone=Asia/Seoul                      # Timezone (changeable)
alertEmail=admin@yourdomain.com          # Alert recipient email

# Monitoring URLs (auto-adjusted when domain changed)
monitorUrlHome=https://yourdomain.com/
monitorUrlSitemap=https://yourdomain.com/sitemap.xml
monitorUrlGhost=https://yourdomain.com/ghost/
```

### Important: Only this file needs modification!

- ✅ **Modify this file**: `config/prod.env`
- ❌ **No modification needed**:
  - `apps/ghost/base/ingress.yaml` (auto-injected)
  - `apps/observers/base/probe.yaml` (auto-injected)
  - All other Kubernetes resources

## Step 2: Change Git Repository URL

### Root Application

`iac/argocd/root-app.yaml`:

```yaml
spec:
  source:
    repoURL: https://github.com/your-org/blogstack-k8s  # Change this
```

### Child Applications

`clusters/prod/apps.yaml`:

```yaml
# Change repoURL for all Applications
spec:
  source:
    repoURL: https://github.com/your-org/blogstack-k8s  # Change this
```

## Step 3: Prepare Vault Secrets

Refer to `security/vault/secrets-guide.md` to prepare secrets for injection:

### Ghost Secret (`kv/blog/prod/ghost`)

Basic configuration (without SMTP):
```bash
vault kv put kv/blog/prod/ghost \
  url="https://yourdomain.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="<your-secure-password>" \
  database__connection__database="ghost"
```

### MySQL Secret (`kv/blog/prod/mysql`)

```bash
vault kv put kv/blog/prod/mysql \
  root_password="<mysql-root-password>" \
  user="ghost" \
  password="<same-as-ghost-db-password>"
```

### Cloudflare Tunnel (`kv/blog/prod/cloudflared`)

```bash
vault kv put kv/blog/prod/cloudflared \
  token="<cloudflare-tunnel-token>"
```

### Optional Features

For SMTP email or backup automation, see docs/03-vault-setup.md (Optional Features)

## Auto-Injection Verification

Verify configuration is properly injected:

### 1. Ghost Ingress Host

```bash
kubectl get ingress -n blog ghost -o yaml | grep host
# Output: host: yourdomain.com (domain value from config/prod.env)
```

### 2. Blackbox Probe Targets

```bash
kubectl get probe -n observers blog-external -o yaml | grep -A3 static:
# Output: monitorUrl* values from config/prod.env
```

### 3. Ghost URL Environment Variable

```bash
kubectl get pods -n blog -l app=ghost -o jsonpath='{.items[0].spec.containers[0].env}' | jq
# url: siteUrl from config/prod.env
```

## Multi-Environment (Optional)

To add dev/staging environments:

### 1. Copy Configuration File

```bash
cp config/prod.env config/dev.env
vim config/dev.env  # Modify to dev domain
```

### 2. Create Overlay

```bash
mkdir -p apps/ghost/overlays/dev
# Reference dev.env in kustomization.yaml
```

### 3. Create Cluster Directory

```bash
mkdir -p clusters/dev
# Copy and modify apps.yaml, project.yaml
```

## Example Domains in Documentation

`sunghogigio.com` in documentation and guides is an **example**. For actual deployment:

- ✅ Use values from `config/prod.env`
- ✅ Enter actual domain in Vault secrets
- ✅ Configure actual domain in Cloudflare

## Validation Checklist

Pre-deployment verification:

Required:
- [ ] Entered actual domain/email in `config/prod.env`
- [ ] Changed repoURL in `iac/argocd/root-app.yaml`
- [ ] Changed all repoURL in `clusters/prod/apps.yaml`
- [ ] Prepared Vault secrets (including domain)
- [ ] Created Cloudflare Tunnel and obtained token

Optional:
- [ ] Created OCI Object Storage bucket and keys (for backup)
- [ ] Prepared SMTP credentials (for email)

## Troubleshooting

### Wrong Domain in Ingress

**Cause**: `config/prod.env` not updated or Argo CD not synchronized

**Solution**:
```bash
# After modifying config/prod.env
git add config/prod.env
git commit -m "Update domain"
git push

# Manual Argo CD sync
kubectl patch app ghost -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge
```

### Blackbox Probe Checking example.invalid

**Cause**: observers app not yet synchronized

**Solution**:
```bash
kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-repo-server
# Auto-sync after Argo CD restart
```

## Additional Resources

- [config/README.md](../config/README.md) - Detailed configuration file explanation
- [security/vault/secrets-guide.md](../security/vault/secrets-guide.md) - Vault secret guide
- [docs/03-vault-setup.md](./03-vault-setup.md) - Vault initialization method

