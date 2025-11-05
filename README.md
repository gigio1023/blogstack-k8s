# blogstack-k8s

GitOps-based self-hosted Ghost blog infrastructure on k3s.

## Stack

- **Kubernetes**: k3s
- **GitOps**: Argo CD (App-of-Apps pattern)
- **Secret Management**: HashiCorp Vault OSS + Vault Secrets Operator
- **Ingress**: ingress-nginx + Cloudflare Tunnel (Zero Trust)
- **Application**: Ghost 5.x + MySQL 8.0
- **Observability**: Prometheus, Grafana, Loki, Promtail, Blackbox Exporter

---

## Prerequisites

### Required

- Oracle Cloud VM.Standard.A1.Flex (ARM64, 4 OCPU, 24GB RAM)
- Domain name (Cloudflare Registrar recommended)
- Cloudflare Zero Trust account + Tunnel

### Optional

- OCI Object Storage (for backup feature)
- SMTP service (for email feature)

---

## Architecture

```
Internet
   │ HTTPS (Cloudflare Tunnel, outbound)
   ▼
Oracle Cloud VM (ARM64)
   ├─ k3s Cluster
   │  ├─ Argo CD (GitOps)
   │  ├─ Vault + VSO (Secret Management)
   │  ├─ cloudflared (x2, HA) → ingress-nginx → Ghost + MySQL
   │  ├─ Prometheus + Grafana + Loki (Observability)
   │  └─ Blackbox Exporter (External probing)
   └─ Local Path Provisioner (PVC)
```

---

## Quick Start

### 1. Customize Configuration

Before deployment, modify repository URLs and domain:

```bash
# Clone your fork
git clone https://github.com/<your-org>/blogstack-k8s
cd blogstack-k8s

# Update Git repository URLs (3 files)
OLD_URL="https://github.com/your-org/blogstack-k8s"
NEW_URL="https://github.com/<your-org>/blogstack-k8s"

sed -i "s|$OLD_URL|$NEW_URL|g" iac/argocd/root-app.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/apps.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/project.yaml

# Update domain
vim config/prod.env
# domain=yourdomain.com → domain=actual-domain.com

# Commit changes
git add .
git commit -m "chore: customize configuration"
git push origin main
```

See [docs/CUSTOMIZATION.md](./docs/CUSTOMIZATION.md) for details.

### 2. Install k3s

SSH into VM:

```bash
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --write-kubeconfig-mode 644

kubectl get nodes
```

### 3. Install Argo CD

```bash
# Clone repository (inside VM)
cd ~
git clone https://github.com/<your-org>/blogstack-k8s
cd blogstack-k8s

# Create namespace
kubectl create namespace argocd

# Install Argo CD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods
kubectl wait --for=condition=available --timeout=300s deployment -n argocd --all

# Configure Kustomize (Helm support + load restrictor)
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm --load-restrictor LoadRestrictionsNone"}}'

kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd

# Create AppProject
kubectl apply -f clusters/prod/project.yaml

# Deploy Root Application
kubectl apply -f iac/argocd/root-app.yaml
```

Monitor application sync:

```bash
watch kubectl get applications -n argocd
```

Expected sync order (by wave):
- `-2`: observers (Prometheus, Grafana, Loki - installs monitoring CRDs)
- `-1`: observers-probes, ingress-nginx
- `0`: cloudflared
- `1`: vault
- `2`: vso-operator (installs Vault CRDs)
- `3`: vso-resources (Vault connections and secrets)
- `4`: ghost

### 4. Initialize Vault (must follow full guide)

Important: You must configure Kubernetes Auth roles and policies before injecting secrets. Follow the detailed guide: docs/ko/03-vault-setup.md (or docs/en/03-vault-setup.md).

Quick outline (do not skip the full guide):

```bash
# Wait for Vault pod
kubectl get pods -n vault -w

# Port-forward
kubectl port-forward -n vault svc/vault 8200:8200 &

# Initialize
export VAULT_ADDR=http://127.0.0.1:8200
cd security/vault/init-scripts
./01-init-unseal.sh

# Backup init-output.json (contains unseal keys and root token)

# Login
export VAULT_TOKEN=$(jq -r .root_token init-output.json)

# Enable/configure Kubernetes auth and write minimal policies/roles (see full guide)
# ... see docs/ko/03-vault-setup.md → "Kubernetes Auth 구성" 섹션 ...

# Inject secrets (match exactly these keys)

# Ghost
vault kv put kv/blog/prod/ghost \
  url="https://yourdomain.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="<password>" \
  database__connection__database="ghost"

# MySQL (must include all four keys)
vault kv put kv/blog/prod/mysql \
  root_password="<mysql-root-password>" \
  user="ghost" \
  password="<same-as-ghost-db-password>" \
  database="ghost"

# Cloudflare Tunnel Token
vault kv put kv/blog/prod/cloudflared \
  token="<cloudflare-tunnel-token>"
```

After completing the full guide and secret injection, `cloudflared` and `ghost` applications will become healthy.

### 5. Configure Cloudflare Tunnel

1. Go to Cloudflare Zero Trust dashboard
2. Networks → Tunnels → Public Hostname
3. Add:
   - Domain: `yourdomain.com`
   - Service: `http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80`
4. Access → Applications → Add Application
5. Configure `/ghost/*` path with authentication

### 6. Verify

```bash
# Check applications
kubectl get applications -n argocd

# Check pods
kubectl get pods -A

# Access blog
curl -I https://yourdomain.com
```

---

## Documentation

### English Documentation

Core setup guides (follow in order):

1. [00-prerequisites.md](./docs/en/00-prerequisites.md) - Setup checklist
2. [CUSTOMIZATION.md](./docs/en/CUSTOMIZATION.md) - Configuration guide
3. [01-infrastructure.md](./docs/en/01-infrastructure.md) - k3s installation
4. [02-argocd-setup.md](./docs/en/02-argocd-setup.md) - Argo CD setup
5. [03-vault-setup.md](./docs/en/03-vault-setup.md) - Vault initialization

### Korean Documentation (한국어 문서)

Complete documentation in Korean:

1. [00-prerequisites.md](./docs/ko/00-prerequisites.md) - 사전 준비사항
2. [CUSTOMIZATION.md](./docs/ko/CUSTOMIZATION.md) - 설정 가이드
3. [01-infrastructure.md](./docs/ko/01-infrastructure.md) - k3s 설치
4. [02-argocd-setup.md](./docs/ko/02-argocd-setup.md) - Argo CD 설치
5. [03-vault-setup.md](./docs/ko/03-vault-setup.md) - Vault 초기화
6. [03-1-ingress-setup.md](./docs/ko/03-1-ingress-setup.md) - Ingress-nginx 설정
7. [03-2-cloudflare-setup.md](./docs/ko/03-2-cloudflare-setup.md) - Cloudflare Tunnel 및 Zero Trust
8. [03-3-verification.md](./docs/ko/03-3-verification.md) - 전체 시스템 검증
9. [03-troubleshooting.md](./docs/ko/03-troubleshooting.md) - 트러블슈팅
10. [04-operations.md](./docs/ko/04-operations.md) - 운영 가이드
11. [RESET.md](./docs/ko/RESET.md) - 전체 재시작 가이드

Additional:
- [CONFORMANCE.md](./docs/ko/CONFORMANCE.md) - 설계 및 정합성
- [SECURITY.md](./docs/ko/SECURITY.md) - 보안 상세
- [ENVIRONMENTS.md](./docs/ko/ENVIRONMENTS.md) - 다중 환경 구성
- [CI.md](./docs/ko/CI.md) - GitHub Actions CI

---

## Repository Structure

```
blogstack-k8s/
├── config/                  # Centralized configuration
│   └── prod.env             # Domain, timezone, etc.
├── iac/argocd/              # Argo CD bootstrap
│   └── root-app.yaml        # Root Application
├── clusters/prod/           # App-of-Apps entry point
│   ├── project.yaml         # AppProject definition
│   └── apps.yaml            # Child Applications (6)
├── apps/                    # Application manifests
│   ├── ghost/               # Ghost + MySQL (StatefulSet)
│   ├── ingress-nginx/       # Ingress controller
│   ├── cloudflared/         # Cloudflare Tunnel (HA)
│   └── observers/           # Prometheus + Grafana + Loki
├── security/
│   ├── vault/               # Vault (Raft backend)
│   └── vso/                 # Vault Secrets Operator
├── scripts/
│   ├── bootstrap.sh         # Automated setup (optional)
│   └── health-check.sh      # Health check utility
└── docs/                    # Documentation
```

---

## Operations

### Monitoring

```bash
# Grafana
kubectl port-forward -n observers svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000 (admin / admin)

# Prometheus
kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090

# Loki
kubectl port-forward -n observers svc/loki 3100:3100
```

### Backup (Optional)

Enable backup to OCI Object Storage:

```bash
# Add backup secret to Vault
vault kv put kv/blog/prod/backup \
  AWS_ENDPOINT="https://namespace.compat.objectstorage.region.oraclecloud.com" \
  AWS_ACCESS_KEY_ID="<access-key>" \
  AWS_SECRET_ACCESS_KEY="<secret-key>" \
  BUCKET_NAME="blog-backups" \
  AWS_REGION="us-phoenix-1"

# Apply backup CronJob
kubectl apply -f apps/ghost/optional/

# Apply VSO secret for backup
kubectl apply -f security/vso/secrets/optional/
```

See [docs/03-vault-setup.md](./docs/03-vault-setup.md) (Optional Features).

### SMTP Email (Optional)

Add SMTP configuration to Ghost secret:

```bash
vault kv patch kv/blog/prod/ghost \
  mail__transport="SMTP" \
  mail__options__service="Mailgun" \
  mail__options__host="smtp.mailgun.org" \
  mail__options__port="587" \
  mail__options__auth__user="postmaster@mg.yourdomain.com" \
  mail__options__auth__pass="<mailgun-password>"
```

---

## Troubleshooting

### Argo CD Application Unknown/Unknown

Check AppProject:

```bash
kubectl describe application blogstack-root -n argocd

# If "project blog which does not exist":
kubectl apply -f clusters/prod/project.yaml

# If "do not match any of the allowed destinations":
# Verify clusters/prod/project.yaml includes argocd namespace in destinations
```

### Kustomize "must specify --enable-helm"

```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm --load-restrictor LoadRestrictionsNone"}}'

kubectl rollout restart deployment argocd-repo-server -n argocd
```

### Ghost Login Loop

Check X-Forwarded-Proto header in ingress-nginx:

```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

### Vault Sealed

Manual unseal required after node restart:

```bash
kubectl port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR=http://127.0.0.1:8200

vault operator unseal <unseal-key-1>
vault operator unseal <unseal-key-2>
vault operator unseal <unseal-key-3>
```

See [docs/04-operations.md](./docs/04-operations.md) for more.

---

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
| Probe | Blackbox Exporter | 8.1+ |

---

## Development

### Validate Manifests

```bash
# Kustomize build
kustomize build apps/ghost/overlays/prod

# Kubeconform validation
kustomize build apps/ghost/overlays/prod | kubeconform -strict

# GitHub Actions CI runs validation on push/PR
```

### Local Testing

```bash
# Test health check
./scripts/health-check.sh

# Port-forward services
kubectl port-forward -n blog svc/ghost 2368:2368
```

---

## License

MIT

---

## Notes

- Default Grafana password: `admin` (change after first login)
- Vault data persists in PVC (backed by Local Path Provisioner)
- Cloudflare Tunnel runs in HA mode (2 replicas)
- Ghost uses MySQL StatefulSet with persistent storage
- Backup and SMTP features are optional and disabled by default
