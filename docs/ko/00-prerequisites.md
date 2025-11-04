# 00. 사전 요구사항

blogstack-k8s를 배포하기 전에 준비해야 할 항목들과 설정 방법입니다.

---

## 1. 하드웨어/인프라

### Oracle Cloud Infrastructure (OCI) VM

필요한 스펙:
- VM Shape: VM.Standard.A1.Flex (ARM64)
- OCPU: 4 (권장)
- 메모리: 24GB (권장)
- 스토리지: 최소 100GB Boot Volume
- OS: Ubuntu 22.04 LTS (ARM64)

### 네트워크 설정

VCN Security List 설정:

| 방향 | CIDR | 프로토콜/포트 | 설명 |
|------|------|---------------|------|
| Egress | 0.0.0.0/0 | TCP/443 | 필수: GitHub, Docker Hub, Helm 접근 |
| Egress | 0.0.0.0/0 | TCP/80 | 선택: 패키지 업데이트 |
| Ingress | - | - | 불필요 (Cloudflare Tunnel 사용) |

참고: Ingress 규칙은 SSH(22)를 제외하고 모두 닫아야 함. 블로그 접근은 Cloudflare Tunnel을 통해서만 이루어짐.

### VM 생성 확인

```bash
# SSH 접속 확인
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>

# 시스템 정보 확인
uname -m  # 출력: aarch64 (ARM64 확인)
cat /etc/os-release  # Ubuntu 버전 확인
df -h  # 디스크 용량 확인 (최소 50GB 여유 필요)
```

---

## 2. Cloudflare 계정 설정

### 2.1. Cloudflare 계정 생성 및 도메인 준비

#### Step 1: Cloudflare 가입
1. https://dash.cloudflare.com/sign-up 에서 계정 생성
2. 이메일 인증 완료

#### Step 2: 도메인 구매 및 추가

**방법 A: Cloudflare Registrar 사용 (권장)**

Cloudflare에서 직접 도메인 구매 시 별도 설정 불필요:

1. Cloudflare 대시보드: **Domain Registration** → **Register Domains**
2. 원하는 도메인 검색 후 구매
3. 자동으로 Cloudflare DNS 설정 완료 (Nameserver 변경 불필요)

장점:
- Nameserver 설정 자동 완료
- 도메인 갱신 비용 저렴 (원가 제공)
- Cloudflare와 완전 통합

**방법 B: 기존 도메인 추가 (타 registrar 구매)**

다른 곳(GoDaddy, Namecheap 등)에서 구매한 도메인을 Cloudflare에 추가:

1. Cloudflare 대시보드: **Add a Site** 클릭
2. 도메인 입력: `yourdomain.com`
3. Plan 선택: **Free**
4. DNS 레코드 스캔 → **Continue**
5. Cloudflare가 제공하는 Nameserver 2개를 도메인 등록업체에서 변경:

```
nameserver1: chad.ns.cloudflare.com
nameserver2: dina.ns.cloudflare.com
```

등록업체별 Nameserver 변경 방법:
- GoDaddy: DNS Management → Nameservers → Change
- Namecheap: Domain List → Manage → Custom DNS
- 기타: 등록업체 DNS 설정에서 "Custom Nameservers" 검색

Nameserver 변경 확인 (전파에 최대 24시간 소요):
```bash
dig NS yourdomain.com +short

# 예상 출력:
# chad.ns.cloudflare.com
# dina.ns.cloudflare.com
```

---

### 2.2. Cloudflare Zero Trust 활성화

#### Step 1: Zero Trust 대시보드 접속
1. https://one.dash.cloudflare.com/ 접속
2. Cloudflare 계정으로 로그인

#### Step 2: Team Domain 생성
- Team name 입력: `myblog-team` (원하는 이름)
- Plan 선택: **Free** (50 users까지)
- **Continue to dashboard** 클릭

---

### 2.3. Cloudflare Tunnel 생성

#### Step 1: Tunnel 페이지 이동
1. Zero Trust 대시보드: https://one.dash.cloudflare.com/
2. 왼쪽 메뉴: **Networks** → **Tunnels**
3. **Create a tunnel** 클릭

#### Step 2: Tunnel Type 선택
- **Cloudflared** 선택 (권장)
- **Next** 클릭

#### Step 3: Tunnel 이름 입력
- Name: `blogstack-tunnel`
- **Save tunnel** 클릭

#### Step 4: Token 복사
화면에 표시되는 Token을 복사하여 안전하게 저장

Token 형식: 긴 Base64 인코딩 문자열 (약 200자 이상)

Connector 설치 단계는 Skip (Kubernetes에서 cloudflared Pod가 자동으로 실행)

#### Step 5: Public Hostname 설정 (나중에 수행)
이 단계는 03-vault-setup.md에서 Vault 시크릿 입력 후 수행

---

### 2.4. Zero Trust Access 정책 (선택)

Ghost Admin 페이지(`/ghost/*`)를 보호하려면:

#### Step 1: IdP 연동 (Google/GitHub)
1. Settings → Authentication → Login methods
2. Add new 클릭
3. Google 또는 GitHub 선택
4. OAuth 앱 생성 및 연동

#### Step 2: Application 생성
1. Access → Applications → Add an application
2. Application type: Self-hosted
3. Application name: `Ghost Admin`
4. Application domain: `yourdomain.com`
5. Path: `/ghost/*`
6. Next 클릭

#### Step 3: Policy 설정
| 설정 | 값 |
|------|-----|
| Policy name | `Admin Only` |
| Action | `Allow` |
| Session duration | `24 hours` |
| Include | Emails: `your-email@gmail.com` |

Add application 클릭

참고: 이 설정을 하면 `/ghost/*` 접근 시 Google/GitHub 로그인이 필요

---

## 3. 개발 도구 (VM 내부)

### VM에서 필요한 도구

```bash
# VM에 SSH 접속 후
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>

# 기본 도구 확인/설치
sudo apt update
sudo apt install -y curl git jq

# Git 버전 확인
git --version  # 2.30+ 필요

# kubectl은 k3s 설치 시 자동 제공됨
```

### 로컬 개발 도구 (선택)

로컬에서 클러스터를 관리하려면:

```bash
# macOS
brew install kubectl kustomize

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# 버전 확인
kubectl version --client  # 1.28+
kustomize version  # 5.0+
```

---

## 4. 필수 자격증명 정리

배포 전에 다음 정보를 모두 준비:

| 항목 | 내용 | 비고 |
|------|------|------|
| Cloudflare | Tunnel Token | Base64 문자열 (약 200자) |
| MySQL | Root Password | 직접 생성 (8자 이상) |
| | Ghost Password | 직접 생성 (8자 이상) |
| Ghost | URL | `https://yourdomain.com` |

팁: 이 정보를 안전한 비밀번호 관리자(1Password, Bitwarden 등)에 저장

---

## 5. 네트워크 요구사항 확인

### VM에서 외부 접근 테스트

```bash
# GitHub 접근 테스트
curl -I https://github.com

# Docker Hub 접근 테스트
curl -I https://registry.hub.docker.com

# Cloudflare API 접근 테스트
curl -I https://api.cloudflare.com

# 예상 출력: HTTP/2 200 또는 3xx
```

### OCI Security List 확인

```bash
# OCI CLI 설치된 경우
oci network security-list list --compartment-id <COMPARTMENT_ID>

# 또는 OCI 콘솔에서:
# Networking → Virtual Cloud Networks → [VCN 이름] → Security Lists
```

Egress Rules에 다음이 있어야 함:
- Destination: `0.0.0.0/0`, Protocol: `TCP`, Port: `443`

---

## 6. 최종 체크리스트

배포 시작 전 확인사항:

### 인프라
- [ ] OCI VM 생성 완료 (ARM64, Ubuntu 22.04, 4 OCPU, 24GB RAM, 100GB 디스크)
- [ ] SSH 접근 가능 (`ssh -i ~/.ssh/oci_key ubuntu@<VM_IP>`)
- [ ] VM 아웃바운드 443/tcp 허용 (Security List)

### 외부 서비스
- [ ] 도메인 준비 완료 (Cloudflare Registrar 권장)
- [ ] Cloudflare 계정 생성
- [ ] 도메인이 Cloudflare DNS로 설정됨 확인 (`dig NS yourdomain.com` 확인)
- [ ] Cloudflare Zero Trust 계정 활성화
- [ ] Cloudflare Tunnel 생성 및 Token 복사

### 자격증명 준비
- [ ] MySQL 비밀번호 2개 생성 (Root, Ghost)
- [ ] 모든 자격증명을 안전한 곳에 저장

### 도구
- [ ] VM에 Git 설치 확인
- [ ] (선택) 로컬에 kubectl, kustomize 설치

---

## 다음 단계

모든 체크리스트가 완료되었으면:

→ [CUSTOMIZATION.md](./CUSTOMIZATION.md) - Git URL 및 도메인 설정 (5분)

→ [01-infrastructure.md](./01-infrastructure.md) - k3s 설치 (5분)

---

## 선택 기능

기본 블로그 기능 외에 추가 기능이 필요하면 설정:

### A. 백업 (OCI Object Storage)

MySQL 데이터베이스와 Ghost 컨텐츠를 자동 백업하려면:

#### A.1. OCI 콘솔 접속
1. https://cloud.oracle.com/ 로그인
2. 왼쪽 메뉴: Storage → Buckets
3. Create Bucket 클릭

#### A.2. 버킷 정보 입력

| 항목 | 값 | 설명 |
|------|-----|------|
| Bucket Name | `blog-backups` | 원하는 이름 입력 |
| Default Storage Tier | Standard | 빠른 접근 |
| Encryption | Oracle Managed Keys | 기본값 |

Create 클릭하여 생성

#### A.3. S3 호환 API Access Key 생성
1. OCI 콘솔 우상단: 프로필 아이콘 → User Settings
2. 왼쪽 메뉴: Customer Secret Keys
3. Generate Secret Key 클릭
4. Name 입력: `blogstack-s3-key`
5. Generate Secret Key → 즉시 복사 (다시 볼 수 없음)

생성 결과:
```bash
Access Key: (32자 영숫자 문자열)
Secret Key: (40자 영숫자 문자열)
```

#### A.4. Endpoint URL 확인

S3 API Endpoint URL 형식:
```
https://<namespace>.compat.objectstorage.<region>.oraclecloud.com
```

Namespace 확인 방법:
```bash
# OCI CLI 설치된 경우
oci os ns get

# 또는 OCI 콘솔에서:
# 버킷 상세 → "Namespace" 항목 확인
```

예시:
- Namespace: `your-namespace`
- Region: `ap-seoul-1`
- Endpoint: `https://your-namespace.compat.objectstorage.ap-seoul-1.oraclecloud.com`

#### A.5. 백업 활성화 방법

자세한 내용은 `apps/ghost/optional/README.md` 참조

---

### B. 이메일 발송 (SMTP)

Ghost에서 비밀번호 재설정, 새 글 알림 등을 발송하려면:

#### B.1. Mailgun 가입 (권장)

**Step 1: Mailgun 가입**
1. https://signup.mailgun.com/ 접속
2. Sign up for free 클릭
3. 계정 정보 입력 및 이메일 인증

**Step 2: Sending Domain 추가**
1. Mailgun 대시보드: Sending → Domains
2. Add New Domain 클릭
3. Domain name 입력: `mg.yourdomain.com` (서브도메인 권장)
4. Add Domain 클릭

**Step 3: DNS 레코드 추가 (Cloudflare에서)**
Mailgun이 제공하는 DNS 레코드를 Cloudflare에 추가:

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| TXT | `mg` | `v=spf1 include:mailgun.org ~all` | DNS only |
| TXT | `k1._domainkey.mg` | `k=rsa; p=MIGfMA0...` (Mailgun 제공) | DNS only |
| CNAME | `email.mg` | `mailgun.org` | DNS only |
| MX | `mg` | `mxa.mailgun.org` (Priority: 10) | DNS only |
| MX | `mg` | `mxb.mailgun.org` (Priority: 10) | DNS only |

**Step 4: SMTP 자격증명 확인**
1. Mailgun 대시보드: Sending → Domain settings → `mg.yourdomain.com` 선택
2. SMTP credentials 섹션에서 확인:

```bash
SMTP Host: smtp.mailgun.org
SMTP Port: 587
Username: postmaster@mg.yourdomain.com
Password: (Mailgun에서 생성한 비밀번호)
```

**Step 5: Ghost에 SMTP 설정 추가**

03-vault-setup.md의 Ghost 시크릿에 SMTP 필드 추가:
```bash
vault kv put kv/blog/prod/ghost \
  url="https://yourdomain.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="YOUR_DB_PASSWORD" \
  database__connection__database="ghost" \
  mail__transport="SMTP" \
  mail__options__service="Mailgun" \
  mail__options__host="smtp.mailgun.org" \
  mail__options__port="587" \
  mail__options__auth__user="postmaster@mg.yourdomain.com" \
  mail__options__auth__pass="YOUR_SMTP_PASSWORD"
```

#### B.2. SendGrid (대안)

1. https://signup.sendgrid.com/ 가입
2. Sender Authentication 설정
3. API Key 생성
4. SMTP 자격증명:
   - Host: `smtp.sendgrid.net`
   - Port: `587`
   - Username: `apikey`
   - Password: (생성한 API Key)

#### B.3. Gmail (테스트용만)

참고: Gmail은 일일 발송 제한(500통)이 있어 프로덕션에 부적합

1. Gmail 계정에서 2단계 인증 활성화
2. 앱 비밀번호 생성: https://myaccount.google.com/apppasswords
3. SMTP 자격증명:
   - Host: `smtp.gmail.com`
   - Port: `587`
   - Username: `your-email@gmail.com`
   - Password: (앱 비밀번호 16자리)

---

참고: SMTP를 설정하지 않으면 Ghost의 이메일 발송 기능이 작동하지 않지만, 블로그 게시 및 관리는 정상적으로 작동합니다.
