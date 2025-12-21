# VictoriaMetrics 단일 구성 설계안 (Operator 미사용)

## 목적
- Prometheus Operator/CRD 의존 제거
- Argo CD App-of-Apps에 맞는 단순한 배포 흐름
- 개인 블로그 기준의 낮은 운영 부담
- 필요한 메트릭만 최소 구성으로 수집

## 범위
- 메트릭 스택: vmsingle + vmagent + Grafana + blackbox-exporter
- 로그: Loki + Promtail 유지 (현행 유지)
- 기존 exporter: mysql-exporter sidecar, ingress-nginx, cloudflared, vault
- 선택사항: node-exporter, kube-state-metrics (대시보드 필요 시)

## 비범위
- 고가용성(HA) 클러스터
- 장기 보관(>30일) 및 오브젝트 스토리지 연계
- 기본 알림(vmalert) 구성

## 설계 원칙
- CRD/Operator 0개
- observers 네임스페이스 유지 (기존 NetworkPolicy와 호환)
- overlays/prod에서 환경별 값 변경
- vmagent 스크레이프 설정은 ConfigMap 리소스로 관리

## 구성 개요
- vmsingle: 저장/쿼리 API (8428)
- vmagent: 스크레이프 + remote_write → vmsingle
- grafana: Prometheus 타입 데이터소스 사용
- blackbox-exporter: 외부 URL 헬스체크
- loki/promtail: 로그 수집 (현행 유지)

## 데이터 흐름
```
scrape targets
  ├─ mysql-exporter (blog)
  ├─ ingress-nginx metrics
  ├─ cloudflared metrics
  ├─ vault metrics
  └─ blackbox-exporter (external URLs)
        ↓
      vmagent ── remote_write ──> vmsingle ──> grafana
```

## Argo CD/Repo 구조 설계
- apps/observers 재사용 (Application 이름: observers)
- 단일 애플리케이션으로 배포 (CRD 앱/Probe 앱 제거)
- clusters/prod/apps.yaml
  - observers-crds, observers-probes 제거
  - observers 유지
- Makefile 및 scripts/validate.sh에 새 오버레이 포함
- docs/ko/10-monitoring.md, docs/ko/08-operations.md 등 모니터링 문서 갱신

## Helm 차트 구성 방향 (예시)
- vmsingle: victoria-metrics-single
- vmagent: victoria-metrics-agent
- grafana: grafana
- loki, promtail: grafana 차트 유지
- blackbox-exporter: prometheus-community 차트 유지

## vmsingle 권장 설정 (초안)
- retention: 14d (개인 블로그 기준)
- storage: 10Gi ~ 20Gi
- resources: 200m CPU / 512Mi 메모리 수준부터 시작

## vmagent 권장 설정 (초안)
- scrape_interval: 30s
- remote_write: http://vmsingle.observers.svc.cluster.local:8428/api/v1/write
- 메트릭 필터링은 relabel로 최소화

## 스크레이프 대상 설계
서비스 이름과 포트는 실제 배포 후 확인이 필요하다. 기본 방향은 endpoints 기반 선택이다.

- mysql-exporter
  - namespace: blog
  - service: mysql-exporter
  - port name: metrics
- ingress-nginx
  - metrics service 활성화 유지
  - 서비스명 예시: ingress-nginx-controller-metrics
  - port name: metrics
- cloudflared
  - namespace: cloudflared
  - service: cloudflared
  - port name: metrics
- vault
  - namespace: vault
  - service: vault
  - port name: http
  - path: /v1/sys/metrics?format=prometheus
- blackbox-exporter
  - namespace: observers
  - service: blackbox-exporter
  - 외부 URL은 overlays/prod의 vmagent-scrape.yml에서 관리

## vmagent 스크레이프 설정 예시
아래는 방향 제시용 예시이며, 실제 값은 배포 후 서비스명과 포트를 확인한다.

```yaml
global:
  scrape_interval: 30s

scrape_configs:
  - job_name: mysql-exporter
    kubernetes_sd_configs:
      - role: endpoints
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: blog;mysql-exporter;metrics

  - job_name: cloudflared
    kubernetes_sd_configs:
      - role: endpoints
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: cloudflared;cloudflared;metrics

  - job_name: vault
    kubernetes_sd_configs:
      - role: endpoints
    metrics_path: /v1/sys/metrics
    params:
      format: [prometheus]
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: vault;vault;http

  - job_name: ingress-nginx
    kubernetes_sd_configs:
      - role: endpoints
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: ingress-nginx;ingress-nginx-controller-metrics;metrics

  - job_name: blackbox
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://example.invalid/
          - https://example.invalid/sitemap.xml
          - https://example.invalid/ghost/
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter.observers.svc.cluster.local:9115
```

## Kustomize 치환 설계
- vmagent 스크레이프 설정을 ConfigMap 리소스로 관리
- base에는 기본 스크레이프 템플릿 유지
- overlays/prod에서 `vmagent-scrape.yml`을 교체해 blackbox targets를 확정

## 결정 사항
- observers 앱 유지, observers-crds/observers-probes 제거
- node-exporter, kube-state-metrics는 기본 제외 (필요 시 추가)
- Alloy 제거 (metrics 수집은 vmagent로 단일화)
- retentionPeriod: 14d, PV size: 10Gi 시작값

## 기존 Prometheus 리소스 정리 항목
- apps/observers-crds 제거
- apps/observers-probes 제거
- ServiceMonitor/Probe 리소스 제거
  - apps/ghost/base/mysql-servicemonitor.yaml
  - apps/cloudflared/overlays/prod/servicemonitor.yaml
  - security/vault/servicemonitor.yaml
  - ingress-nginx 차트 값에서 serviceMonitor 비활성화

## Grafana 데이터소스 방향
- 타입: Prometheus
- URL: http://vmsingle.observers.svc.cluster.local:8428
- 기존 Loki 데이터소스는 유지

## 검증 플로우 (운영 관점)
- vmagent /metrics 확인: 스크레이프 타깃 UP 여부
- Grafana에서 up, probe_success 쿼리 확인
- 외부 URL probe_success=1 여부 확인

## docs/ko 수정 계획
- docs/ko/README.md: 모니터링 스택 설명을 VictoriaMetrics 기반으로 수정, 10-monitoring 링크 설명 갱신
- docs/ko/02-argocd-setup.md: observers 앱 설명/Sync Wave 테이블 수정, CRD 확인 절차 삭제, 모니터링 스택 확인 절차를 vmsingle/vmagent 기준으로 갱신
- docs/ko/06-verification.md: Prometheus 포트포워딩을 vmsingle/grafana 기준으로 변경
- docs/ko/08-operations.md: Prometheus Targets 섹션을 vmagent/vmsingle 중심으로 재작성, Grafana 접속 경로 확인
- docs/ko/09-troubleshooting.md: Prometheus Operator/ServiceMonitor 관련 이슈 제거, vmagent 스크레이프/blackbox 관련 점검 항목 추가
- docs/ko/10-monitoring.md: 전체 구조를 vmsingle/vmagent/blackbox 기준으로 재작성, ServiceMonitor/Probe/CRD 전제 제거
- docs/ko/CONFORMANCE.md: 모니터링 스택/검증 항목을 VictoriaMetrics 기준으로 수정, Prometheus 언급 제거
- docs/ko/CI.md: Prometheus Operator CRD 관련 문구 삭제 또는 VictoriaMetrics 기반 검증으로 교체
- docs/ko/CUSTOMIZATION.md: Blackbox Probe 설정 파트를 vmagent 설정/ConfigMap 치환 방식으로 갱신

## 결정 필요 사항
- retention 기간과 스토리지 용량
- node-exporter, kube-state-metrics 포함 여부
- vmalert 필요 여부
