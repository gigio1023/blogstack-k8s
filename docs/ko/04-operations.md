# 04. 운영 가이드

일상 운영, 모니터링, 트러블슈팅 가이드

## 서비스 접근

### Ghost Admin

- URL: `https://sunghogigio.com/ghost`
- Cloudflare Zero Trust Access 인증 필요
- 첫 접속 시 Admin 계정 생성

### Grafana (모니터링)

```bash
# Port-forward
kubectl port-forward -n observers svc/kube-prometheus-stack-grafana 3000:80

# 브라우저: http://localhost:3000
# Username: admin
# Password: admin (기본값, apps/observers/base/kustomization.yaml에서 변경 가능)
```

### Argo CD

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
# https://localhost:8080
```

## 모니터링

### Prometheus Targets 확인

```bash
kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090/targets
```

**확인할 타깃:**
- `ingress-nginx` (포트 10254)
- `cloudflared` (포트 2000)
- `vault` (sys/metrics)
- `blackbox/blog-external` (외부 헬스체크)

### Grafana 대시보드

기본 제공 대시보드:
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace (Pods)
- NGINX Ingress Controller

**커스텀 대시보드 추가:**
1. Grafana → Dashboards → Import
2. ID 입력:
   - `7587`: nginx-ingress controller
   - `11159`: CloudFlare
   - `12904`: Vault

### 외부 헬스체크 (Blackbox)

Prometheus Query:
```promql
probe_success{job="blog-external"}
```

결과가 `1`이면 정상, `0`이면 장애

### 로그 확인 (Loki)

Grafana → Explore → Loki 선택

LogQL 예시:
```logql
# Ghost 로그
{namespace="blog", app="ghost"}

# MySQL 에러 로그
{namespace="blog", app="mysql"} |= "error"

# Cloudflared 로그
{namespace="cloudflared"}
```

## 일반적인 문제 해결

### 1. Ghost 로그인/리다이렉트 루프

**원인**: `X-Forwarded-Proto` 헤더 미전달

**해결:**
```bash
# Ingress 확인
kubectl get ingress -n blog ghost -o yaml | grep -A5 annotations

# configuration-snippet이 있는지 확인:
# proxy_set_header X-Forwarded-Proto https;
```

**대안:**
```yaml
# apps/ghost/base/ingress.yaml에 추가
metadata:
  annotations:
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header X-Forwarded-Proto https;
```

Git commit → Push → Argo CD 자동 동기화

### 2. Cloudflare Tunnel 연결 끊김

**증상**: 블로그 접근 불가 (502/504)

**확인:**
```bash
# cloudflared Pod 상태
kubectl get pods -n cloudflared

# 로그 확인
kubectl logs -n cloudflared -l app=cloudflared --tail=50

# /ready 엔드포인트
kubectl exec -n cloudflared <pod-name> -- curl http://localhost:2000/ready
```

**해결:**
```bash
# Pod 재시작
kubectl rollout restart deployment/cloudflared -n cloudflared

# Token 갱신 (필요시)
vault kv put kv/blog/prod/cloudflared token="<NEW_TOKEN>"
kubectl delete pod -n cloudflared -l app=cloudflared
```

### 3. Vault Sealed 상태

**증상**: VSO Secret 동기화 안됨, 앱 기동 실패

**확인:**
```bash
kubectl exec -n vault vault-0 -- vault status
# Sealed: true 이면 문제
```

**해결:**
```bash
# 수동 Unseal (Unseal Keys 3개 필요)
kubectl exec -n vault vault-0 -- vault operator unseal <KEY1>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY2>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY3>
```

### 4. MySQL 연결 실패

**증상**: Ghost Pod CrashLoopBackOff

**확인:**
```bash
# MySQL Pod 상태
kubectl get pods -n blog -l app=mysql

# MySQL 로그
kubectl logs -n blog mysql-0

# Ghost 로그
kubectl logs -n blog -l app=ghost
```

**해결:**
```bash
# MySQL 재시작
kubectl rollout restart statefulset/mysql -n blog

# DB 연결 정보 확인 (Vault)
vault kv get kv/blog/prod/ghost
vault kv get kv/blog/prod/mysql

# 비밀번호 일치 확인
# database__connection__password == mysql password
```

### 5. Argo CD OutOfSync

**증상**: Git 변경이 반영 안됨

**확인:**
```bash
argocd app get <app-name>
argocd app diff <app-name>
```

**해결:**
```bash
# 수동 동기화
argocd app sync <app-name>

# 강제 동기화 (Prune 포함)
argocd app sync <app-name> --force --prune
```

## 스케일링

### Ghost 스케일 업

```bash
# 2 replicas로 증가
kubectl scale deployment ghost -n blog --replicas=2

# 또는 Deployment YAML 수정 후 Git push
```

### MySQL 스케일 (StatefulSet)

단일 노드 환경에서는 1 replica 유지 권장.
다중 노드 환경에서만 스케일 가능.

## 업데이트

### Ghost 버전 업그레이드

```yaml
# apps/ghost/base/deployment.yaml
spec:
  template:
    spec:
      containers:
      - name: ghost
        image: ghost:5.XX-alpine  # 버전 변경
```

Git push → Argo CD 자동 배포

### MySQL 버전 업그레이드

주의: 데이터 손실 방지를 위해 PVC 스냅샷 또는 수동 백업 권장

```yaml
# apps/ghost/base/mysql-statefulset.yaml
spec:
  template:
    spec:
      containers:
      - name: mysql
        image: mysql:8.X  # 버전 변경
```

## 리소스 사용량 확인

```bash
# 노드 리소스
kubectl top nodes

# Pod 리소스 (Metrics Server 필요)
kubectl top pods -n blog
kubectl top pods -n observers
```

## 알림 설정

### Grafana Alerting

1. Grafana → Alerting → Contact points
2. 이메일 Contact Point 추가:
   - Name: `admin-email`
   - Type: `Email`
   - Addresses: `admin@sunghogigio.com`

3. Alert Rules 생성:
   - **Ghost Down**:
     ```promql
     probe_success{job="blog-external", instance=~"https://sunghogigio.com.*"} == 0
     ```
     Duration: 5m

   - **High Memory**:
     ```promql
     container_memory_usage_bytes{namespace="blog"} / container_spec_memory_limit_bytes > 0.9
     ```
     Duration: 10m

## 정기 점검 (월 1회)

- [ ] 디스크 사용량 확인 (`df -h`)
- [ ] Vault Unseal Keys 보관 상태 확인
- [ ] SSL 인증서 만료일 (Cloudflare 자동 갱신 확인)
- [ ] Grafana 대시보드 검토
- [ ] Ghost 플러그인 업데이트
- [ ] (선택) 백업 파일 확인 및 복구 테스트 (apps/ghost/optional/ 활성화 시)

## 긴급 복구 시나리오

### 전체 클러스터 재구축

1. (선택) 백업 데이터 확보 (MySQL dump, Ghost content/ - 백업 활성화 시)
2. k3s 재설치
3. Argo CD 재설치 → Root App 적용
4. Vault 재초기화 → 시크릿 재입력
5. MySQL 데이터 복구
6. Ghost content/ 복구

### 참고 자료

- [Ghost 공식 문서](https://ghost.org/docs/)
- [Vault 공식 문서](https://developer.hashicorp.com/vault/docs)
- [Argo CD 공식 문서](https://argo-cd.readthedocs.io/)
- [k3s 공식 문서](https://docs.k3s.io/)

---

## 선택 기능

### 백업 & 복구 (Optional)

기본 구성에서는 백업이 비활성화되어 있습니다. 활성화하려면:

#### 백업 활성화

자세한 설정: docs/03-vault-setup.md (선택 기능 B)

#### MySQL 백업

백업 CronJob이 매일 03:00에 자동 실행:

```bash
# CronJob 확인
kubectl get cronjob -n blog mysql-backup

# 최근 Job 실행 확인
kubectl get jobs -n blog

# 수동 백업 트리거
kubectl create job -n blog manual-backup-$(date +%Y%m%d) --from=cronjob/mysql-backup
```

#### 백업 파일 확인 (OCI Object Storage)

```bash
# AWS CLI로 확인 (credentials 설정 필요)
aws s3 ls s3://blog-backups/mysql/ --endpoint-url https://<namespace>.compat.objectstorage.<region>.oraclecloud.com
```

#### 복구

```bash
# 백업 다운로드
aws s3 cp s3://blog-backups/mysql/20241029-030000.sql backup.sql --endpoint-url <endpoint>

# MySQL Pod에 복사
kubectl cp backup.sql blog/mysql-0:/tmp/backup.sql

# 복구 실행
kubectl exec -n blog mysql-0 -- mysql -u root -p<password> < /tmp/backup.sql
```

