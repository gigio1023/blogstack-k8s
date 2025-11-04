# blogstack-k8s

Self-hosted Ghost 블로그를 위한 GitOps 모노레포  
k3s + Argo CD + Vault + Cloudflare Tunnel + MySQL + Ghost

---

> ⚠️ **배포 전 필수 수정사항**
>
> 이 리포지토리를 그대로 배포하면 작동하지 않습니다. 다음을 먼저 수정하세요:
>
> 1. **Git Repository URL 변경** (3개 파일)
>    - `iac/argocd/root-app.yaml`
>    - `clusters/prod/apps.yaml` (6곳)
>    - `clusters/prod/project.yaml`
>    ```yaml
>    repoURL: https://github.com/your-org/blogstack-k8s  # 실제 URL로 변경
>    ```
>
> 2. **도메인 설정** (`config/prod.env`)
>    ```env
>    domain=yourdomain.com  # 실제 도메인으로 변경
>    ```
>
> 3. **외부 서비스 준비**
>    - Cloudflare Tunnel 생성 및 토큰 발급
>    - (선택) OCI Object Storage - 백업 활성화 시
>    - (선택) SMTP 서비스 - 이메일 발송 시
>
> 자세한 내용: [`docs/CUSTOMIZATION.md`](./docs/CUSTOMIZATION.md)

---

## 주요 특징

- **GitOps**: Argo CD로 선언적 배포 및 자동 동기화
- **Self-hosted Secret 관리**: HashiCorp Vault + VSO로 시크릿 중앙화
- **Cloudflare Tunnel**: 공인 포트 개방 없이 HTTPS 노출 + Zero Trust Access
- **관측 우선**: Prometheus + Grafana + Loki + Blackbox로 전방위 모니터링
- **선택 기능**: 자동 백업 (MySQL → OCI S3), SMTP 이메일 발송

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                       Internet                              │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ HTTPS (Cloudflare Tunnel, outbound only)
                 │
┌────────────────▼────────────────────────────────────────────┐
│                 Oracle Cloud VM (ARM64)                     │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              k3s Kubernetes Cluster                  │  │
│  │                                                       │  │
│  │  ┌─────────────┐  ┌───────────┐  ┌────────────┐    │  │
│  │  │   Argo CD   │  │   Vault   │  │    VSO     │    │  │
│  │  │  (GitOps)   │  │(Raft/KVv2)│  │(Secrets)   │    │  │
│  │  └─────────────┘  └───────────┘  └────────────┘    │  │
│  │                                                       │  │
│  │  ┌─────────────────────────────────────────────┐    │  │
│  │  │       Observability Stack                   │    │  │
│  │  │  - kube-prometheus-stack (Prom + Grafana)   │    │  │
│  │  │  - Loki + Promtail                          │    │  │
│  │  │  - Blackbox Exporter (외부 SLI)             │    │  │
│  │  └─────────────────────────────────────────────┘    │  │
│  │                                                       │  │
│  │  ┌─────────────┐  ┌───────────┐  ┌────────────┐    │  │
│  │  │ cloudflared │  │ingress-   │  │   Ghost   │    │  │
│  │  │  (Tunnel)   │─>│  nginx    │─>│  + MySQL  │    │  │
│  │  │  HA x2      │  │(X-Fwd-    │  │  StatefulSet│  │  │
│  │  └─────────────┘  │  Proto)   │  └────────────┘    │  │
│  │                   └───────────┘         │            │  │
│  │                                         │            │  │
│  │                                         ▼            │  │
│  │                                    ┌────────────┐   │  │
│  │                                    │ Local PVC  │   │  │
│  │                                    │(Local Path)│   │  │
│  │                                    └────────────┘   │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

선택 기능 (기본 비활성화):
- 백업 CronJob: MySQL/Content → OCI Object Storage
- SMTP: Ghost 이메일 발송
```

## 📚 문서 가이드

### 순서대로 따라하기

처음 배포하시는 분은 다음 순서로 문서를 보세요:

1. **[00-prerequisites.md](./docs/00-prerequisites.md)** - 사전 준비사항 체크리스트
2. **[CUSTOMIZATION.md](./docs/CUSTOMIZATION.md)** - 5분 빠른 설정 (Git URL, 도메인)
3. **[01-infrastructure.md](./docs/01-infrastructure.md)** - k3s 설치
4. **[02-argocd-setup.md](./docs/02-argocd-setup.md)** - Argo CD 설치 (수동)
5. **[03-vault-setup.md](./docs/03-vault-setup.md)** - Vault 초기화 및 시크릿 입력
6. **[04-operations.md](./docs/04-operations.md)** - 운영 가이드

### 추가 문서

- **[CONFORMANCE.md](./docs/CONFORMANCE.md)** - **Setup & Conformance (단일 사실 원천)** - 계획, 검증, 참조, 트러블슈팅 통합
- [SECURITY.md](./docs/SECURITY.md) - 보안 설정 상세
- [ENVIRONMENTS.md](./docs/ENVIRONMENTS.md) - 다중 환경 구성
- [CI.md](./docs/CI.md) - GitHub Actions CI

---

## 빠른 시작

> **중요**: 이 문서의 예시에서 `sunghogigio.com`은 참조용입니다. 실제 구축 시 `config/prod.env` 파일에서 본인의 도메인으로 변경하세요.

### 1. 사전 요구사항

필수:
- Oracle Cloud VM.Standard.A1.Flex (ARM64, 4 OCPU, 24GB)
- 도메인 (Cloudflare Registrar 권장)
- Cloudflare Zero Trust 계정

선택 (필요 시):
- OCI Object Storage 버킷 (백업 활성화 시)
- SMTP 서비스 (이메일 발송 시 - Mailgun, SendGrid 등)

자세한 내용: [docs/00-prerequisites.md](./docs/00-prerequisites.md)

### 2. 설정 커스터마이징

```bash
# 리포지토리 클론
git clone https://github.com/<your-org>/blogstack-k8s
cd blogstack-k8s

# 중앙 설정 파일 수정
vim config/prod.env
# domain, email, timezone 등 수정

# Git repo URL 변경
vim iac/argocd/root-app.yaml
vim clusters/prod/apps.yaml
# repoURL을 실제 리포지토리로 변경

# Git에 커밋
git add .
git commit -m "Customize config for my blog"
git push origin main
```

### 3. 인프라 설치

VM에 SSH 접속 후:

```bash
# k3s 설치
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --write-kubeconfig-mode 644

# 확인
kubectl get nodes
```

자세한 내용: [docs/01-infrastructure.md](./docs/01-infrastructure.md)

### 4. Argo CD 설치

```bash
# 리포지토리 클론 (VM 내부)
git clone https://github.com/<your-org>/blogstack-k8s
cd blogstack-k8s

# Argo CD 네임스페이스 생성
kubectl create namespace argocd

# Argo CD 설치
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Pod 준비 대기 (약 2-3분)
kubectl wait --for=condition=available --timeout=300s deployment -n argocd --all

# Root App 배포
kubectl apply -f iac/argocd/root-app.yaml
```

Root App이 모든 하위 애플리케이션을 자동으로 배포합니다.

자세한 내용: [docs/02-argocd-setup.md](./docs/02-argocd-setup.md)

> 빠른 설치 스크립트(`./scripts/bootstrap.sh`)도 제공되지만, 처음 설치하시는 분은 위의 수동 설치를 권장합니다.

### 5. Vault 초기화 및 시크릿 주입

```bash
# Vault Pod이 Running이 될 때까지 대기
kubectl get pods -n vault -w

# Port-forward
kubectl port-forward -n vault svc/vault 8200:8200 &

# 초기화
export VAULT_ADDR=http://127.0.0.1:8200
cd security/vault/init-scripts
./01-init-unseal.sh

# init-output.json을 안전한 곳에 백업!
# Unseal Keys와 Root Token 포함

# 시크릿 입력 (security/vault/secrets-guide.md 참조)
export VAULT_TOKEN=<root-token>

# Ghost 시크릿 (기본 구성 - SMTP 없이)
vault kv put kv/blog/prod/ghost \
  url="https://sunghogigio.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="<password>" \
  database__connection__database="ghost"

# MySQL 시크릿
vault kv put kv/blog/prod/mysql \
  root_password="<mysql-root-pw>" \
  password="<same-as-ghost-db-pw>"

# Cloudflare Tunnel 토큰
vault kv put kv/blog/prod/cloudflared \
  token="<tunnel-token>"
```

선택 기능 활성화 방법은 docs/03-vault-setup.md (선택 기능) 참조

자세한 내용: [docs/03-vault-setup.md](./docs/03-vault-setup.md)

### 6. 확인

```bash
# 헬스 체크
./scripts/health-check.sh

# Argo CD Apps 상태
kubectl get applications -n argocd

# Ghost 접근
# https://sunghogigio.com (공개)
# https://sunghogigio.com/ghost (Zero Trust 인증 필요)
```

## 리포지토리 구조

```
blogstack-k8s/
├── config/                  # 중앙 설정 (퍼블릭)
│   ├── prod.env
│   └── README.md
├── clusters/prod/           # Argo CD 엔트리포인트
│   ├── kustomization.yaml
│   ├── project.yaml
│   ├── apps.yaml            # App-of-Apps
│   └── README.md
├── apps/                    # 애플리케이션 매니페스트
│   ├── ghost/               # Ghost + MySQL
│   ├── ingress-nginx/       # Ingress Controller
│   ├── cloudflared/         # Cloudflare Tunnel
│   └── observers/           # Prometheus + Loki + Blackbox
├── iac/argocd/              # Argo CD 초기 설치
│   └── root-app.yaml
├── security/                # 시크릿 관리
│   ├── vault/               # Vault (Helm + 정책)
│   └── vso/                 # Vault Secrets Operator
├── scripts/                 # 유틸리티 스크립트
│   ├── bootstrap.sh         # (선택) 빠른 설치
│   └── health-check.sh      # 헬스 체크
└── docs/                    # 문서
    ├── 00-prerequisites.md
    ├── 01-infrastructure.md
    ├── 02-argocd-setup.md
    ├── 03-vault-setup.md
    └── 04-operations.md
```

## 운영

### 모니터링

```bash
# Grafana
kubectl port-forward -n observers svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000 (admin / prom-operator)

# Prometheus
kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090
```

### 트러블슈팅

- **Ghost 로그인 루프**: `X-Forwarded-Proto` 헤더 확인
- **Cloudflare Tunnel 끊김**: cloudflared Pod 로그 및 /ready 확인
- **Vault Sealed**: 수동 Unseal 필요
- **VSO Secret 미생성**: VaultAuth 상태 확인

자세한 내용: [docs/04-operations.md](./docs/04-operations.md)

## 추가 문서

- 보안 가이드: [docs/SECURITY.md](./docs/SECURITY.md)
- 환경 구성: [docs/ENVIRONMENTS.md](./docs/ENVIRONMENTS.md)
- CI 파이프라인: [docs/CI.md](./docs/CI.md)

## 주요 기술 스택

| 컴포넌트 | 기술 | 버전 |
|---------|------|------|
| Kubernetes | k3s | 1.28+ |
| GitOps | Argo CD | Latest |
| Secret 관리 | HashiCorp Vault OSS | 1.15+ |
| Secret Operator | Vault Secrets Operator | 0.6+ |
| CMS | Ghost | 5.x |
| Database | MySQL | 8.0 |
| Ingress | ingress-nginx | 4.13+ |
| Tunnel | cloudflared | 2025.10+ |
| Monitoring | kube-prometheus-stack | 79.0+ |
| Logging | Loki + Promtail | 5.39+ |
| Probing | Blackbox Exporter | 8.1+ |

### 개발 환경

```bash
# Kustomize 빌드 테스트
kustomize build apps/ghost/overlays/prod

# Helm values 검증
helm template vault hashicorp/vault -f security/vault/kustomization.yaml

# 문서 린트
markdownlint docs/
```

