# blogstack-k8s

Self-hosted Ghost 블로그를 위한 **프로덕션 ready GitOps 모노레포**

Oracle Cloud ARM64 VM + k3s + Argo CD + Vault + Cloudflare Tunnel

## 주요 특징

- **GitOps**: Argo CD로 선언적 배포 및 자동 동기화
- **Self-hosted Secret 관리**: HashiCorp Vault + VSO로 시크릿 중앙화
- **Cloudflare Tunnel**: 공인 포트 개방 없이 HTTPS 노출 + Zero Trust Access
- **관측 우선**: Prometheus + Grafana + Loki + Blackbox로 전방위 모니터링
- **자동 백업**: MySQL → OCI Object Storage (S3 API)
- **ARM64 최적화**: Oracle Cloud A1.Flex 인스턴스 지원

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
│  │  │  cloudflared│  │ingress-nginx│  │   Ghost   │    │  │
│  │  │  (Tunnel)   │─>│(Controller) │─>│  + MySQL  │    │  │
│  │  └─────────────┘  └───────────┘  └────────────┘    │  │
│  │                                         │            │  │
│  │                                         ▼            │  │
│  │                                    ┌────────────┐   │  │
│  │                                    │ Local PVC  │   │  │
│  │                                    │(Local Path)│   │  │
│  │                                    └────────────┘   │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌───────────────────────────────────────────────────┐     │
│  │      Backup CronJob (매일 03:00)                  │     │
│  │   mysqldump → OCI Object Storage (S3 API)         │     │
│  └───────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## 빠른 시작

> **중요**: 이 문서의 예시에서 `sunghogigio.com`은 참조용입니다. 실제 구축 시 `config/prod.env` 파일에서 본인의 도메인으로 변경하세요.

커스터마이징 방법은 `docs/CUSTOMIZATION.md`를 참고하세요.

### 1. 사전 요구사항

- Oracle Cloud VM.Standard.A1.Flex (ARM64, 4 OCPU, 24GB)
- 도메인 (Cloudflare 등록)
- Cloudflare Zero Trust 계정
- OCI Object Storage 버킷 (백업용)
- SMTP 서비스 (Mailgun, SendGrid 등)

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

### 4. 부트스트랩 실행

```bash
# 리포지토리 클론 (VM 내부)
git clone https://github.com/<your-org>/blogstack-k8s
cd blogstack-k8s

# 부트스트랩 스크립트 실행
./scripts/bootstrap.sh
```

스크립트가 자동으로:
- Argo CD 설치
- Root App 배포
- 자식 App들 동기화 시작

자세한 내용: [docs/02-argocd-setup.md](./docs/02-argocd-setup.md)

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

# Ghost 시크릿
vault kv put kv/blog/prod/ghost \
  url="https://sunghogigio.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="<password>" \
  database__connection__database="ghost" \
  mail__transport="SMTP" \
  mail__options__auth__user="<smtp-user>" \
  mail__options__auth__pass="<smtp-pass>"

# MySQL 시크릿
vault kv put kv/blog/prod/mysql \
  root_password="<mysql-root-pw>" \
  password="<same-as-ghost-db-pw>"

# Cloudflare Tunnel 토큰
vault kv put kv/blog/prod/cloudflared \
  token="<tunnel-token>"

# 백업 S3 credentials
vault kv put kv/blog/prod/backup \
  AWS_ACCESS_KEY_ID="<oci-key>" \
  AWS_SECRET_ACCESS_KEY="<oci-secret>" \
  AWS_ENDPOINT_URL_S3="https://<ns>.compat.objectstorage.<region>.oraclecloud.com"
```

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
├── scripts/                 # 자동화 스크립트
│   ├── bootstrap.sh
│   └── health-check.sh
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

### 백업 확인

```bash
# 백업 CronJob 상태
kubectl get cronjob -n blog mysql-backup

# 최근 Job 실행
kubectl get jobs -n blog

# OCI Object Storage 확인
aws s3 ls s3://blog-backups/mysql/ --endpoint-url <endpoint>
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

