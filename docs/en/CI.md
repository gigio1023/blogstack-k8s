# CI Pipeline

GitHub Actions for manifest validation

## `.github/workflows/validate.yaml`

Automates manifest build and schema validation

### Triggers
- Push to `main` branch
- Pull request to `main` branch

### Steps
1. Install Kustomize (v5.4.3)
2. Install Kubeconform (v0.6.7)
3. Build & validate all overlays:
   - `apps/ghost/overlays/prod`
   - `apps/ingress-nginx/overlays/prod`
   - `apps/cloudflared/overlays/prod`
   - `apps/observers/overlays/prod`
   - `security/vault`
   - `security/vso`

### Validation

- Kubernetes resource schema
- CRDs (Prometheus Operator, VSO, etc.)
- Kustomize build errors

### Local Validation

Test before CI runs:

```bash
# Using Makefile
make validate

# Manual
kustomize build apps/ghost/overlays/prod | kubeconform -summary -strict
```

## (Optional) Theme Auto-Deploy

Auto-deploy Ghost themes with `.github/workflows/theme-deploy.yaml`:

```yaml
name: Deploy Ghost Theme
on:
  push:
    paths:
      - 'theme/**'
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: TryGhost/action-deploy-theme@v1
        with:
          api-url: ${{ secrets.GHOST_ADMIN_API_URL }}
          api-key: ${{ secrets.GHOST_ADMIN_API_KEY }}
          theme-name: "my-theme"
          file: "theme"
```

Required Secrets:
- `GHOST_ADMIN_API_URL`: `https://yourdomain.com`
- `GHOST_ADMIN_API_KEY`: Ghost Admin → Integrations → Custom Integration

## Best Practices

- Create PRs as Draft first
- Merge only after CI passes

