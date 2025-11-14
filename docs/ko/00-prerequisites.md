# 00. 사전 요구사항

blogstack-k8s 배포 전 준비사항

## 1. 하드웨어/인프라

### OCI VM 스펙
- VM Shape: VM.Standard.A1.Flex (ARM64)
- OCPU: 4
- 메모리: 24GB
- 스토리지: 100GB Boot Volume
- OS: Ubuntu 22.04 LTS (ARM64)

### 네트워크 설정

VCN Security List:

| 방향 | CIDR | 프로토콜/포트 | 설명 |
|------|------|---------------|------|
| Egress | 0.0.0.0/0 | TCP/443 | 필수: GitHub, Docker Hub, Helm |
| Egress | 0.0.0.0/0 | TCP/80 | 선택: 패키지 업데이트 |
| Ingress | - | - | 불필요 (Cloudflare Tunnel 사용) |

Ingress 규칙은 SSH(22)를 제외하고 닫아야 함

### VM 접속 확인

```bash
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>

uname -m  # aarch64 확인
df -h     # 최소 50GB 여유 필요
```

## 2. Cloudflare 계정 설정

### 2.1. 계정 생성 및 도메인 준비

1. https://dash.cloudflare.com/sign-up 에서 계정 생성
2. 도메인 준비

방법 A: Cloudflare Registrar에서 직접 구매 (권장)
- Domain Registration → Register Domains
- 자동 DNS 설정, 저렴한 갱신 비용

방법 B: 타 registrar 도메인 추가
- Add a Site → 도메인 입력
- Plan: Free
- Nameserver를 Cloudflare로 변경 (도메인 등록업체에서)

```bash
# Nameserver 변경 확인 (최대 24시간 소요)
dig NS yourdomain.com +short
# 출력: chad.ns.cloudflare.com, dina.ns.cloudflare.com
```

### 2.2. Cloudflare Zero Trust 활성화

1. https://one.dash.cloudflare.com/ 접속
2. Team name 입력
3. Plan: Free (50 users)

### 2.3. Cloudflare Tunnel 생성

1. Zero Trust: Networks → Tunnels → Create a tunnel
2. Type: Cloudflared
3. Name: `blogstack-tunnel`
4. Token 복사 (Base64 문자열, 약 200자)
5. Connector 설치 단계 Skip (Kubernetes에서 자동 실행)

Public Hostname 설정은 05-cloudflare-setup.md에서 진행

### 2.4. Zero Trust Access 정책 (선택)

Ghost Admin (`/ghost/*`)를 보호하려면:

1. Settings → Authentication → Google/GitHub 연동
2. Access → Applications → Add
   - Type: Self-hosted
   - Name: `Ghost Admin`
   - Domain: `yourdomain.com`
   - Path: `/ghost/*`
3. Policy:
   - Name: `Admin Only`
   - Action: Allow
   - Include: Emails

## 3. 개발 도구

### VM 내부

```bash
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>

sudo apt update
sudo apt install -y curl git jq

git --version  # 2.30+
# kubectl은 k3s 설치 시 자동 제공
```

### 로컬 (선택)

```bash
# macOS
brew install kubectl kustomize

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

## 4. 필수 자격증명

| 항목 | 내용 | 비고 |
|------|------|------|
| Cloudflare | Tunnel Token | Base64 문자열 (약 200자) |
| MySQL | Root Password | 직접 생성 (8자 이상) |
| | Ghost Password | 직접 생성 (8자 이상) |
| Ghost | URL | `https://yourdomain.com` |
| Mailgun | SMTP Host | `smtp.mailgun.org` |
| | SMTP Username | `postmaster@mg.yourdomain.com` |
| | SMTP Password | Mailgun에서 생성 |
| | 발신 이메일 | `noreply@yourdomain.com` |

## 5. 네트워크 요구사항 확인

```bash
# GitHub, Docker Hub, Cloudflare API 접근 확인
curl -I https://github.com
curl -I https://registry.hub.docker.com
curl -I https://api.cloudflare.com
# 예상 출력: HTTP/2 200 또는 3xx
```

OCI Security List: Egress `0.0.0.0/0:443` 허용 필요

## 6. SMTP 이메일 설정 (필수)

Ghost 비밀번호 재설정 및 로그인 기능 필수

### Mailgun 가입 및 설정

#### Step 1: 가입

1. https://signup.mailgun.com/ 접속
2. Sign up for free
3. 이메일 인증

무료 플랜: 월 5,000통

#### Step 2: Sending Domain 추가

1. Mailgun: Sending → Domains → Add New Domain
2. Domain name: `mg.yourdomain.com` (서브도메인 권장)

#### Step 3: DNS 레코드 추가 (Cloudflare)

Cloudflare: DNS → Records → Mailgun 제공 레코드 추가

| Type | Name | Value | Proxy Status |
|------|------|-------|--------------|
| TXT | `mg` | `v=spf1 include:mailgun.org ~all` | DNS only |
| TXT | `k1._domainkey.mg` | Mailgun 제공 DKIM | DNS only |
| CNAME | `email.mg` | `mailgun.org` | DNS only |
| MX | `mg` | `mxa.mailgun.org` (Priority: 10) | DNS only |
| MX | `mg` | `mxb.mailgun.org` (Priority: 10) | DNS only |

중요: Proxy Status는 반드시 DNS only (회색)

#### Step 4: Domain Verification

Mailgun 대시보드에서 Status: Verified 확인 (최대 48시간, 보통 10분)

#### Step 5: SMTP 자격증명

Mailgun: Sending → Domain settings → SMTP Credentials

- Host: `smtp.mailgun.org`
- Port: `587`
- Username: `postmaster@mg.yourdomain.com`
- Password: Mailgun 자동 생성

이 정보를 저장 (07-smtp-setup.md에서 사용)

## 7. 최종 체크리스트

### 인프라
- [ ] OCI VM 생성 (ARM64, Ubuntu 22.04, 4 OCPU, 24GB RAM, 100GB 디스크)
- [ ] SSH 접근 가능
- [ ] VM Egress 443/tcp 허용

### 외부 서비스
- [ ] 도메인 준비
- [ ] Cloudflare 계정 생성
- [ ] 도메인 Cloudflare DNS 설정 (`dig NS` 확인)
- [ ] Cloudflare Zero Trust 활성화
- [ ] Cloudflare Tunnel 생성 및 Token 복사
- [ ] Mailgun 계정 생성 및 도메인 인증
- [ ] Mailgun DNS 레코드 Cloudflare 추가

### 자격증명
- [ ] MySQL 비밀번호 2개 생성 (Root, Ghost)
- [ ] Mailgun SMTP 자격증명 확인
- [ ] 모든 자격증명을 안전한 곳에 저장

### 도구
- [ ] VM에 Git 설치 확인
- [ ] (선택) 로컬에 kubectl, kustomize 설치

## 다음 단계

→ [CUSTOMIZATION.md](./CUSTOMIZATION.md) - Git URL 및 도메인 설정

→ [01-infrastructure.md](./01-infrastructure.md) - k3s 설치

## 선택 기능

### 백업 (OCI Object Storage)

MySQL/Ghost 자동 백업

1. OCI: Storage → Buckets → Create Bucket
   - Name: `blog-backups`
   - Tier: Standard
2. Customer Secret Keys 생성 (S3 API)
3. Endpoint URL 확인: `https://<namespace>.compat.objectstorage.<region>.oraclecloud.com`
4. `apps/ghost/optional/README.md` 참조
