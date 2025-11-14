# Architecture & Conformance

High-level architecture and component verification

This document is intentionally kept as-is for technical reference.

See Korean version (docs/ko/CONFORMANCE.md) for detailed architecture documentation.

## Quick Overview

### Components

- k3s: Lightweight Kubernetes
- Argo CD: GitOps deployment
- Vault + VSO: Secret management
- ingress-nginx: Ingress controller
- Cloudflare Tunnel: External access
- Ghost + MySQL: Blog application
- Prometheus, Grafana, Loki: Observability

### Architecture Diagram

```
Internet
   ↓
Cloudflare Tunnel
   ↓
ingress-nginx
   ↓
Ghost ←→ MySQL
   ↑
Vault (secrets via VSO)
```

### Verification Commands

```bash
# All pods running
kubectl get pods -A

# All apps synced
kubectl get applications -n argocd

# External access
curl -I https://yourdomain.com
```

For detailed component specs, security policies, and compliance checks, refer to the Korean documentation or examine the manifests in:
- `apps/*/base/`
- `apps/*/overlays/prod/`
- `security/vault/`
- `security/vso/`

