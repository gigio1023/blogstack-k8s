# Customization

Customize blogstack-k8s for your blog

## Quick Start

Minimal changes to deploy after fork (run on VM)

### Prerequisites

- 00-prerequisites.md completed
- VM SSH access
- Ready: domain, Git repo URL

### 1. Clone Repo (On VM)

```bash
# SSH to VM
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>

# Go to work directory
cd ~

# Clone your fork
git clone https://github.com/YOUR_GITHUB_USERNAME/blogstack-k8s.git
cd blogstack-k8s

# Verify location
pwd
# Expected: /home/ubuntu/blogstack-k8s
```

Note: Clone your fork, not the original

### 2. Bulk Update Git URLs

```bash
# Check current URL
grep "repoURL" iac/argocd/root-app.yaml

# Set variables
OLD_URL="https://github.com/your-org/blogstack-k8s"
NEW_URL="https://github.com/YOUR_GITHUB_USERNAME/blogstack-k8s"

# Update all files
sed -i "s|$OLD_URL|$NEW_URL|g" iac/argocd/root-app.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/apps.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/project.yaml

# Verify
grep "repoURL" iac/argocd/root-app.yaml
# Should show your GitHub username
```

### 3. Update Domain

```bash
# Check current domain
grep "siteUrl" config/prod.env

# Update to your domain
sed -i 's|siteUrl=.*|siteUrl=https://yourdomain.com|' config/prod.env

# Verify
grep "siteUrl" config/prod.env
```

### 4. Set Git Identity

```bash
git config user.name "Your Name"
git config user.email "your-email@example.com"
```

### 5. Commit & Push

```bash
git add iac/ clusters/ config/
git commit -m "chore: customize URLs and domain"
git push origin main
```

Done. Proceed to 01-infrastructure.md

## Advanced Customization

### Change Namespace Names

Edit `apps/*/overlays/prod/kustomization.yaml`:

```yaml
namespace: my-blog  # Change from 'blog'
```

Update all references in:
- `clusters/prod/project.yaml`
- VSO resources
- NetworkPolicies

### Change Resource Limits

Edit `apps/*/base/kustomization.yaml` or overlays:

```yaml
patches:
  - patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: 1Gi
    target:
      kind: Deployment
      name: ghost
```

### Multiple Environments

Copy prod to dev:

```bash
cp -r apps/ghost/overlays/prod apps/ghost/overlays/dev
```

Edit `apps/ghost/overlays/dev/kustomization.yaml`:

```yaml
namespace: blog-dev

configMapGenerator:
  - name: blog-env
    envs:
      - ../../../../config/dev.env
```

Create dev App:

```yaml
# clusters/dev/apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ghost-dev
  namespace: argocd
spec:
  source:
    path: apps/ghost/overlays/dev
  destination:
    namespace: blog-dev
```

### Use Different Ingress Class

Edit `apps/ghost/base/ingress.yaml`:

```yaml
spec:
  ingressClassName: traefik  # Change from 'nginx'
```

### Custom Ghost Image

Edit `apps/ghost/base/deployment.yaml`:

```yaml
spec:
  template:
    spec:
      containers:
        - name: ghost
          image: your-registry/ghost:custom
```

### Add Backup to Different Provider

Edit `apps/ghost/optional/cronjob-backup.yaml`:

Replace AWS_* env vars with your provider's API.

## Don't Forget

After changes:

```bash
git add .
git commit -m "chore: customize configuration"
git push origin main
```

Argo CD auto-syncs in ~3 minutes, or manual sync:

```bash
kubectl patch application <app-name> -n argocd \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}' --type merge
```
