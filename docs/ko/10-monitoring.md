# 10. 모니터링 구성

Prometheus, Grafana, Loki 기반의 통합 모니터링 인프라 구축

## 개요

- **메트릭**: Prometheus (Pull 방식)
- **시각화**: Grafana
- **로그**: Loki + Promtail
- **가용성**: Blackbox Exporter (HTTP Probing)
- **구성요소**:
  - Node Exporter: 인프라 리소스
  - MySQL Exporter: DB 성능 지표 (Sidecar)
  - Ingress NGINX: 웹 트래픽 및 에러율

## 구성 단계

### 1. 모니터링 스택 확인

`apps/observers` 애플리케이션은 `kube-prometheus-stack` 헬름 차트를 기반으로 합니다.

관련 파일:
- [apps/observers/base/kustomization.yaml](../../apps/observers/base/kustomization.yaml)

주요 설정:
- `serviceMonitorSelector: {}`: 모든 ServiceMonitor 수집
- `serviceMonitorNamespaceSelector: {}`: 모든 네임스페이스 수집

### 2. MySQL 모니터링

Ghost 데이터베이스 메트릭 수집을 위해 사이드카 컨테이너와 ServiceMonitor를 추가합니다.

#### Exporter 사이드카 추가

`mysql` StatefulSet에 `prom/mysqld-exporter` 컨테이너를 추가합니다.

관련 파일:
- [apps/ghost/base/mysql-statefulset.yaml](../../apps/ghost/base/mysql-statefulset.yaml)

#### ServiceMonitor 및 Service 생성

Prometheus가 Exporter에 접근할 수 있도록 리소스를 생성합니다.

관련 파일:
- [apps/ghost/base/mysql-exporter-service.yaml](../../apps/ghost/base/mysql-exporter-service.yaml)
- [apps/ghost/base/mysql-servicemonitor.yaml](../../apps/ghost/base/mysql-servicemonitor.yaml)
- [apps/ghost/base/kustomization.yaml](../../apps/ghost/base/kustomization.yaml)

### 3. Ingress 및 가용성 모니터링

#### Ingress NGINX 메트릭

Ingress Controller의 메트릭 수집을 활성화합니다.

관련 파일:
- [apps/ingress-nginx/base/kustomization.yaml](../../apps/ingress-nginx/base/kustomization.yaml)

설정 내용:
- `controller.metrics.enabled: true`
- `controller.metrics.serviceMonitor.enabled: true`

#### Blackbox Probing

외부 URL 헬스 체크를 수행합니다.

관련 파일:
- [apps/observers-probes/base/probe.yaml](../../apps/observers-probes/base/probe.yaml)

## 검증 및 확인

### Grafana 접속

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n observers 3000:80
```
- 주소: `http://localhost:3000`
- 계정: `admin` / `admin`

### 주요 대시보드

1. **Kubernetes / Compute Resources / Namespace (Pods)**: Ghost 리소스 사용량
2. **MySQL Overview**: DB 연결 수, 쿼리 성능 (ID: 7362)
3. **NGINX Ingress Controller**: 트래픽, 응답 시간 (ID: 9614)
