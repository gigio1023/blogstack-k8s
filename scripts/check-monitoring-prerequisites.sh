#!/usr/bin/env bash

# 모니터링 구성 전제 조건 검증 스크립트
# 사용법: bash scripts/check-monitoring-prerequisites.sh

set -euo pipefail

echo "=== 모니터링 전제 조건 검증 ==="
echo ""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

check_app_status() {
    local app_name=$1

    if ! kubectl get application "$app_name" -n argocd &>/dev/null; then
        echo -e "${RED}❌ ${app_name} Application이 없습니다.${NC}"
        echo "   → 02-argocd-setup.md를 먼저 완료하세요."
        ERRORS=$((ERRORS + 1))
        return
    fi

    local app_status
    local sync_status
    app_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
    sync_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)

    if [[ "$app_status" == "Healthy" && "$sync_status" == "Synced" ]]; then
        echo -e "${GREEN}✅ ${app_name} Application: Synced, Healthy${NC}"
    else
        echo -e "${YELLOW}⚠️  ${app_name} 상태: Sync=$sync_status, Health=$app_status${NC}"
        ERRORS=$((ERRORS + 1))
    fi
}

check_pod_ready() {
    local label_selector=$1
    local display_name=$2

    if ! kubectl get pods -n observers -l "$label_selector" &>/dev/null; then
        echo -e "${RED}❌ ${display_name} Pod를 찾을 수 없습니다.${NC}"
        ERRORS=$((ERRORS + 1))
        return
    fi

    local pod_status
    local pod_ready
    pod_status=$(kubectl get pods -n observers -l "$label_selector" -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    pod_ready=$(kubectl get pods -n observers -l "$label_selector" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)

    if [[ "$pod_status" == "Running" && "$pod_ready" == "true" ]]; then
        echo -e "${GREEN}✅ ${display_name} Pod: Running${NC}"
    else
        echo -e "${YELLOW}⚠️  ${display_name} Pod 상태: $pod_status (Ready: $pod_ready)${NC}"
        ERRORS=$((ERRORS + 1))
    fi
}

# 1. observers Application 확인
echo "1. ArgoCD observers Application 확인..."
check_app_status "observers"
echo ""

# 2. VMSingle Pod 확인
echo "2. VMSingle Pod 상태 확인..."
check_pod_ready "app.kubernetes.io/instance=vmsingle" "vmsingle"
echo ""

# 3. VMAgent Pod 확인
echo "3. VMAgent Pod 상태 확인..."
check_pod_ready "app.kubernetes.io/instance=vmagent" "vmagent"
echo ""

# 4. Grafana Pod 확인
echo "4. Grafana Pod 상태 확인..."
check_pod_ready "app.kubernetes.io/instance=grafana" "grafana"
echo ""

# 5. Loki/Promtail/Blackbox Pod 확인
echo "5. Loki/Promtail/Blackbox Pod 상태 확인..."
check_pod_ready "app.kubernetes.io/instance=loki" "loki"
check_pod_ready "app.kubernetes.io/instance=promtail" "promtail"
check_pod_ready "app.kubernetes.io/instance=blackbox-exporter" "blackbox-exporter"
echo ""

# 최종 결과
echo "==================================="
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✅ 모든 전제 조건이 충족되었습니다!${NC}"
    echo ""
    echo "이제 10-monitoring.md의 구성 단계를 진행할 수 있습니다."
    exit 0
else
    echo -e "${RED}❌ $ERRORS개의 문제가 발견되었습니다.${NC}"
    echo ""
    echo "문제 해결 후 다시 실행하거나, 02-argocd-setup.md를 참조하세요."
    exit 1
fi
