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

```bash
# Prometheus 설정 확인 (모든 ServiceMonitor 수집 여부)
kubectl get prometheus -n observers -o yaml | grep -A 2 serviceMonitorSelector
# serviceMonitorSelector: {} 확인
```

### 2. MySQL 모니터링

Ghost 데이터베이스 메트릭 수집을 위해 사이드카 컨테이너와 ServiceMonitor를 추가합니다.

#### Exporter 자격증명 준비

모니터링 전용 MySQL 사용자를 최소 권한으로 만들고 Vault에 저장해 VSO로 동기화합니다.

```bash
# Vault 정책 및 시크릿 확인
vault policy read mysql
kubectl get secret -n blog mysql-exporter-secret
```

#### Exporter 사이드카 추가

`mysql` StatefulSet에 `mysql-exporter` 컨테이너가 추가되었는지 확인합니다.

```bash
kubectl get statefulset mysql -n blog -o jsonpath='{.spec.template.spec.containers[*].name}'
# 출력: mysql mysql-exporter
```

#### ServiceMonitor 및 Service 생성

Prometheus가 Exporter에 접근할 수 있도록 리소스를 생성합니다.

```bash
# Service 확인 (9104 포트)
kubectl get svc -n blog mysql-exporter

# ServiceMonitor 확인
kubectl get servicemonitor -n blog mysql-exporter
```

### 3. Ingress 및 가용성 모니터링

#### Ingress NGINX 메트릭

Ingress Controller의 메트릭 수집 활성화 여부를 확인합니다.

```bash
# 메트릭 활성화 확인 (metrics.enabled=true)
kubectl get deployment -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.template.spec.containers[0].args}' | grep metrics

# ServiceMonitor 확인
kubectl get servicemonitor -n ingress-nginx ingress-nginx-controller
```

#### Blackbox Probing

외부 URL 헬스 체크를 위한 Probe 리소스를 확인합니다.

```bash
# Probe 리소스 확인
kubectl get probe -n observers blog-external
```

## 검증 및 확인

### 1. Pod 상태 확인

모니터링 스택의 주요 컴포넌트가 정상 동작하는지 확인합니다.

```bash
kubectl get pods -n observers
# prometheus-kube-prometheus-stack-prometheus-0 (Running)
# kube-prometheus-stack-grafana-xxx (Running)
# kube-prometheus-stack-operator-xxx (Running)
# loki-0 (Running)
# promtail-xxx (Running)
```

### 2. Prometheus Target 확인

Prometheus가 각 Exporter를 정상적으로 수집하고 있는지 확인합니다.

```bash
# 포트 포워딩
kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090 &
```

1. 브라우저 접속: `http://localhost:9090/targets`
2. 주요 Target 상태 `UP` 확인:
   - `serviceMonitor/blog/mysql-exporter/0`: MySQL Exporter
   - `serviceMonitor/ingress-nginx/ingress-nginx-controller/0`: Ingress Controller
   - `serviceMonitor/observers/kube-prometheus-stack-node-exporter/0`: Node Exporter

### 3. Grafana 대시보드 확인

수집된 메트릭이 시각화되는지 확인합니다.

```bash
# 포트 포워딩
kubectl port-forward -n observers svc/kube-prometheus-stack-grafana 3000:80 &
```

1. 브라우저 접속: `http://localhost:3000`
   - 계정: `admin` / `admin` (초기값)
2. 필수 대시보드 확인:
   - **MySQL Overview** (ID: 7362): 'MySQL Connections', 'Questions' 그래프 데이터 확인
   - **NGINX Ingress Controller** (ID: 9614): 'Controller Request Volume', 'Success Rate' 확인
   - **Kubernetes / Compute Resources / Namespace (Pods)**: `blog` 네임스페이스 선택 후 Ghost Pod 리소스 확인

### 4. 로그 수집 확인 (Loki)

Grafana Explore 탭에서 로그가 검색되는지 확인합니다.

1. Grafana → Explore 메뉴 이동
2. 데이터 소스: `Loki` 선택
3. LogQL 입력 및 실행:
   ```logql
   {namespace="blog", app="ghost"}
   ```

## 트러블슈팅

### Target이 Down 상태인 경우

1. **MySQL Exporter Down**:
   - Exporter 로그 확인:
     ```bash
     kubectl logs -n blog mysql-0 -c mysql-exporter
     ```
   - 자격증명(Secret) 확인: `mysql-exporter-secret`이 올바르게 마운트되었는지 확인

2. **Ingress NGINX Down**:
   - ServiceMonitor 라벨 매칭 확인:
     ```bash
     kubectl get servicemonitor -n ingress-nginx ingress-nginx-controller -o yaml
     # matchLabels가 Service의 라벨과 일치해야 함
     ```

### Grafana 데이터 없음

1. 시간 범위 확인: 우측 상단 Time Range가 최근 시간인지 확인
2. Prometheus 데이터 소스 연결 확인: Configuration → Data Sources → Prometheus → 'Save & Test'

