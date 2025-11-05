#!/bin/bash
# Argo CD Applications 빠른 재시작
# 사용법: ./scripts/quick-reset.sh

set -e

echo "=== Argo CD Applications 재시작 ==="
echo ""
echo "작업 내용:"
echo "  1. Root App 삭제 (child applications도 삭제됨)"
echo "  2. Git 최신 코드 가져오기"
echo "  3. Root App 재배포"
echo ""
echo "참고: 실제 워크로드는 점진적으로 정리되며, 자동으로 재배포됩니다."
echo ""
read -p "계속하시겠습니까? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "취소되었습니다."
  exit 0
fi

echo ""
echo "[1/3] Root App 삭제 중..."
kubectl delete application blogstack-root -n argocd --ignore-not-found

echo "  대기 중 (10초)..."
sleep 10

echo ""
echo "[2/3] Git 최신 코드 가져오기..."
git fetch origin
git pull origin main
echo "  현재 커밋: $(git log --oneline -1)"

echo ""
echo "[3/3] Root App 재배포..."
kubectl apply -f iac/argocd/root-app.yaml

echo ""
echo "=== 완료! ==="
echo ""
echo "현재 상태:"
kubectl get applications -n argocd 2>/dev/null || echo "  Applications 생성 중..."
echo ""
echo "실시간 모니터링:"
echo "  watch -n 5 kubectl get applications -n argocd"
echo ""
echo "예상 배포 시간: 5~10분"
echo "최종 상태: 8개 applications, cloudflared/ghost만 Degraded (정상)"
