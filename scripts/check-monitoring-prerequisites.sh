#!/bin/bash

# 모니터링 구성 전제 조건 검증 스크립트
# 사용법: bash scripts/check-monitoring-prerequisites.sh

set -e

echo "=== 모니터링 전제 조건 검증 ==="
echo ""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

# 1. observers Application 확인
echo "1. ArgoCD observers Application 확인..."
if ! kubectl get application observers -n argocd &>/dev/null; then
    echo -e "${RED}❌ observers Application이 없습니다.${NC}"
    echo "   → 02-argocd-setup.md를 먼저 완료하세요."
    ERRORS=$((ERRORS + 1))
else
    APP_STATUS=$(kubectl get application observers -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
    SYNC_STATUS=$(kubectl get application observers -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
    
    if [[ "$APP_STATUS" == "Healthy" && "$SYNC_STATUS" == "Synced" ]]; then
        echo -e "${GREEN}✅ observers Application: Synced, Healthy${NC}"
    else
        echo -e "${YELLOW}⚠️  observers Application 상태: Sync=$SYNC_STATUS, Health=$APP_STATUS${NC}"
        echo "   → 정상 배포를 기다리거나 ArgoCD 로그를 확인하세요."
        ERRORS=$((ERRORS + 1))
    fi
fi
echo ""

# 2. Prometheus CRD 확인
echo "2. Prometheus Operator CRD 확인..."
REQUIRED_CRDS=(
    "prometheuses.monitoring.coreos.com"
    "servicemonitors.monitoring.coreos.com"
    "probes.monitoring.coreos.com"
)

for crd in "${REQUIRED_CRDS[@]}"; do
    if kubectl get crd "$crd" &>/dev/null; then
        echo -e "${GREEN}✅ $crd${NC}"
    else
        echo -e "${RED}❌ $crd가 설치되지 않았습니다.${NC}"
        echo "   → observers 애플리케이션 배포를 확인하세요."
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# 3. Prometheus Pod 확인
echo "3. Prometheus Pod 상태 확인..."
if kubectl get pods -n observers -l app.kubernetes.io/name=prometheus &>/dev/null; then
    POD_STATUS=$(kubectl get pods -n observers -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    POD_READY=$(kubectl get pods -n observers -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
    
    if [[ "$POD_STATUS" == "Running" && "$POD_READY" == "true" ]]; then
        echo -e "${GREEN}✅ Prometheus Pod: Running${NC}"
    else
        echo -e "${YELLOW}⚠️  Prometheus Pod 상태: $POD_STATUS (Ready: $POD_READY)${NC}"
        echo "   → 배포 완료를 기다리세요 (2-3분 소요)"
    fi
else
    echo -e "${RED}❌ Prometheus Pod를 찾을 수 없습니다.${NC}"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 4. Grafana Pod 확인
echo "4. Grafana Pod 상태 확인..."
if kubectl get pods -n observers -l app.kubernetes.io/name=grafana &>/dev/null; then
    GRAFANA_STATUS=$(kubectl get pods -n observers -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    
    if [[ "$GRAFANA_STATUS" == "Running" ]]; then
        echo -e "${GREEN}✅ Grafana Pod: Running${NC}"
    else
        echo -e "${YELLOW}⚠️  Grafana Pod 상태: $GRAFANA_STATUS${NC}"
    fi
else
    echo -e "${RED}❌ Grafana Pod를 찾을 수 없습니다.${NC}"
    ERRORS=$((ERRORS + 1))
fi
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
