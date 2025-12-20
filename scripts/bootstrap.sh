#!/usr/bin/env bash
set -euo pipefail

# blogstack-k8s Bootstrap Script
# 전제: k3s가 이미 설치되어 있어야 함
#
# ⚠️ 주의: 이 스크립트는 선택사항입니다.
# 처음 설치하시는 분은 docs/02-argocd-setup.md의 수동 설치를 권장합니다.
# - 각 단계를 이해하고 학습할 수 있습니다
# - 문제 발생 시 정확한 원인 파악이 가능합니다

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
    
    # Git URL customization check (CRITICAL)
    log_info "Checking Git Repository URL customization..."
    if grep -rq "your-org/blogstack-k8s" "$ROOT_DIR/iac/" "$ROOT_DIR/clusters/" 2>/dev/null; then
        log_error "Git Repository URL not customized!"
        log_error "Found 'your-org' in configuration files."
        log_error ""
        log_error "Please follow docs/CUSTOMIZATION.md to change Git URLs:"
        log_error "  - iac/argocd/root-app.yaml"
        log_error "  - clusters/prod/apps.yaml"
        log_error "  - clusters/prod/project.yaml"
        log_error ""
        log_error "After changing, commit and push to your repository."
        exit 1
    fi
    log_info "Git URL check passed"
    
    # Domain check (warning only)
    if grep -q "domain=yourdomain.com" "$ROOT_DIR/config/prod.env" 2>/dev/null; then
        log_warn "Domain still set to 'yourdomain.com' in config/prod.env"
        log_warn "Please update before final deployment"
        log_warn ""
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

configure_argocd() {
    log_info "Configuring Argo CD (Kustomize Helm support + Load Restrictor)..."
    
    kubectl patch configmap argocd-cm -n argocd --type merge \
        -p '{"data":{"kustomize.buildOptions":"--enable-helm --load-restrictor LoadRestrictionsNone"}}'
    
    log_info "Restarting Argo CD Repo Server..."
    kubectl rollout restart deployment argocd-repo-server -n argocd
    kubectl rollout status deployment argocd-repo-server -n argocd --timeout=120s
    
    log_info "Argo CD configured successfully"
}

create_appproject() {
    log_info "Creating AppProject..."
    
    if [ ! -f "$ROOT_DIR/clusters/prod/project.yaml" ]; then
        log_error "AppProject not found: $ROOT_DIR/clusters/prod/project.yaml"
        exit 1
    fi
    
    kubectl apply -f "$ROOT_DIR/clusters/prod/project.yaml"
    
    # Verify argocd namespace in destinations
    if ! kubectl get appproject blog -n argocd -o yaml | grep -q "namespace: argocd"; then
        log_warn "AppProject 'blog' may not have 'argocd' namespace in destinations"
        log_warn "This may cause Root App deployment to fail"
    fi
    
    log_info "AppProject created successfully"
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
   - vso-operator (wave 2)
   - vso-resources (wave 3)
   - ghost (wave 4)

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
   - Grafana: kubectl port-forward -n observers svc/grafana 3000:80
   - VMAgent Targets: kubectl port-forward -n observers svc/vmagent 8429:8429
   - VMSingle UI: kubectl port-forward -n observers svc/vmsingle 8428:8428

${GREEN}For detailed instructions, see:${NC}
- docs/02-argocd-setup.md
- docs/03-vault-setup.md
- docs/04-operations.md

EOF
}

main() {
    cat <<EOF

${YELLOW}╔════════════════════════════════════════════════════════════════╗
║  blogstack-k8s Bootstrap Script (Experimental)                 ║
║                                                                ║
║  ⚠️  처음 설치하시는 분은 수동 설치를 권장합니다.                    ║
║     docs/02-argocd-setup.md 참조                               ║
║                                                                ║
║  이 스크립트는 재설치나 테스트 환경용으로 제공됩니다.               ║
╚════════════════════════════════════════════════════════════════╝${NC}

EOF
    
    read -p "Continue with automated installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted. Please follow docs/02-argocd-setup.md for manual installation."
        exit 0
    fi
    
    log_info "Starting blogstack-k8s bootstrap..."
    
    check_prerequisites
    install_argocd
    configure_argocd
    create_appproject
    deploy_root_app
    wait_for_vault
    print_next_steps
    
    log_info "Bootstrap completed successfully!"
}

main "$@"
