# Customization

Customize blogstack-k8s for your own blog.

## Quick Start

Minimal changes required to deploy after forking (run on VM).

### Prerequisites

- 00-prerequisites.md completed
- VM SSH access
- Prepared: Domain, Git Repository URL

### Step 1: Clone Repository (On VM)

```bash
# SSH into VM
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>

# Go to home directory
cd ~

# Clone repository (Your forked repository)
git clone https://github.com/YOUR_GITHUB_USERNAME/blogstack-k8s.git
cd blogstack-k8s

# Verify location
pwd
# Expected output: /home/ubuntu/blogstack-k8s
```

Note: Clone your own forked repository, not the original one.

---

### Step 2: Bulk Update Git URLs

```bash
# Check current URL
grep "repoURL" iac/argocd/root-app.yaml

# Set variables (Change to actual values)
OLD_URL="https://github.com/your-org/blogstack-k8s"
NEW_URL="https://github.com/YOUR_GITHUB_USERNAME/blogstack-k8s"

# Bulk update (Linux - on VM)
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
# Example: If GitHub username is "johndoe"
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

Before change:
```env
domain=yourdomain.com
siteUrl=https://yourdomain.com
email=admin@yourdomain.com
timezone=Asia/Seoul
```

After change (Real example):
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
# Git Config (First time only)
git config --global user.name "Your Name"
git config --global user.email "your-email@example.com"

# Check changes
git status

# Expected output:
# modified:   iac/argocd/root-app.yaml
# modified:   clusters/prod/apps.yaml
# modified:   clusters/prod/project.yaml
# modified:   config/prod.env

# Stage changes
git add iac/argocd/root-app.yaml \
        clusters/prod/apps.yaml \
        clusters/prod/project.yaml \
        config/prod.env

# Commit
git commit -m "Customize: Update Git URL and domain to myblog.com"

# Push (GitHub authentication required)
git push origin main
```

GitHub Authentication Method:
```bash
# Use Personal Access Token (Recommended)
# GitHub → Settings → Developer settings → Personal access tokens → Generate new token
# Scopes: repo (all)

# Username when pushing: YOUR_GITHUB_USERNAME
# Password: (The generated Personal Access Token)
```

---

### Step 5: Verify External Services Readiness

Double-check that **all of the following** are ready:

```bash
# Checklist (Copy and paste in terminal)
cat << 'EOF'
External Services Readiness Check:
□ Cloudflare Tunnel Token copied
□ MySQL passwords (2) generated (Root, Ghost)

Optional (If needed):
□ OCI S3 Access Key/Secret Key copied (If backup enabled)
□ SMTP credentials copied (If email sending enabled)
EOF
```

---

### Completion

Now proceed to the next step:

→ [01-infrastructure.md](./01-infrastructure.md) - Install k3s (5 min)

---

## Design Principles

**Centralized Configuration**: Most personalization settings live in `config/prod.env`. Monitoring (Blackbox) URLs are managed in `apps/observers/overlays/prod/vmagent-scrape.yml`.

**Reusable Infrastructure**: The code in this repository is designed so anyone can fork it and modify `config/prod.env`, plus `vmagent-scrape.yml` when needed, to use it immediately.

## Step 1: Modify config/prod.env

Open the `config/prod.env` file at the root of the repository and modify the following values:

```env
# Basic Settings
domain=yourdomain.com                    # Change to actual domain
siteUrl=https://yourdomain.com           # Match the domain
email=admin@yourdomain.com               # Admin email
timezone=Asia/Seoul                      # Timezone (Changeable)
alertEmail=admin@yourdomain.com          # Alert recipient email

```

### Important: By default you only need to modify this file!

- ✅ **Modify this file**: `config/prod.env`
- ❌ **Do not need to modify**:
  - `apps/ghost/base/ingress.yaml` (Auto-injected)
  - All other Kubernetes resources

### (Optional) Step 1.5: Update Blackbox target URLs

Blackbox targets are managed in `apps/observers/overlays/prod/vmagent-scrape.yml`.

```yaml
  - job_name: blackbox
    static_configs:
      - targets:
          - https://yourdomain.com/
          - https://yourdomain.com/sitemap.xml
          - https://yourdomain.com/ghost/
```

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

Prepare the secrets to be entered by referring to `security/vault/secrets-guide.md`:

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

For SMTP email sending (required), see docs/07-smtp-setup.md. For automated backups, see apps/ghost/optional/README.md.

## Verify Auto-Injection

Verify that configurations are injected correctly:

### 1. Ghost Ingress Host

```bash
kubectl get ingress -n blog ghost -o yaml | grep host
# Output: host: yourdomain.com (domain value from config/prod.env)
```

### 2. Blackbox Targets

```bash
kubectl get configmap -n observers vmagent-scrape -o yaml | grep -A5 blackbox
# Output: targets from overlays/prod/vmagent-scrape.yml
```

### 3. Ghost URL Environment Variable

```bash
kubectl get pods -n blog -l app=ghost -o jsonpath='{.items[0].spec.containers[0].env}' | jq
# url: siteUrl from config/prod.env
```

## Multiple Environments (Optional)

To add dev/staging environments:

### 1. Copy Config File

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

## Example Domain in Documentation

`sunghogigio.com` in the documentation and guides is an **example**. When deploying for real:

- ✅ Use values from `config/prod.env`
- ✅ Update Blackbox URLs in `apps/observers/overlays/prod/vmagent-scrape.yml`
- ✅ Enter actual domain in Vault secrets
- ✅ Configure actual domain in Cloudflare

## Verification Checklist

Check before deployment:

Required:
- [ ] Enter actual domain/email in `config/prod.env`
- [ ] Change repoURL in `iac/argocd/root-app.yaml`
- [ ] Change all repoURLs in `clusters/prod/apps.yaml`
- [ ] Prepare Vault secrets (including domain)
- [ ] Create Cloudflare Tunnel and issue token

Optional:
- [ ] Create OCI Object Storage bucket and keys (If backup enabled)
- [ ] Prepare SMTP credentials (If email sending enabled)

## Troubleshooting

### Wrong Domain in Ingress

**Cause**: `config/prod.env` not updated or Argo CD not synced

**Fix**:
```bash
# After modifying config/prod.env
git add config/prod.env
git commit -m "Update domain"
git push

# Manual Argo CD sync
kubectl patch app ghost -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge
```

### Blackbox Targets check example.invalid

**Cause**: monitoring URLs not updated in `config/prod.env`, or observers app not yet synced

**Fix**:
```bash
# After modifying config/prod.env
git add config/prod.env
git commit -m "chore(config): update monitoring urls"
git push

# Optional hard refresh
kubectl patch app observers -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge
```

## Additional Resources

- [config/README.md](../config/README.md) - Config file details
- [security/vault/secrets-guide.md](../security/vault/secrets-guide.md) - Vault secrets guide
- [docs/03-vault-setup.md](./03-vault-setup.md) - Vault initialization method
