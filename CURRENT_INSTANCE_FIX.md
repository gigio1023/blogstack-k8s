# 현재 인스턴스 문제 해결 가이드

현재 인스턴스에 발생한 문제를 단계별로 해결합니다.

## 문제 요약

1. Ghost Ingress 생성 실패 - `configuration-snippet` annotation이 ingress-nginx에서 보안상 차단됨
2. Cloudflared CrashLoopBackOff - `--metrics` 플래그 사용법 오류
3. Ghost CrashLoopBackOff - Ingress 미생성으로 인한 부차적 문제

## 해결 절차

### Part A: 영구 수정 (Git 커밋 필요)

현재 발생한 문제의 근본 원인을 코드베이스에서 제거합니다.

#### A1. Ghost Ingress에서 불필요한 annotation 제거

`configuration-snippet`은 보안상 위험하며 ingress-nginx의 `use-forwarded-headers` 설정으로 대체됩니다.

```bash
cd ~/git/blogstack-k8s

# 현재 상태 확인
cat apps/ghost/base/ingress.yaml | grep -A 2 "configuration-snippet"
```

`configuration-snippet`이 있다면 이미 제거되어 있습니다. 없다면 다음 단계로 진행.

확인:
```bash
# configuration-snippet이 없어야 함
grep "configuration-snippet" apps/ghost/base/ingress.yaml
```

출력이 없으면 정상입니다.

#### A2. Cloudflared metrics 플래그 수정

```bash
# 현재 상태 확인
grep -A 2 "metrics" apps/cloudflared/base/deployment.yaml
```

`- --metrics`와 `- 0.0.0.0:2000`이 분리되어 있다면 수정:

```bash
# 자동 수정
sed -i 's/- --metrics$/- --metrics=0.0.0.0:2000/' apps/cloudflared/base/deployment.yaml
sed -i '/- 0\.0\.0\.0:2000$/d' apps/cloudflared/base/deployment.yaml

# 확인 (한 줄로 합쳐졌는지)
grep -A 1 "metrics" apps/cloudflared/base/deployment.yaml
```

예상 출력:
```
- --metrics=0.0.0.0:2000
- --edge-ip-version
```

#### A3. Git 커밋 및 푸시

```bash
# 변경사항 확인
git status

# 커밋 (변경된 파일만)
git add apps/ghost/base/ingress.yaml apps/cloudflared/base/deployment.yaml
git commit -m "fix: remove insecure configuration-snippet and fix cloudflared metrics flag"
git push origin main
```

Git push 완료 후 **15초 대기**:
```bash
sleep 15
```

---

### Part B: 클러스터 동기화

Argo CD를 통해 수정된 manifest를 클러스터에 적용합니다.

#### B1. Ghost Application 동기화

```bash
kubectl patch application ghost -n argocd \
  -p '{"operation": {"sync": {"revision": "HEAD"}}}' --type merge

echo "Ghost 동기화 시작됨. Ingress 생성 대기 중..."
sleep 10
```

Ingress 생성 확인:
```bash
kubectl get ingress -n blog
```

예상 출력:
```
NAME    CLASS   HOSTS              ADDRESS       PORTS   AGE
ghost   nginx   sunghogigio.com    10.42.0.x     80      5s
```

Ingress가 생성되지 않았다면:
```bash
# 에러 확인
kubectl get application ghost -n argocd -o jsonpath='{.status.conditions}' | jq '.'
```

#### B2. Cloudflared Application 동기화

```bash
kubectl patch application cloudflared -n argocd \
  -p '{"operation": {"sync": {"revision": "HEAD"}}}' --type merge

echo "Cloudflared 동기화 시작됨. Pod 재시작 대기 중..."
sleep 30
```

Cloudflared Pod 상태 확인:
```bash
kubectl get pods -n cloudflared
```

모든 Pod이 `1/1 Running` 상태여야 합니다.

CrashLoopBackOff가 남아있다면:
```bash
# 로그 확인
kubectl logs -n cloudflared -l app=cloudflared --tail=30
```

#### B3. Ghost Pod 상태 확인

```bash
kubectl get pods -n blog
```

Ghost Pod이 `1/1 Running`이면 Part C로 이동.

`CrashLoopBackOff`이면 로그 확인:
```bash
kubectl logs -n blog -l app=ghost --tail=30
```

"Migration lock" 에러가 보이면 다음 명령으로 해제:
```bash
# MySQL에서 lock 해제
kubectl exec -n blog mysql-0 -- mysql \
  -u root \
  -p$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.root_password}' | base64 -d) \
  ghost -e "UPDATE migrations_lock SET locked=0 WHERE lock_key='km01';"

# Ghost 재시작
kubectl rollout restart deployment/ghost -n blog

# 대기
sleep 60

# 재확인
kubectl get pods -n blog
```

---

### Part C: 최종 검증

모든 리소스가 정상 작동하는지 확인합니다.

#### Pod 상태

```bash
echo "=== Pod 상태 ==="
kubectl get pods -n blog
kubectl get pods -n cloudflared
kubectl get pods -n vault
kubectl get pods -n ingress-nginx
```

모든 Pod이 `1/1 Running` 상태여야 합니다.

#### Ingress 상태

```bash
echo "=== Ingress 상태 ==="
kubectl get ingress -n blog
```

`ghost` Ingress가 존재하고 ADDRESS가 할당되어야 합니다.

#### Argo CD Applications

```bash
echo "=== Argo CD Applications ==="
kubectl get applications -n argocd | grep -E "NAME|ghost|cloudflared"
```

모든 애플리케이션이 `Synced`, `Healthy` 상태여야 합니다.

#### 외부 접근 테스트

```bash
echo "=== 외부 접근 테스트 ==="
curl -I https://sunghogigio.com
echo ""
curl -I https://sunghogigio.com/ghost/
```

예상 결과:
- 메인 페이지: `HTTP/2 200`
- Ghost 관리자: `HTTP/2 302` (Cloudflare Access 리다이렉트)

---

## 문제 해결 실패 시

### Ingress 여전히 생성 안됨

```bash
# Application 에러 상세 확인
kubectl get application ghost -n argocd -o jsonpath='{.status.conditions}' | jq '.'

# Webhook 상태 확인
kubectl get validatingwebhookconfiguration ingress-nginx-admission \
  -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | wc -c
# 700 이상이어야 함

# Ingress-nginx 로그
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50
```

### Cloudflared 여전히 CrashLoopBackOff

```bash
# Deployment 적용 확인
kubectl get deployment cloudflared -n cloudflared -o yaml | grep -A 10 "args:"

# 로그 확인
kubectl logs -n cloudflared -l app=cloudflared --tail=50

# Git 변경사항 적용 확인
cat apps/cloudflared/base/deployment.yaml | grep -A 2 "metrics"
```

### Ghost 여전히 CrashLoopBackOff

```bash
# 로그 상세 확인
kubectl logs -n blog -l app=ghost --tail=50

# Secret 확인
kubectl get secret ghost-env -n blog -o jsonpath='{.data.url}' | base64 -d
echo ""

# MySQL 연결 테스트
kubectl exec -n blog -l app=ghost -- nc -zv mysql.blog.svc.cluster.local 3306
```

---

## 완료

모든 검증이 통과하면 `https://sunghogigio.com/ghost/` 접속하여 Ghost 초기 설정을 진행합니다.
