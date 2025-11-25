# blogstack-k8s — Setup & Conformance (Single Source of Truth)

This document is the final single source of truth for blogstack-k8s. It provides both the initial build plan (design/choices/order) and implementation conformance (verification commands) in one place.

Principles:
- The document is the standard. If the implementation differs, update the document first, then align the implementation.
- Prioritize minimum complexity and lightweight configuration that is easy to set up on a personal server.

---

## A. Plan & Setup

### A.1 Goals & Premises
- **Goals**:
  1) Auto-reflect code changes via GitOps
  2) Immediate release from Ghost Admin
  3) Visualize status with metrics/alerts
  4) Self-hosted management of secrets/configurations
- **Platform/Constraints**: Oracle Cloud ARM64 (4 OCPU/24GB) single prod node
- **Exposure/Security**: Cloudflare Tunnel (CNAME → <UUID>.cfargotunnel.com), `/ghost/*` protected by Zero Trust Access
- **Proxy Note**: Ghost requires `X-Forwarded-Proto: https` (to prevent redirect loops)

### A.2 Repository Structure (Summary)
```
blogstack-k8s/
├─ docs/                 # Overview/Runbooks/Security/This Document
├─ clusters/prod/        # App-of-Apps Entry
├─ iac/argocd/           # Root App
├─ apps/                 # ingress-nginx, cloudflared, ghost(+mysql), observers
├─ security/             # vault, vso
├─ config/               # Public Config (prod.env)
└─ scripts/              # Utilities (bootstrap, health-check)
```

### A.3 Secrets/Config — Recommendations & Alternatives
- **Recommended**: HashiCorp Vault (OSS) + Vault Secrets Operator (VSO)
  - Standard Helm deployment, Raft storage, K8s Auth, Metrics/Audit
  - Auto-sync K8s Secrets via VSO (triggers rolling updates)
- **Alternatives (Optional)**: Sealed Secrets, SOPS (+KSOPS), Infisical

### A.4 Deployment Order (End-to-End)
1) Install k3s → 2) Argo CD + Root App (App-of-Apps) → 3) ingress-nginx (metrics on) → 4) cloudflared (Named Tunnel, /ready, metrics) → 5) Vault (Helm, Init/Unseal, K8s Auth) → 6) VSO (Secret Sync) → 7) Ghost+MySQL (Check ingress `X-Forwarded-Proto`) → 8) Observability (Probes/Dashboards/Alerts)

### A.5 Vault Design (Key Points)
- **Deployment**: Helm, start with HA disabled, Raft data/audit PVC
- **Auth**: Kubernetes Auth + Least Privilege Policies
- **Injection**: VSO (Secret Sync) or Injector (File/ENV Template)
- **Monitoring**: Scrape `/v1/sys/metrics?format=prometheus`

### A.6 Observability/Alerting (Summary)
- kube-prometheus-stack + Loki + Blackbox
- **Targets**: ingress 10254, cloudflared 2000, vault sys/metrics, external SLIs (`/`, `/sitemap.xml`, `/ghost`)

### A.7 Optional Features
- **Backup**: See `apps/ghost/optional/` if needed (MySQL + Content → OCI S3)
- **SMTP**: Required (see docs/07-smtp-setup.md)

### A.8 Networking/Security Key Points
- Cloudflare Tunnel (Outbound only), `/ghost/*` Zero Trust Access
- Ingress enforces `X-Forwarded-Proto: https`

### A.9 Execution Checklist (Summary)
- Install k3s → Install Argo CD → Deploy Root App → Vault Init/Unseal → Input Secrets (`ghost`, `mysql`, `cloudflared`) → Configure Cloudflare Public Hostname (ingress-nginx svc:80) → Health Check → Operations

---

## B. Docs ⇄ Implementation Conformance Map

Provides the core assertions of the document, the location of the actual implementation (manifests/scripts), and quick verification commands.

### B.0 Preparation/Environment
- **Docs**: `docs/00-prerequisites.md`, `docs/CUSTOMIZATION.md`
- **Impl**: `config/prod.env`

**Key Assertions**:
- Requires Cloudflare Zero Trust, OCI Object Storage, SMTP
- All public configurations are centrally managed in `config/prod.env`

**Quick Check**:
```bash
cat config/prod.env | sed -n '1,40p'
```

---

### B.1 Argo CD Installation
- **Docs**: `docs/02-argocd-setup.md`
- **Impl**: `iac/argocd/root-app.yaml`, `clusters/prod/apps.yaml`, `clusters/prod/project.yaml`
- **Optional**: `scripts/bootstrap.sh` (for quick install)

**Key Assertions**:
- Manual Argo CD install (recommended) or script → Deploy Root App
- App-of-Apps, sync-wave: observers(-2) → ingress-nginx(-1) → cloudflared(0) → vault(1) → vso(2) → ghost(3)

**Quick Check**:
```bash
kubectl get ns argocd && kubectl get applications -n argocd
kubectl get app observers ingress-nginx cloudflared vault vso ghost -n argocd 2>/dev/null || true
```

---

### B.2 Ingress-NGINX + Cloudflare Tunnel
- **Docs**: `docs/03-vault-setup.md` (Cloudflare section), `docs/08-operations.md`
- **Impl**: `apps/ingress-nginx/**`, `apps/cloudflared/**`, `apps/ghost/base/ingress.yaml`

**Key Assertions**:
- Routing: Cloudflare Tunnel → Ingress-NGINX (Service) → Ghost
- Ingress enforces `X-Forwarded-Proto: https`

**Quick Check**:
```bash
kubectl get svc -n ingress-nginx | grep ingress-nginx-controller
kubectl get ingress -n blog ghost -o yaml | grep -A2 annotations
kubectl logs -n cloudflared -l app=cloudflared --tail=50 | tail -n +1
```

---

### B.3 Vault + VSO (Secrets)
- **Docs**: `docs/03-vault-setup.md`, `security/vault/secrets-guide.md`
- **Impl**: `security/vault/**`, `security/vso/**`

**Key Assertions**:
- Vault: Helm deployment (Raft), Kubernetes Auth (1.24+ Token), Policies applied
- VSO: Creates `ghost-env`, `mysql-secret`, `cloudflared-token` via `VaultStaticSecret`

**Quick Check**:
```bash
kubectl get pods -n vault
kubectl exec -n vault vault-0 -- vault status
kubectl get vaultauth -A; kubectl get vaultconnection -A
kubectl get secrets -n blog | egrep 'ghost-env|mysql-secret' || true
kubectl get secrets -n cloudflared | grep cloudflared-token || true
```

---

### B.4 Application (Ghost + MySQL)
- **Docs**: `docs/02-argocd-setup.md` (Sync), `docs/08-operations.md`
- **Impl**: `apps/ghost/**`

**Key Assertions**:
- Ghost `url` injected from `config/prod.env.siteUrl`
- MySQL initialized with `mysql-secret`, Ghost uses `ghost-env`

**Quick Check**:
```bash
kubectl get deploy -n blog ghost -o yaml | grep -A3 'name: url'
kubectl get statefulset -n blog mysql
kubectl get pvc -n blog | egrep 'ghost-content|data-mysql'
```

---

### B.5 Observability/Alerting
- **Docs**: `docs/08-operations.md`
- **Impl**: `apps/observers/**`, `security/vault/servicemonitor.yaml`, `apps/cloudflared/overlays/prod/servicemonitor.yaml`, ingress-nginx ServiceMonitor generated by Helm (`apps/ingress-nginx/base/kustomization.yaml`)

**Key Assertions**:
- Grafana (admin/admin), Prometheus Targets: ingress 10254, cloudflared 2000, vault sys/metrics, Blackbox Probe external SLI

**Quick Check**:
```bash
kubectl port-forward -n observers svc/kube-prometheus-stack-grafana 3000:80 &
kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090 &
kubectl get probe -n observers blog-external -o yaml | grep static:
```

---

### B.6 Backup (Optional Feature)
- **Docs**: `apps/ghost/optional/README.md`
- **Impl**: `apps/ghost/optional/backup-cronjob.yaml`, `apps/ghost/optional/content-backup-cronjob.yaml`

Disabled in default configuration. Refer to `apps/ghost/optional/` to enable if needed.

---

### B.7 Health Check/Ops Scripts
- **Docs**: `README.md` (Usage link), `docs/08-operations.md`
- **Impl**: `scripts/health-check.sh`

**Key Assertions**:
- Batch check for core namespaces/apps/secrets/external access

**Quick Check**:
```bash
./scripts/health-check.sh || true
```

---

## C. Change Management Rules
1. Create a PR for implementation changes first, but **must include document changes (relevant section)**.
2. Add/Update verification commands for the change in `docs/CONFORMANCE.md`.
3. CI (`.github/workflows/validate.yaml`) must pass before merging.

---

## D. References

### Core Official Docs
- **Cloudflare Tunnel**: [DNS records](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/dns/), [Tunnel metrics](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/monitor-tunnels/metrics/), [Create tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/create-local-tunnel/)
- **Ghost**: [Reverse Proxying HTTPS](https://docs.ghost.org/faq/proxying-https-infinite-loops), [Comments](https://ghost.org/help/commenting/), [Official Docs](https://ghost.org/docs/)
- **HashiCorp Vault**: [Helm chart](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/helm), [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/sources/vault), [Agent Injector](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/injector), [Raft Deployment Guide](https://developer.hashicorp.com/vault/tutorials/day-one-raft/raft-deployment-guide), [Metrics API](https://developer.hashicorp.com/vault/api-docs/system/metrics), [Monitor with Prometheus](https://developer.hashicorp.com/vault/tutorials/archive/monitor-telemetry-grafana-prometheus)
- **Kubernetes**: [k3s Storage](https://docs.k3s.io/storage), [Ingress-NGINX Monitoring](https://kubernetes.github.io/ingress-nginx/user-guide/monitoring/), [Canary Deployments](https://kubernetes.github.io/ingress-nginx/examples/canary/)
- **Monitoring**: [Blackbox Exporter](https://github.com/prometheus/blackbox_exporter), [Grafana Contact Points](https://grafana.com/docs/grafana/latest/alerting/fundamentals/notifications/contact-points/)
- **Oracle Cloud**: [S3 Compatible API](https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/s3compatibleapi.htm)
- **Alternative Secret Tools**: [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets), [SOPS](https://github.com/getsops/sops), [Infisical](https://github.com/Infisical/infisical)

---

## E. Optional Features

### E.1 Comment System
**Context**: Ghost native comments are for members only ([Ghost Comments](https://ghost.org/help/commenting/)).

**Alternatives** (Public Comments):
- **Remark42** (Open Source, self-hosted) - Lightweight
- **HYVOR Talk** (Paid SaaS) - Premium features
- **Disqus** (Free/Paid) - Most widely used

**Implementation**: Embed JavaScript widget in Ghost theme.

### E.2 Ghost Theme Auto-Deployment
**Automate theme deployment with GitHub Actions**

`.github/workflows/theme-deploy.yaml`:
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

**Required Secrets**:
- `GHOST_ADMIN_API_URL`: `https://yourdomain.com`
- `GHOST_ADMIN_API_KEY`: Ghost Admin → Integrations → Custom Integration

### E.3 Vault Raft Snapshot Backup
**Automation Recommendation**

CronJob for Raft snapshot → OCI S3 upload:

```yaml
# Example: security/vault/backup-cronjob.yaml
schedule: "0 4 * * *"  # Daily at 04:00
command:
  - /bin/sh
  - -c
  - |
    vault operator raft snapshot save /tmp/vault-snapshot.snap
    aws s3 cp /tmp/vault-snapshot.snap s3://vault-backups/$(date +%Y%m%d).snap
```

**Restore**: `vault operator raft snapshot restore <file>`

### E.4 Secret Options Comparison

| Option | Operation Type | Pros | Cons |
|--------|----------------|------|------|
| **Vault + VSO/Injector** | Service (self-hosted) | Standard/Extensible/Audit/Metrics/Granular/Dynamic | Init/Ops learning curve |
| **Sealed Secrets** | Controller + KeyPair | Easy Git storage/Low resource | Dynamic rotation/Audit limits |
| **SOPS (+KSOPS)** | Git Encryption | No external service, GitOps friendly | Real-time rotation/Granularity limits |
| **Infisical** | Service (self-hosted) | UI/Operator/ESO integration | Many components |

### E.5 Canary Deployment (Optional)
Gradual rollout using Ingress-NGINX canary annotations:

```yaml
annotations:
  nginx.ingress.kubernetes.io/canary: "true"
  nginx.ingress.kubernetes.io/canary-weight: "20"  # 20% traffic
```

Ref: [Canary Deployments](https://kubernetes.github.io/ingress-nginx/examples/canary/)

---

## F. Troubleshooting (Quick Fixes)

### F.1 Ghost Redirect Loop/Login Failure
**Symptom**: Infinite redirect when accessing Ghost Admin

**Cause**: `X-Forwarded-Proto` header not passed

**Fix**:
```bash
# Check ingress-nginx use-forwarded-headers setting
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o jsonpath='{.data.use-forwarded-headers}'
# Output: true (Normal)

# Check Ingress
kubectl get ingress -n blog ghost -o jsonpath='{.spec.ingressClassName}'
# Output: nginx (Normal)

# Restart if issue persists
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
kubectl rollout restart deployment ghost -n blog
```

Ref: [Ghost Reverse Proxy Docs](https://docs.ghost.org/faq/proxying-https-infinite-loops)

### F.2 Cloudflare Tunnel Disconnected
**Symptom**: 502/504 Error, Blog inaccessible

**Check**:
```bash
# Pod Status
kubectl get pods -n cloudflared

# Check Logs
kubectl logs -n cloudflared -l app=cloudflared --tail=50

# /ready endpoint
kubectl exec -n cloudflared <pod-name> -- curl http://localhost:2000/ready
```

**Fix**:
```bash
# Restart Pod
kubectl rollout restart deployment/cloudflared -n cloudflared

# Renew Token (if needed)
vault kv put kv/blog/prod/cloudflared token="<NEW_TOKEN>"
kubectl delete pod -n cloudflared -l app=cloudflared
```

### F.3 Vault Sealed State
**Symptom**: VSO Secret sync failed, App CrashLoopBackOff

**Check**:
```bash
kubectl exec -n vault vault-0 -- vault status
# Problem if Sealed: true
```

**Fix** (Requires 3 Unseal Keys):
```bash
kubectl exec -n vault vault-0 -- vault operator unseal <KEY1>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY2>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY3>
```

### F.4 Metrics Not Collected
**Check Points**:
- Ingress-NGINX: Check `:10254/metrics` response
- Cloudflared: Check `:2000/metrics` response
- Vault: Check `/v1/sys/metrics?format=prometheus` permissions
- Blackbox: Check Probe target settings

```bash
# Check ServiceMonitor
kubectl get servicemonitor -A

# Prometheus Targets (after port-forward)
kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090/targets
```

### F.5 MySQL Connection Failure
**Symptom**: Ghost Pod CrashLoopBackOff

**Check**:
```bash
# MySQL Pod Status
kubectl get pods -n blog -l app=mysql

# MySQL Logs
kubectl logs -n blog mysql-0

# Ghost Logs
kubectl logs -n blog -l app=ghost
```

**Fix**:
```bash
# Check DB Connection Info (Vault)
vault kv get kv/blog/prod/ghost
vault kv get kv/blog/prod/mysql

# Check Password Match
# database__connection__password == mysql password (must be identical)

# Restart MySQL
kubectl rollout restart statefulset/mysql -n blog
```
