# 10. 모니터링 구성

VictoriaMetrics, Grafana, Loki 기반의 통합 모니터링 인프라 구축

## 개요

- **메트릭**: VictoriaMetrics (vmagent → vmsingle)
- **시각화**: Grafana
- **로그**: Loki + Promtail
- **가용성**: Blackbox Exporter (HTTP Probing)
- **구성요소**:
  - MySQL Exporter: DB 성능 지표 (Sidecar)
  - Ingress NGINX: 웹 트래픽 및 에러율
  - Cloudflared: 터널 상태 및 커넥션
  - Vault: 내부 메트릭 API

## 전제 조건

### 1. Argo CD 모니터링 스택 배포 확인

`observers` 애플리케이션이 정상적으로 배포되어야 합니다.

```bash
kubectl get application observers -n argocd
# 예상 출력: observers   Synced   Healthy
```

> [!WARNING]
> `observers` 애플리케이션이 없거나 `Degraded` 상태라면 먼저 [02-argocd-setup.md](./02-argocd-setup.md)를 완료하세요.

### 2. 모니터링 Pod 상태 확인

```bash
kubectl get pods -n observers

# 예상 출력:
# vmsingle-0                           1/1   Running
# vmagent-xxx                          1/1   Running
# grafana-xxx                          1/1   Running
# loki-0                               1/1   Running
# promtail-xxx                         1/1   Running
# blackbox-exporter-xxx                1/1   Running
```

### 검증 스크립트 (선택)

전제 조건을 자동으로 검증하려면:

```bash
# 프로젝트 루트에서 실행
bash scripts/check-monitoring-prerequisites.sh
```

## 구성 단계

### 1. 모니터링 스택 구성 확인

`apps/observers` 애플리케이션은 다음 Helm 차트를 사용합니다:

- `victoria-metrics-single`
- `victoria-metrics-agent`
- `grafana`
- `loki`, `promtail`
- `prometheus-blackbox-exporter`

관련 파일:
- `apps/observers/base/kustomization.yaml`

### 2. vmagent 스크레이프 설정

vmagent는 ConfigMap의 `scrape.yml`을 사용합니다.

- 기본값: `apps/observers/base/vmagent-scrape.yml`
- 프로덕션 값: `apps/observers/overlays/prod/vmagent-scrape.yml`

`vmagent-scrape.yml`에서 다음 타깃을 관리합니다:
- MySQL Exporter
- Ingress NGINX
- Cloudflared
- Vault
- Blackbox Exporter (외부 URL)

### 3. MySQL 모니터링

Ghost 데이터베이스 메트릭 수집을 위해 사이드카 컨테이너와 Service를 사용합니다.

```bash
kubectl get statefulset mysql -n blog -o jsonpath='{.spec.template.spec.containers[*].name}'
# 출력: mysql mysql-exporter

kubectl get svc -n blog mysql-exporter
```

### 4. Ingress 및 Vault/Cloudflared 모니터링

```bash
# Ingress NGINX 메트릭 활성화 확인
kubectl get deployment -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.template.spec.containers[0].args}' | grep metrics

# Cloudflared 메트릭 서비스 확인
kubectl get svc -n cloudflared cloudflared

# Vault 메트릭 API 확인
kubectl get svc -n vault vault
```

### 5. Blackbox Probing

외부 URL 헬스 체크는 vmagent 설정의 `blackbox` 잡에서 관리합니다.

```bash
# vmagent 설정 확인
kubectl get configmap -n observers vmagent-scrape -o yaml
```

## 검증 및 확인

### 1. vmagent Targets 확인

```bash
kubectl port-forward -n observers svc/vmagent 8429:8429 &
# http://localhost:8429/targets
```

주요 Target 상태 `UP` 확인:
- `mysql-exporter`
- `ingress-nginx`
- `cloudflared`
- `vault`
- `blackbox`

### 2. vmsingle UI 확인

```bash
kubectl port-forward -n observers svc/vmsingle 8428:8428 &
# http://localhost:8428/vmui
```

예시 쿼리:
- `up`
- `probe_success{job="blackbox"}`

### 3. Grafana 대시보드 확인

```bash
kubectl port-forward -n observers svc/grafana 3000:80 &
# http://localhost:3000
# admin / admin (초기값)
```

필수 대시보드 확인:
- **MySQL Overview** (ID: 7362)
- **NGINX Ingress Controller** (ID: 9614)
- **Kubernetes / Compute Resources / Namespace (Pods)**

### 4. 로그 수집 확인 (Loki)

Grafana Explore 탭에서 로그가 검색되는지 확인합니다.

```logql
{namespace="blog", app="ghost"}
```

## 트러블슈팅

문제가 발생하면 [09-troubleshooting.md](./09-troubleshooting.md)를 참고하세요.
