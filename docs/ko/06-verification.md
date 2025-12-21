# 06. 전체 시스템 검증

## Pod 상태 확인

```bash
kubectl get pods -n blog
# ghost, mysql: 1/1 Running

kubectl get pods -n cloudflared
# 1/1 Running

kubectl get applications -n argocd
# Synced Healthy

kubectl get ingress -n blog
# ghost ingress 생성
```

## 네트워크 테스트

```bash
# MySQL 연결
kubectl exec -n blog mysql-0 -- mysql \
  -u ghost \
  -p$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.password}' | base64 -d) \
  ghost -e "SELECT 1;"

# 외부 접근
curl -I https://yourdomain.com
# HTTP/2 200

curl -I https://yourdomain.com/ghost/
# HTTP/2 302 (Access 인증)
```

## Ghost 초기 설정

1. `https://yourdomain.com/ghost/` 접속
2. Cloudflare Access 인증 (Zero Trust 설정한 경우)
3. 관리자 계정 생성
4. 첫 게시글 작성

## 모니터링 접근 (선택)

### VictoriaMetrics (vmagent)

```bash
kubectl port-forward -n observers svc/vmagent 8429:8429 &
# http://localhost:8429/targets
```

### VictoriaMetrics (vmsingle)

```bash
kubectl port-forward -n observers svc/vmsingle 8428:8428 &
# http://localhost:8428/vmui
```

### Grafana

```bash
kubectl port-forward -n observers svc/grafana 3000:80 &
# http://localhost:3000
# admin / admin
```

## 백업 테스트 (선택)

```bash
kubectl create job --from=cronjob/mysql-backup mysql-backup-test -n blog
kubectl logs -f job/mysql-backup-test -n blog
```

## 트러블슈팅

### Ghost Pod CrashLoopBackOff

```bash
kubectl logs -n blog <ghost-pod>
# MySQL 연결 실패 확인

# MySQL password 확인
kubectl get secret -n blog ghost-env -o jsonpath='{.data.database__connection__password}' | base64 -d
kubectl get secret -n blog mysql-secret -o jsonpath='{.data.password}' | base64 -d
# 두 값 동일해야 함
```

### 503 Service Unavailable

```bash
kubectl get pods -n blog
kubectl get ingress -n blog

kubectl describe ingress ghost -n blog
```

## 다음 단계

→ [07-smtp-setup.md](./07-smtp-setup.md) - SMTP 이메일 설정 (필수)

→ [08-operations.md](./08-operations.md) - 운영 및 유지보수

→ [09-troubleshooting.md](./09-troubleshooting.md) - 트러블슈팅
