#!/usr/bin/env bash
set -euo pipefail

# blogstack-k8s Bootstrap Script
# 전제: k3s가 이미 설치되어 있어야 함

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    # k3s running
    if ! kubectl get nodes &> /dev/null; then
        log_error "Cannot connect to Kubernetes. Is k3s running?"
        exit 1
    fi
    
    # jq
    if ! command -v jq &> /dev/null; then
        log_warn "jq not found. Some features may not work."
    fi
    
    log_info "Prerequisites OK"
}

install_argocd() {
    log_info "Installing Argo CD..."
    
    # Namespace 생성
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    # Argo CD 설치
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    log_info "Waiting for Argo CD to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment -n argocd --all
    
    # Admin 비밀번호 출력
    ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")
    if [ -n "$ADMIN_PASSWORD" ]; then
        log_info "Argo CD Admin Password: $ADMIN_PASSWORD"
        echo "$ADMIN_PASSWORD" > "$ROOT_DIR/.argocd-password"
        log_info "Password saved to .argocd-password (add to .gitignore!)"
    fi
    
    log_info "Argo CD installed successfully"
}

deploy_root_app() {
    log_info "Deploying Root App..."
    
    if [ ! -f "$ROOT_DIR/iac/argocd/root-app.yaml" ]; then
        log_error "Root App not found: $ROOT_DIR/iac/argocd/root-app.yaml"
        exit 1
    fi
    
    # Root App 적용
    kubectl apply -f "$ROOT_DIR/iac/argocd/root-app.yaml"
    
    log_info "Root App deployed. Applications will sync automatically."
    log_info "Monitor with: kubectl get applications -n argocd"
}

wait_for_vault() {
    log_info "Waiting for Vault Pod to be Running..."
    
    timeout=300
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if kubectl get pods -n vault -l app.kubernetes.io/name=vault 2>/dev/null | grep -q "Running"; then
            log_info "Vault Pod is Running (but sealed)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    log_warn "Vault Pod not Running within timeout. Continue manually."
}

print_next_steps() {
    # Try to read domain from config
    local config_file="$ROOT_DIR/config/prod.env"
    local domain="yourdomain.com"
    
    if [ -f "$config_file" ]; then
        domain=$(grep "^domain=" "$config_file" | cut -d'=' -f2 || echo "yourdomain.com")
    fi
    
    cat <<EOF

${GREEN}=== Bootstrap Complete ===${NC}

${YELLOW}Next Steps:${NC}

1. ${GREEN}Port-forward Argo CD UI:${NC}
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   https://localhost:8080
   Username: admin
   Password: $(cat "$ROOT_DIR/.argocd-password" 2>/dev/null || echo "see .argocd-password file")

2. ${GREEN}Wait for all Applications to sync:${NC}
   kubectl get applications -n argocd
   
   Sync order (by wave):
   - observers (wave -2)
   - ingress-nginx (wave -1)
   - cloudflared (wave 0)
   - vault (wave 1)
   - vso (wave 2)
   - ghost (wave 3)

3. ${GREEN}Initialize Vault:${NC}
   - Wait for Vault Pod to be Running (sealed state is OK)
   - Follow: docs/03-vault-setup.md
   - Port-forward: kubectl port-forward -n vault svc/vault 8200:8200
   - Run: security/vault/init-scripts/01-init-unseal.sh
   - Input secrets to Vault (see security/vault/secrets-guide.md)

4. ${GREEN}Configure Cloudflare Tunnel:${NC}
   - Create Tunnel at https://one.dash.cloudflare.com/
   - Get Token and add to Vault: kv/blog/prod/cloudflared
   - Set Public Hostname: $domain -> http://ghost.blog.svc.cluster.local
   - Configure Zero Trust Access for /ghost/* path

5. ${GREEN}Verify Ghost:${NC}
   - Access: https://$domain
   - Admin: https://$domain/ghost

6. ${GREEN}Check Monitoring:${NC}
   - Grafana: kubectl port-forward -n observers svc/kube-prometheus-stack-grafana 3000:80
   - Prometheus: kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090

${GREEN}For detailed instructions, see:${NC}
- docs/02-argocd-setup.md
- docs/03-vault-setup.md
- docs/04-operations.md

EOF
}

main() {
    log_info "Starting blogstack-k8s bootstrap..."
    
    check_prerequisites
    install_argocd
    deploy_root_app
    wait_for_vault
    print_next_steps
    
    log_info "Bootstrap completed successfully!"
}

main "$@"

