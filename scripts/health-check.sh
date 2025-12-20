#!/usr/bin/env bash
set -euo pipefail

# blogstack-k8s Health Check Script
# 모든 컴포넌트의 상태를 확인합니다

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"

check_namespace_pods() {
    local namespace=$1
    local min_ready=${2:-1}
    
    local total=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
    local ready=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [ "$total" -eq 0 ]; then
        echo -e "$WARN Namespace $namespace: No pods found"
        return 1
    elif [ "$ready" -ge "$min_ready" ]; then
        echo -e "$PASS Namespace $namespace: $ready/$total pods ready"
        return 0
    else
        echo -e "$FAIL Namespace $namespace: $ready/$total pods ready (expected >= $min_ready)"
        return 1
    fi
}

check_vault_unsealed() {
    if ! kubectl get pods -n vault -l app.kubernetes.io/name=vault &>/dev/null; then
        echo -e "$FAIL Vault: Pods not found"
        return 1
    fi
    
    local sealed=$(kubectl exec -n vault vault-0 -- vault status -format=json 2>/dev/null | jq -r .sealed)
    
    if [ "$sealed" = "false" ]; then
        echo -e "$PASS Vault: Unsealed"
        return 0
    else
        echo -e "$FAIL Vault: Sealed (run unseal manually)"
        return 1
    fi
}

check_vso_secrets() {
    local namespaces=("blog" "cloudflared")
    local all_ok=true
    
    for ns in "${namespaces[@]}"; do
        local secrets=$(kubectl get secrets -n "$ns" 2>/dev/null | grep -E "(ghost-env|mysql-secret|cloudflared-token|backup-s3)" | wc -l)
        if [ "$secrets" -gt 0 ]; then
            echo -e "$PASS VSO Secrets in $ns: Found $secrets secrets"
        else
            echo -e "$FAIL VSO Secrets in $ns: No secrets found"
            all_ok=false
        fi
    done
    
    $all_ok
}

check_ingress() {
    local ingress_count=$(kubectl get ingress -n blog --no-headers 2>/dev/null | wc -l)
    
    if [ "$ingress_count" -gt 0 ]; then
        echo -e "$PASS Ingress: Found $ingress_count ingress resources"
        return 0
    else
        echo -e "$FAIL Ingress: No ingress resources found"
        return 1
    fi
}

check_external_access() {
    # Try to read domain from config/prod.env
    local config_file="$(dirname "$0")/../config/prod.env"
    local domain=""
    
    if [ -f "$config_file" ]; then
        domain=$(grep "^domain=" "$config_file" | cut -d'=' -f2)
    fi
    
    if [ -z "$domain" ]; then
        echo -e "$WARN External Access: config/prod.env not found or domain not set, skipping"
        return 0
    fi
    
    echo -e "Checking external access to https://$domain ..."
    
    if command -v curl &> /dev/null; then
        local status=$(curl -s -o /dev/null -w "%{http_code}" "https://$domain" --max-time 10 || echo "000")
        
        if [ "$status" = "200" ] || [ "$status" = "301" ] || [ "$status" = "302" ]; then
            echo -e "$PASS External Access: https://$domain (HTTP $status)"
            return 0
        else
            echo -e "$FAIL External Access: https://$domain (HTTP $status)"
            return 1
        fi
    else
        echo -e "$WARN curl not found, skipping external check"
        return 0
    fi
}

check_pvc() {
    local pvc_count=$(kubectl get pvc --all-namespaces --field-selector=status.phase=Bound --no-headers 2>/dev/null | wc -l)
    
    if [ "$pvc_count" -gt 0 ]; then
        echo -e "$PASS PVC: $pvc_count Bound"
        return 0
    else
        echo -e "$WARN PVC: No Bound PVCs found"
        return 1
    fi
}

check_argocd_apps() {
    local total=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
    local synced=$(kubectl get applications -n argocd -o json 2>/dev/null | jq -r '.items[] | select(.status.sync.status=="Synced") | .metadata.name' | wc -l)
    
    if [ "$total" -eq 0 ]; then
        echo -e "$FAIL Argo CD: No applications found"
        return 1
    elif [ "$synced" -eq "$total" ]; then
        echo -e "$PASS Argo CD: $synced/$total applications synced"
        return 0
    else
        echo -e "$WARN Argo CD: $synced/$total applications synced"
        kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
        return 1
    fi
}

main() {
    echo "========================================="
    echo "  blogstack-k8s Health Check"
    echo "========================================="
    echo ""
    
    local failed=0
    
    echo "--- Core Components ---"
    check_namespace_pods "argocd" 4 || ((failed++))
    check_argocd_apps || ((failed++))
    
    echo ""
    echo "--- Observability ---"
    check_namespace_pods "observers" 4 || ((failed++))
    
    echo ""
    echo "--- Networking ---"
    check_namespace_pods "ingress-nginx" 1 || ((failed++))
    check_ingress || ((failed++))
    check_namespace_pods "cloudflared" 1 || ((failed++))
    
    echo ""
    echo "--- Security ---"
    check_namespace_pods "vault" 1 || ((failed++))
    check_vault_unsealed || ((failed++))
    check_namespace_pods "vso" 1 || ((failed++))
    check_vso_secrets || ((failed++))
    
    echo ""
    echo "--- Application ---"
    check_namespace_pods "blog" 2 || ((failed++))
    check_pvc || ((failed++))
    
    echo ""
    echo "--- External ---"
    check_external_access || ((failed++))
    
    echo ""
    echo "========================================="
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}All checks passed!${NC}"
        exit 0
    else
        echo -e "${YELLOW}$failed check(s) failed${NC}"
        echo ""
        echo "Troubleshooting tips:"
        echo "1. Check logs: kubectl logs -n <namespace> <pod-name>"
        echo "2. Check events: kubectl get events -n <namespace> --sort-by='.lastTimestamp'"
        echo "3. Check Argo CD UI for sync status"
        echo "4. See docs/04-operations.md for detailed troubleshooting"
        exit 1
    fi
}

main "$@"
