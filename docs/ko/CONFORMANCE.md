# blogstack-k8s — Setup & Conformance (Single Source of Truth)

이 문서는 blogstack-k8s의 최종 단일 문서입니다. 초기 구축 계획(설계/선택/순서)과 구현 정합성(검증 명령)을 한 곳에 제공합니다.

원칙
- 문서가 기준입니다. 구현이 달라지면 문서를 먼저 업데이트하고, 그 다음 구현을 맞춥니다.
- 최소 복잡도, 개인 서버에서도 쉽게 셋업 가능한 경량 구성을 우선합니다.

---

## A. Plan & Setup

### A.1 목표·전제
- 목표
  1) GitOps로 코드 변경 자동 반영, 2) Ghost Admin에서 즉시 출고, 3) 지표/알림으로 상태 가시화, 4) 시크릿/설정은 Self-hosted 관리
- 플랫폼/제약: Oracle Cloud ARM64(4 OCPU/24GB) 단일 prod
- 노출/보안: Cloudflare Tunnel(CNAME → <UUID>.cfargotunnel.com), `/ghost/*`는 Zero Trust Access 보호
- 프록시 주의: Ghost는 `X-Forwarded-Proto: https` 필요(리다이렉트 루프 방지)

### A.2 리포지토리 구조(요약)
```
blogstack-k8s/
├─ docs/                 # 개요/런북/보안/본 문서
├─ clusters/prod/        # App-of-Apps 엔트리
├─ iac/argocd/           # Root App
├─ apps/                 # ingress-nginx, cloudflared, ghost(+mysql), observers
├─ security/             # vault, vso
├─ config/               # 공개 설정(prod.env)
└─ scripts/              # 유틸리티 (bootstrap, health-check)
```

### A.3 시크릿/설정 — 권장안과 대안
- 권장: HashiCorp Vault(OSS) + Vault Secrets Operator(VSO)
  - 표준 Helm 배포, Raft 스토리지, K8s Auth, 메트릭/감사
  - VSO로 K8s Secret 자동 동기화(롤링갱신 트리거)
- 대안(선택): Sealed Secrets, SOPS(+KSOPS), Infisical

### A.4 배포 순서(End-to-End)
1) k3s 설치 → 2) Argo CD + Root App(App-of-Apps) → 3) ingress-nginx(메트릭 on) → 4) cloudflared(Named Tunnel, /ready, metrics) → 5) Vault(Helm, Init/Unseal, K8s Auth) → 6) VSO(Secret 동기화) → 7) Ghost+MySQL(ingress `X-Forwarded-Proto` 확인) → 8) Observability(프로브/대시보드/알림)

### A.5 Vault 설계(요점)
- 배포: Helm, 서버 HA 비활성으로 시작, Raft 데이터/audit PVC
- 인증: Kubernetes Auth + 정책 최소권한
- 주입: VSO(Secret 동기화) 또는 Injector(파일/ENV 템플릿)
- 모니터링: `/v1/sys/metrics?format=prometheus` 스크레이프

### A.6 관측/알림(요약)
- VictoriaMetrics(vmsingle/vmagent) + Grafana + Loki + Blackbox
- 타깃: ingress 10254, cloudflared 2000, vault sys/metrics, 외부 SLIs(`/`, `/sitemap.xml`, `/ghost`)

### A.7 선택 기능
- 백업: 필요 시 `apps/ghost/optional/` 참조 (MySQL + Content → OCI S3)
- SMTP: 필수 (docs/07-smtp-setup.md 참조)

### A.8 네트워킹/보안 요점
- Cloudflare Tunnel(아웃바운드 전용), `/ghost/*` Zero Trust Access
- Ingress는 `X-Forwarded-Proto: https` 강제

### A.9 실행 체크리스트(요약)
- k3s 설치 → Argo CD 설치 → Root App 배포 → Vault Init/Unseal → 시크릿 입력(`ghost`, `mysql`, `cloudflared`) → Cloudflare Public Hostname 설정(ingress-nginx svc:80) → Health 체크 → 운영

---

## B. Docs ⇄ Implementation Conformance Map

문서의 핵심 주장과 실제 구현(매니페스트/스크립트) 위치, 그리고 빠른 검증 명령을 제공합니다.

### B.0 준비/환경
- 문서: `docs/00-prerequisites.md`, `docs/CUSTOMIZATION.md`
- 구현: `config/prod.env`

핵심 주장
- Cloudflare Zero Trust, OCI Object Storage, SMTP 필요
- 기본 설정은 `config/prod.env`, 모니터링 URL은 `apps/observers/overlays/prod/vmagent-scrape.yml`에서 관리

빠른 확인
```bash
cat config/prod.env | sed -n '1,40p'
```

---

### B.1 Argo CD 설치
- 문서: `docs/02-argocd-setup.md`
- 구현: `iac/argocd/root-app.yaml`, `clusters/prod/apps.yaml`, `clusters/prod/project.yaml`
- 선택: `scripts/bootstrap.sh` (빠른 설치용)

핵심 주장
- Argo CD 수동 설치 (권장) 또는 스크립트 → Root App 배포
- App-of-Apps, sync-wave: observers(-2) → ingress-nginx(-1) → cloudflared(0) → vault(1) → vso(2) → ghost(3)

빠른 확인
```bash
kubectl get ns argocd && kubectl get applications -n argocd
kubectl get app observers ingress-nginx cloudflared vault vso ghost -n argocd 2>/dev/null || true
```

---

### B.2 Ingress-NGINX + Cloudflare Tunnel
- 문서: `docs/03-vault-setup.md` (Cloudflare 섹션), `docs/08-operations.md`
- 구현: `apps/ingress-nginx/**`, `apps/cloudflared/**`, `apps/ghost/base/ingress.yaml`

핵심 주장
- Cloudflare Tunnel → Ingress-NGINX(Service) → Ghost로 라우팅
- Ingress는 `X-Forwarded-Proto: https` 강제

빠른 확인
```bash
kubectl get svc -n ingress-nginx | grep ingress-nginx-controller
kubectl get ingress -n blog ghost -o yaml | grep -A2 annotations
kubectl logs -n cloudflared -l app=cloudflared --tail=50 | tail -n +1
```

---

### B.3 Vault + VSO (Secrets)
- 문서: `docs/03-vault-setup.md`, `security/vault/secrets-guide.md`
- 구현: `security/vault/**`, `security/vso/**`

핵심 주장
- Vault: Helm 배포(Raft), Kubernetes Auth(1.24+ 토큰), Policies 적용
- VSO: `VaultStaticSecret`로 `ghost-env`, `mysql-secret`, `cloudflared-token` 생성

빠른 확인
```bash
kubectl get pods -n vault
kubectl exec -n vault vault-0 -- vault status
kubectl get vaultauth -A; kubectl get vaultconnection -A
kubectl get secrets -n blog | egrep 'ghost-env|mysql-secret' || true
kubectl get secrets -n cloudflared | grep cloudflared-token || true
```

---

### B.4 애플리케이션(Ghost + MySQL)
- 문서: `docs/02-argocd-setup.md`(동기화), `docs/08-operations.md`
- 구현: `apps/ghost/**`

핵심 주장
- Ghost `url`은 `config/prod.env.siteUrl`에서 주입
- MySQL은 `mysql-secret`로 초기화, Ghost는 `ghost-env`를 사용

빠른 확인
```bash
kubectl get deploy -n blog ghost -o yaml | grep -A3 'name: url'
kubectl get statefulset -n blog mysql
kubectl get pvc -n blog | egrep 'ghost-content|data-mysql'
```

---

### B.5 관측/알림
- 문서: `docs/08-operations.md`
- 구현: `apps/observers/**`

핵심 주장
- Grafana(admin/admin), vmagent Targets: ingress 10254, cloudflared 2000, vault sys/metrics, Blackbox 외부 SLI

빠른 확인
```bash
kubectl port-forward -n observers svc/grafana 3000:80 &
kubectl port-forward -n observers svc/vmagent 8429:8429 &
kubectl get configmap -n observers vmagent-scrape -o yaml | grep -A3 targets:
```

---

### B.6 백업 (선택 기능)
- 문서: `apps/ghost/optional/README.md`
- 구현: `apps/ghost/optional/backup-cronjob.yaml`, `apps/ghost/optional/content-backup-cronjob.yaml`

기본 구성에서는 비활성화됨. 필요 시 `apps/ghost/optional/` 참조하여 활성화

---

### B.7 헬스체크/운영 스크립트
- 문서: `README.md`(사용법 링크), `docs/08-operations.md`
- 구현: `scripts/health-check.sh`

핵심 주장
- 핵심 네임스페이스/앱/시크릿/외부 접근을 일괄 점검

빠른 확인
```bash
./scripts/health-check.sh || true
```

---

## C. 변경 관리 규칙
1. 구현 변경을 먼저 PR로 만들되, **문서 변경(해당 섹션) 포함**이 필수
2. `docs/CONFORMANCE.md`에 해당 변경의 검증 명령을 추가/수정
3. CI(`.github/workflows/validate.yaml`)가 통과해야 머지

---

## D. 참고 자료 (References)

### 핵심 공식 문서
- **Cloudflare Tunnel**: [DNS records](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/dns/), [Tunnel metrics](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/monitor-tunnels/metrics/), [Create tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/create-local-tunnel/)
- **Ghost**: [Reverse Proxying HTTPS](https://docs.ghost.org/faq/proxying-https-infinite-loops), [Comments](https://ghost.org/help/commenting/), [Official Docs](https://ghost.org/docs/)
- **HashiCorp Vault**: [Helm chart](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/helm), [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/sources/vault), [Agent Injector](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/injector), [Raft Deployment Guide](https://developer.hashicorp.com/vault/tutorials/day-one-raft/raft-deployment-guide), [Metrics API](https://developer.hashicorp.com/vault/api-docs/system/metrics)
- **Kubernetes**: [k3s Storage](https://docs.k3s.io/storage), [Ingress-NGINX Monitoring](https://kubernetes.github.io/ingress-nginx/user-guide/monitoring/), [Canary Deployments](https://kubernetes.github.io/ingress-nginx/examples/canary/)
- **Monitoring**: [VictoriaMetrics](https://docs.victoriametrics.com/), [Blackbox Exporter](https://github.com/prometheus/blackbox_exporter), [Grafana Contact Points](https://grafana.com/docs/grafana/latest/alerting/fundamentals/notifications/contact-points/)
- **Oracle Cloud**: [S3 Compatible API](https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/s3compatibleapi.htm)
- **Alternative Secret Tools**: [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets), [SOPS](https://github.com/getsops/sops), [Infisical](https://github.com/Infisical/infisical)

---

## E. 선택 기능 (Optional Features)

### E.1 댓글 시스템
**배경**: Ghost 네이티브 댓글은 멤버십 가입자만 사용 가능 ([Ghost Comments](https://ghost.org/help/commenting/))

**대안** (전원 공개 댓글):
- **Remark42** (오픈소스, self-hosted) - 가벼운 댓글 시스템
- **HYVOR Talk** (유료 SaaS) - 프리미엄 기능
- **Disqus** (무료/유료) - 가장 널리 사용

**구현 방법**: Ghost 테마에 JavaScript 위젯 임베드

### E.2 Ghost 테마 자동 배포
**GitHub Actions로 테마 배포 자동화**

`.github/workflows/theme-deploy.yaml`:
```yaml
name: Deploy Ghost Theme
on:
  push:
    paths:
      - 'theme/**'
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: TryGhost/action-deploy-theme@v1
        with:
          api-url: ${{ secrets.GHOST_ADMIN_API_URL }}
          api-key: ${{ secrets.GHOST_ADMIN_API_KEY }}
          theme-name: "my-theme"
          file: "theme"
```

**필요 Secrets**:
- `GHOST_ADMIN_API_URL`: `https://yourdomain.com`
- `GHOST_ADMIN_API_KEY`: Ghost Admin → Integrations → Custom Integration

### E.3 Vault Raft 스냅샷 백업
**자동화 권장사항**

CronJob으로 Raft 스냅샷 → OCI S3 업로드:

```yaml
# 예시: security/vault/backup-cronjob.yaml
schedule: "0 4 * * *"  # 매일 04:00
command:
  - /bin/sh
  - -c
  - |
    vault operator raft snapshot save /tmp/vault-snapshot.snap
    aws s3 cp /tmp/vault-snapshot.snap s3://vault-backups/$(date +%Y%m%d).snap
```

**복구**: `vault operator raft snapshot restore <file>`

### E.4 시크릿 옵션 비교표

| 옵션 | 운영형태 | 장점 | 주의 |
|------|----------|------|------|
| **Vault + VSO/Injector** | 서비스형 (self-hosted) | 표준/확장/감사/메트릭/세분권한/동적주입 | 초기화·운영 러닝커브 |
| **Sealed Secrets** | 컨트롤러+키쌍 | Git 보관 간편/저자원 | 동적 회전/감사 한계 |
| **SOPS(+KSOPS)** | Git 암호화 | 외부 서비스 無, GitOps 친화 | 실시간 회전/권한미세화 한계 |
| **Infisical** | 서비스형 (self-hosted) | UI/오퍼레이터/ESO 연동 | 구성요소 다수 |

### E.5 Canary 배포 (선택)
Ingress-NGINX의 canary 주석으로 점진적 배포 가능:

```yaml
annotations:
  nginx.ingress.kubernetes.io/canary: "true"
  nginx.ingress.kubernetes.io/canary-weight: "20"  # 20% 트래픽
```

참고: [Canary Deployments](https://kubernetes.github.io/ingress-nginx/examples/canary/)

---

## F. 트러블슈팅 (Quick Fixes)

### F.1 Ghost 리다이렉트 루프/로그인 실패
**증상**: Ghost Admin 접근 시 무한 리다이렉트

**원인**: `X-Forwarded-Proto` 헤더 미전달

**해결**:
```bash
# ingress-nginx의 use-forwarded-headers 설정 확인
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o jsonpath='{.data.use-forwarded-headers}'
# 출력: true (정상)

# Ingress 확인
kubectl get ingress -n blog ghost -o jsonpath='{.spec.ingressClassName}'
# 출력: nginx (정상)

# 문제 지속 시 재시작
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
kubectl rollout restart deployment ghost -n blog
```

참고: [Ghost Reverse Proxy Docs](https://docs.ghost.org/faq/proxying-https-infinite-loops)

### F.2 Cloudflare Tunnel 연결 끊김
**증상**: 502/504 에러, 블로그 접근 불가

**확인**:
```bash
# Pod 상태
kubectl get pods -n cloudflared

# 로그 확인
kubectl logs -n cloudflared -l app=cloudflared --tail=50

# /ready 엔드포인트
kubectl exec -n cloudflared <pod-name> -- curl http://localhost:2000/ready
```

**해결**:
```bash
# Pod 재시작
kubectl rollout restart deployment/cloudflared -n cloudflared

# Token 갱신 (필요시)
vault kv put kv/blog/prod/cloudflared token="<NEW_TOKEN>"
kubectl delete pod -n cloudflared -l app=cloudflared
```

### F.3 Vault Sealed 상태
**증상**: VSO Secret 동기화 안됨, 앱 CrashLoopBackOff

**확인**:
```bash
kubectl exec -n vault vault-0 -- vault status
# Sealed: true 이면 문제
```

**해결** (Unseal Keys 3개 필요):
```bash
kubectl exec -n vault vault-0 -- vault operator unseal <KEY1>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY2>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY3>
```

### F.4 메트릭 미수집
**확인 포인트**:
- Ingress-NGINX: `:10254/metrics` 응답 확인
- Cloudflared: `:2000/metrics` 응답 확인
- Vault: `/v1/sys/metrics?format=prometheus` 권한 확인
- Blackbox: vmagent 설정의 타깃 확인

```bash
# vmagent Targets (port-forward 후 확인)
kubectl port-forward -n observers svc/vmagent 8429:8429
# http://localhost:8429/targets

# vmagent 설정 확인
kubectl get configmap -n observers vmagent-scrape -o yaml
```

### F.5 MySQL 연결 실패
**증상**: Ghost Pod CrashLoopBackOff

**확인**:
```bash
# MySQL Pod 상태
kubectl get pods -n blog -l app=mysql

# MySQL 로그
kubectl logs -n blog mysql-0

# Ghost 로그
kubectl logs -n blog -l app=ghost
```

**해결**:
```bash
# DB 연결 정보 확인 (Vault)
vault kv get kv/blog/prod/ghost
vault kv get kv/blog/prod/mysql

# 비밀번호 일치 확인
# database__connection__password == mysql password (동일해야 함)

# MySQL 재시작
kubectl rollout restart statefulset/mysql -n blog
```
