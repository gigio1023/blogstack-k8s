# blogstack-k8s

GitOps-based self-hosted Ghost blog infrastructure on Kubernetes

## Overview

Production-ready Ghost blog deployment using GitOps principles. Manages secrets with Vault, deploys via Argo CD, and exposes services through Cloudflare Tunnel without public ingress ports.

## Stack

- **Kubernetes**: k3s (lightweight, single-node optimized)
- **GitOps**: Argo CD (App-of-Apps pattern)
- **Secret Management**: HashiCorp Vault OSS + Vault Secrets Operator (VSO)
- **Ingress**: ingress-nginx + Cloudflare Tunnel (Zero Trust)
- **Application**: Ghost 5.x + MySQL 8.0
- **Observability**: Prometheus, Grafana, Loki, Promtail, Blackbox Exporter

## Architecture

```
Internet
   ↓
Cloudflare Tunnel (outbound HTTPS only)
   ↓
Kubernetes Cluster
   ├─ Argo CD (GitOps controller)
   ├─ Vault + VSO (secret injection)
   ├─ cloudflared → ingress-nginx → Ghost
   ├─ MySQL (StatefulSet + PVC)
   └─ Prometheus + Grafana + Loki
```

Key design choices:
- No public ingress required (Cloudflare Tunnel initiates outbound connection)
- Secrets never stored in Git (Vault + VSO sync to Kubernetes)
- Declarative deployment (Argo CD watches Git for changes)
- Persistent storage for MySQL and Vault data

## Prerequisites

Tested environment (not guaranteed minimum):

- **Compute**: Kubernetes cluster (k3s recommended)
  - 4 CPU cores (ARM64 or x86_64)
  - 24GB RAM
  - 100GB disk space
  - k3s can run on lower specs, but untested in this project
- **Network**: Outbound HTTPS (443) access required
  - GitHub (manifests)
  - Docker Hub, registry.k8s.io (images)
  - Cloudflare API (tunnel connection)
- **External Services**:
  - Domain name (any registrar, Cloudflare DNS required)
  - Cloudflare account (Free plan sufficient)
  - SMTP service (Mailgun, SendGrid, etc.)

This project was developed and tested on Oracle Cloud Free Tier (ARM64 VM). The specs above are for reference only and not a guaranteed minimum requirement.

For detailed testing environment: [docs/en/00-prerequisites.md](./docs/en/00-prerequisites.md)

## Getting Started

- English Documentation: [docs/en/README.md](./docs/en/README.md)
- Korean Documentation: [docs/ko/README.md](./docs/ko/README.md)

### Installation Steps

Follow the documentation in order:

```
00. Prerequisites → 01. k3s Setup → 02. Argo CD → 03. Vault
    ↓
04. Ingress → 05. Cloudflare → 06. Verification → 07. SMTP
    ↓
08. Operations
```

### Quick Navigation

| Step | Document | Description |
|------|----------|-------------|
| 0 | [00-prerequisites.md](./docs/en/00-prerequisites.md) | Requirements checklist |
| - | [CUSTOMIZATION.md](./docs/en/CUSTOMIZATION.md) | Fork repo, update Git URLs & domain |
| 1 | [01-infrastructure.md](./docs/en/01-infrastructure.md) | Install k3s cluster |
| 2 | [02-argocd-setup.md](./docs/en/02-argocd-setup.md) | Deploy Argo CD & App-of-Apps |
| 3 | [03-vault-setup.md](./docs/en/03-vault-setup.md) | Initialize Vault, inject secrets |
| 4 | [04-ingress-setup.md](./docs/en/04-ingress-setup.md) | Fix ingress-nginx webhook |
| 5 | [05-cloudflare-setup.md](./docs/en/05-cloudflare-setup.md) | Configure Tunnel & Zero Trust |
| 6 | [06-verification.md](./docs/en/06-verification.md) | Verify deployment |
| 7 | [07-smtp-setup.md](./docs/en/07-smtp-setup.md) | Configure email (required) |
| 8 | [08-operations.md](./docs/en/08-operations.md) | Day-2 operations |
| 9 | [09-troubleshooting.md](./docs/en/09-troubleshooting.md) | Common issues |
| 10 | [10-monitoring.md](./docs/en/10-monitoring.md) | Monitoring Setup |


## Repository Structure

```
blogstack-k8s/
├── config/
│   ├── prod.env              # Environment config (domain, URLs)
│   └── dev.env
├── iac/argocd/
│   └── root-app.yaml         # Root Application (App-of-Apps)
├── clusters/prod/
│   ├── project.yaml          # Argo CD AppProject
│   └── apps.yaml             # Child Application definitions
├── apps/
│   ├── ghost/                # Ghost CMS + MySQL
│   │   ├── base/
│   │   └── overlays/prod/
│   ├── ingress-nginx/        # Ingress controller
│   ├── cloudflared/          # Cloudflare Tunnel connector
│   └── observers/            # Prometheus stack (Helm)
├── security/
│   ├── vault/                # Vault StatefulSet (Raft storage)
│   │   ├── policies/
│   │   └── init-scripts/
│   └── vso/                  # Vault Secrets Operator
│       ├── operator/         # VSO Helm chart
│       └── resources/        # VaultAuth, VaultStaticSecret CRDs
└── docs/                     # Documentation (en, ko)
```

## Key Features

### GitOps with Argo CD

- **App-of-Apps Pattern**: Single root app deploys all components
- **Sync Waves**: Controlled deployment order (observers → ingress → vault → ghost)
- **Declarative**: Git is source of truth, manual `kubectl` not required
- **Auto-Sync**: Changes pushed to Git automatically deploy (configurable)

### Secret Management

- **Vault**: Secrets stored in Vault (never in Git)
- **VSO**: Automatically syncs Vault secrets to Kubernetes secrets
- **Per-Namespace Isolation**: Separate ServiceAccounts and Vault roles
- **Least Privilege**: NetworkPolicies restrict access to Vault

### Zero-Trust Networking

- **No Public Ports**: Cloudflare Tunnel initiates outbound connection
- **Cloudflare Access**: Optional authentication for `/ghost/*` admin panel
- **Internal-Only Services**: MySQL, Vault accessible only within cluster

### Observability

- **Metrics**: Prometheus scrapes Ghost, MySQL, ingress-nginx, cloudflared
- **Dashboards**: Pre-configured Grafana (cluster resources, NGINX, Vault)
- **Logs**: Loki aggregates logs from all namespaces
- **Health Checks**: Blackbox Exporter monitors external HTTPS endpoint

### Common Tasks

| Task | Reference |
|------|-----------|
| Update domain or Git URL | [CUSTOMIZATION.md](./docs/en/CUSTOMIZATION.md) |
| Change SMTP settings | [07-smtp-setup.md](./docs/en/07-smtp-setup.md) |
| Update Vault secrets | [03-vault-setup.md](./docs/en/03-vault-setup.md), [08-operations.md](./docs/en/08-operations.md) |
| Restart applications | [RESET.md](./docs/en/RESET.md) |
| Troubleshoot issues | [09-troubleshooting.md](./docs/en/09-troubleshooting.md) |
| Enable backups (optional) | [08-operations.md](./docs/en/08-operations.md) |

## Additional Resources

- [SECURITY.md](./docs/en/SECURITY.md) - Security design (NetworkPolicy, RBAC, PSS)
- [CONFORMANCE.md](./docs/en/CONFORMANCE.md) - Architecture details & compliance
- [ENVIRONMENTS.md](./docs/en/ENVIRONMENTS.md) - Multi-environment setup (dev/prod)
- [CI.md](./docs/en/CI.md) - GitHub Actions validation pipeline

## Technology Versions

| Component | Technology | Version |
|-----------|------------|---------|
| Kubernetes | k3s | 1.28+ |
| GitOps | Argo CD | stable |
| Secret Management | Vault OSS | 1.15+ |
| Secret Operator | VSO | 0.6+ |
| CMS | Ghost | 5.x |
| Database | MySQL | 8.0 |
| Ingress | ingress-nginx | 4.13+ |
| Tunnel | cloudflared | 2025.10+ |
| Monitoring | kube-prometheus-stack | 79.0+ |
| Logging | Loki + Promtail | 5.39+ |

## Contributing

Contributions welcome. Please:
- Follow existing manifest structure
- Test with `kustomize build` and `kubeconform`
- Update relevant documentation
- Run CI validation: `make validate`

## License

MIT

## Notes

- Vault data persists on PVC (survives pod restarts)
- MySQL uses StatefulSet with persistent storage
- Cloudflare Tunnel runs in HA mode (2 replicas)
- SMTP configuration required for Ghost password resets
- Backup to object storage is optional (see docs)
