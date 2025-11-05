# blogstack-k8s

GitOps-based self-hosted Ghost blog infrastructure on k3s.

## Stack

- **Kubernetes**: k3s
- **GitOps**: Argo CD (App-of-Apps pattern)
- **Secret Management**: HashiCorp Vault OSS + Vault Secrets Operator
- **Ingress**: ingress-nginx + Cloudflare Tunnel (Zero Trust)
- **Application**: Ghost 5.x + MySQL 8.0
- **Observability**: Prometheus, Grafana, Loki, Promtail, Blackbox Exporter

## Prerequisites

- Oracle Cloud VM.Standard.A1.Flex (ARM64, 4 OCPU, 24GB RAM)
- Domain name (Cloudflare managed)
- Cloudflare Zero Trust account + Tunnel

## Architecture

```
Internet → Cloudflare Tunnel (outbound HTTPS)
   ↓
Oracle Cloud VM (ARM64)
   ├─ k3s Cluster
   │  ├─ Argo CD (GitOps)
   │  ├─ Vault + VSO (Secrets)
   │  ├─ cloudflared (HA) → ingress-nginx → Ghost + MySQL
   │  └─ Prometheus + Grafana + Loki
   └─ Local Path Provisioner (PVC)
```

## Quick Start

### 1. Customize Configuration

```bash
git clone https://github.com/<your-org>/blogstack-k8s
cd blogstack-k8s

# Update repository URLs
OLD_URL="https://github.com/your-org/blogstack-k8s"
NEW_URL="https://github.com/<your-org>/blogstack-k8s"

sed -i "s|$OLD_URL|$NEW_URL|g" iac/argocd/root-app.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/apps.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/project.yaml

# Update domain in config/prod.env
vim config/prod.env

git add .
git commit -m "chore: customize configuration"
git push origin main
```

### 2. Install k3s

```bash
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --write-kubeconfig-mode 644
```

### 3. Install Argo CD

```bash
cd ~/blogstack-k8s

kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment -n argocd --all

# Configure Kustomize
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm --load-restrictor LoadRestrictionsNone"}}'

kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd

# Deploy
kubectl apply -f clusters/prod/project.yaml
kubectl apply -f iac/argocd/root-app.yaml
```

Monitor:
```bash
watch kubectl get applications -n argocd
```

### 4. Initialize Vault

Follow detailed setup guide: [docs/en/03-vault-setup.md](./docs/en/03-vault-setup.md)

Quick outline:

```bash
kubectl get pods -n vault -w
kubectl port-forward -n vault svc/vault 8200:8200 &

export VAULT_ADDR=http://127.0.0.1:8200
cd security/vault/init-scripts
./01-init-unseal.sh

# Backup init-output.json
export VAULT_TOKEN=$(jq -r .root_token init-output.json)

# Configure Kubernetes Auth (see full guide)

# Inject secrets
vault kv put kv/blog/prod/ghost \
  url="https://yourdomain.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="<password>" \
  database__connection__database="ghost"

vault kv put kv/blog/prod/mysql \
  root_password="<root-password>" \
  user="ghost" \
  password="<same-password>" \
  database="ghost"

vault kv put kv/blog/prod/cloudflared \
  token="<tunnel-token>"
```

### 5. Configure Cloudflare

Follow: [docs/en/03-2-cloudflare-setup.md](./docs/en/03-2-cloudflare-setup.md)

1. Networks → Tunnels → Public Hostname
2. Add: yourdomain.com → http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
3. Access → Applications → Add `/ghost/*` path with authentication

### 6. Verify

```bash
kubectl get applications -n argocd
kubectl get pods -A
curl -I https://yourdomain.com
```

## Documentation

### Complete Setup Guides

1. [00-prerequisites.md](./docs/en/00-prerequisites.md)
2. [CUSTOMIZATION.md](./docs/en/CUSTOMIZATION.md)
3. [01-infrastructure.md](./docs/en/01-infrastructure.md)
4. [02-argocd-setup.md](./docs/en/02-argocd-setup.md)
5. [03-vault-setup.md](./docs/en/03-vault-setup.md)
6. [03-1-ingress-setup.md](./docs/en/03-1-ingress-setup.md)
7. [03-2-cloudflare-setup.md](./docs/en/03-2-cloudflare-setup.md)
8. [03-3-verification.md](./docs/en/03-3-verification.md)
9. [03-troubleshooting.md](./docs/en/03-troubleshooting.md)
10. [04-operations.md](./docs/en/04-operations.md)

### Korean Documentation

Complete Korean versions: [docs/ko/](./docs/ko/)

### Additional Resources

- [SECURITY.md](./docs/en/SECURITY.md)
- [CONFORMANCE.md](./docs/en/CONFORMANCE.md)
- [ENVIRONMENTS.md](./docs/en/ENVIRONMENTS.md)
- [CI.md](./docs/en/CI.md)
- [RESET.md](./docs/en/RESET.md)

## Repository Structure

```
blogstack-k8s/
├── config/
│   └── prod.env             # Centralized config
├── iac/argocd/
│   └── root-app.yaml        # Root Application
├── clusters/prod/
│   ├── project.yaml         # AppProject
│   └── apps.yaml            # Child Applications
├── apps/
│   ├── ghost/               # Ghost + MySQL
│   ├── ingress-nginx/       # Ingress controller
│   ├── cloudflared/         # Cloudflare Tunnel
│   └── observers/           # Prometheus + Grafana + Loki
├── security/
│   ├── vault/               # Vault (Raft)
│   └── vso/                 # Vault Secrets Operator
└── docs/                    # Documentation
```

## Operations

### Monitoring

```bash
# Grafana
kubectl port-forward -n observers svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000 (admin/prom-operator)

# Prometheus
kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090
```

### Backup (Optional)

```bash
vault kv put kv/blog/prod/backup \
  AWS_ENDPOINT="https://namespace.compat.objectstorage.region.oraclecloud.com" \
  AWS_ACCESS_KEY_ID="<key>" \
  AWS_SECRET_ACCESS_KEY="<secret>" \
  BUCKET_NAME="blog-backups"

kubectl apply -f apps/ghost/optional/
kubectl apply -f security/vso/secrets/optional/
```

### SMTP (Optional)

```bash
vault kv patch kv/blog/prod/ghost \
  mail__transport="SMTP" \
  mail__options__service="Mailgun" \
  mail__options__host="smtp.mailgun.org" \
  mail__options__port="587" \
  mail__options__auth__user="postmaster@mg.yourdomain.com" \
  mail__options__auth__pass="<password>"
```

## Troubleshooting

### Argo CD Application Unknown/Unknown

```bash
kubectl describe application blogstack-root -n argocd
kubectl apply -f clusters/prod/project.yaml
```

### Kustomize Error

```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm --load-restrictor LoadRestrictionsNone"}}'

kubectl rollout restart deployment argocd-repo-server -n argocd
```

### Vault Sealed

```bash
kubectl port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR=http://127.0.0.1:8200

vault operator unseal <key-1>
vault operator unseal <key-2>
vault operator unseal <key-3>
```

See [03-troubleshooting.md](./docs/en/03-troubleshooting.md) for more.

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

## Development

```bash
# Validate manifests
kustomize build apps/ghost/overlays/prod
kustomize build apps/ghost/overlays/prod | kubeconform -strict

# Health check
./scripts/health-check.sh
```

## License

MIT

## Notes

- Default Grafana password: `admin` (change after first login)
- Vault data persists in PVC
- Cloudflare Tunnel runs in HA mode (2 replicas)
- Ghost uses MySQL StatefulSet with persistent storage
- Backup and SMTP features are optional
