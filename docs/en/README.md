# blogstack-k8s Documentation

GitOps-based Ghost blog infrastructure

OCI Free ARM VM + k3s + Argo CD + Vault + Ghost

---

## Installation Order

```
00 → 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08
```

- [00-prerequisites.md](./00-prerequisites.md) - Prerequisites
- [01-infrastructure.md](./01-infrastructure.md) - k3s cluster setup
- [02-argocd-setup.md](./02-argocd-setup.md) - Argo CD & App-of-Apps
- [03-vault-setup.md](./03-vault-setup.md) - Vault init & secrets
- [04-ingress-setup.md](./04-ingress-setup.md) - Ingress-nginx admission webhook
- [05-cloudflare-setup.md](./05-cloudflare-setup.md) - Cloudflare Tunnel & Zero Trust
- [06-verification.md](./06-verification.md) - System verification
- [07-smtp-setup.md](./07-smtp-setup.md) - SMTP email setup (required)
- [08-operations.md](./08-operations.md) - Operations & maintenance
- [09-troubleshooting.md](./09-troubleshooting.md) - Troubleshooting
- [10-monitoring.md](./10-monitoring.md) - Monitoring Setup (VictoriaMetrics/Grafana)

---

## Operations & Reference

### Operations
- [RESET.md](./RESET.md) - Restart applications

### Configuration
- [CUSTOMIZATION.md](./CUSTOMIZATION.md) - Git URL, domain, environment config
- [ENVIRONMENTS.md](./ENVIRONMENTS.md) - dev/prod environments

### Architecture
- [CONFORMANCE.md](./CONFORMANCE.md) - Architecture & component verification
- [SECURITY.md](./SECURITY.md) - Security guide
- [CI.md](./CI.md) - CI pipeline

---

## Tech Stack

- Kubernetes: k3s
- GitOps: Argo CD
- Secrets: Vault + VSO
- Ingress: ingress-nginx + Cloudflare Tunnel
- Application: Ghost 5.x + MySQL 8.0
- Observability: VictoriaMetrics + Grafana + Loki
