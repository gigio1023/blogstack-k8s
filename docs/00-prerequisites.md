# 00. 사전 요구사항

blogstack-k8s를 배포하기 전에 준비해야 할 항목들입니다.

## 하드웨어/인프라

### Oracle Cloud Infrastructure (OCI)

- **VM Shape**: VM.Standard.A1.Flex (ARM64)
- **OCPU**: 4 (권장)
- **메모리**: 24GB (권장)
- **스토리지**: 최소 100GB Boot Volume
- **네트워크**: VCN 및 Public Subnet 구성
- **보안 그룹**: 
  - 인바운드: 필요 없음 (Cloudflare Tunnel 사용)
  - 아웃바운드: 443/tcp (HTTPS) 허용 필수

### OCI Object Storage (백업용)

- S3 호환 API 활성화
- 버킷 생성 (예: `blog-backups`)
- Access Key/Secret Key 생성
- Endpoint URL 확인: `https://<namespace>.compat.objectstorage.<region>.oraclecloud.com`

## 도메인 및 DNS

### 도메인 등록

- 도메인 구매 및 소유권 확인
- 예시: `sunghogigio.com`

### DNS 제공자

- Cloudflare (권장) - Zero Trust 기능 통합
- DNS 레코드는 Cloudflare Tunnel 설정 시 자동/수동 생성

## Cloudflare 계정

### 필수 설정

1. **Cloudflare 계정 생성**
2. **도메인을 Cloudflare에 추가**
   - Nameserver를 Cloudflare로 변경
3. **Zero Trust 계정 활성화**
   - https://one.dash.cloudflare.com/
   - 무료 플랜으로 시작 가능 (50 users까지)

### Cloudflare Tunnel

- Tunnel 생성 및 Token 발급 (설정 시 수행)
- DNS CNAME 레코드: `<domain>` → `<tunnel-id>.cfargotunnel.com`

### Zero Trust Access

- IdP 연동 (Google/GitHub 등)
- Application 생성: `/ghost/*` 경로 보호
- Policies: 인증된 사용자만 허용

## 개발 도구

### 로컬 환경

- **Git**: 2.30+
- **kubectl**: 1.28+
- **kustomize**: 5.0+
- **Helm**: 3.14+ (선택)
- **jq**: JSON 파싱용

### SSH 접근

- OCI VM에 대한 SSH Key 등록
- SSH 접근 확인: `ssh -i <private-key> ubuntu@<vm-ip>`

## 필수 자격증명

준비해야 할 시크릿 목록 (Vault에 저장):

1. **MySQL**
   - Root 비밀번호
   - Ghost 사용자 비밀번호

2. **Ghost**
   - Database 연결 정보 (자동 생성됨)
   - SMTP 자격증명 (이메일 발송용)
     - Mailgun, SendGrid, Gmail 등

3. **Cloudflare Tunnel**
   - Tunnel Token (Tunnel 생성 시 발급)

4. **OCI Object Storage**
   - Access Key ID
   - Secret Access Key
   - Endpoint URL

5. **Vault** (초기화 시 생성)
   - Unseal Keys (5개, threshold 3)
   - Root Token

## 네트워크 요구사항

### 아웃바운드 연결

VM에서 다음 엔드포인트로 HTTPS(443) 연결 필요:

- `github.com` - Git repo clone
- `*.helm.sh`, `*.github.io` - Helm charts
- `registry.k8s.io`, `docker.io`, `ghcr.io` - Container images
- `api.cloudflare.com` - Cloudflare Tunnel
- `*.compat.objectstorage.*.oraclecloud.com` - OCI Object Storage

### 방화벽 규칙

**OCI Security List / Network Security Group:**
- Egress: 0.0.0.0/0 → 443/tcp (HTTPS)
- Ingress: 불필요 (Tunnel 사용)

## 체크리스트

구축 전 확인:

- [ ] OCI VM 생성 완료 (ARM64, 4 OCPU, 24GB)
- [ ] SSH 접근 확인
- [ ] 도메인 구매 및 Cloudflare 등록
- [ ] Cloudflare Zero Trust 계정 활성화
- [ ] OCI Object Storage 버킷 생성
- [ ] S3 호환 API Access Key 발급
- [ ] SMTP 서비스 가입 (Mailgun/SendGrid 등)
- [ ] 로컬 도구 설치 (git, kubectl, kustomize)

다음 단계: [01-infrastructure.md](./01-infrastructure.md)

