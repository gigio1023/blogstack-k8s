# 03. Vault 초기화 및 시크릿 주입

HashiCorp Vault를 초기화하고 VSO를 통해 K8s Secret을 동기화합니다.

## 전제 조건

- 02-argocd-setup.md 완료
- Argo CD가 Vault와 VSO를 배포한 상태
- Vault Pod가 Running (0/1 - 미초기화 상태)
- VaultStaticSecret 리소스 생성됨 (하지만 K8s Secret은 아직 없음)

```bash
# Vault Pod 확인
kubectl get pods -n vault
# vault-0   0/1  Running  (미초기화 상태)

# VaultStaticSecret 리소스 확인
kubectl get vaultstaticsecrets -A
# NAMESPACE     NAME                AGE
# blog          ghost-env           Xm
# blog          mysql-secret        Xm
# cloudflared   cloudflared-token   Xm

# K8s Secret은 아직 없음 (Vault 미초기화로 인해)
kubectl get secrets -n blog
# No resources found in blog namespace.
```

**Vault CLI 설치 (필수)**

```bash
# Vault CLI 버전 확인
vault version

# 설치되지 않았다면 설치 https://developer.hashicorp.com/vault/install#linux 참고하여 설치
```

## Vault 초기화 프로세스

### 1. 작업 디렉토리 확인

모든 명령어는 프로젝트 루트 디렉토리에서 실행합니다:

```bash
cd ~/blogstack-k8s
pwd
# /home/ubuntu/blogstack-k8s 또는 /home/ubuntu/git/blogstack-k8s
```

### 2. Vault Pod에 Port-forward (백그라운드)

```bash
# 백그라운드로 Port-forward 실행
kubectl port-forward -n vault svc/vault 8200:8200 &

# PID 저장 (나중에 종료용)
VAULT_PF_PID=$!
echo "Port-forward PID: $VAULT_PF_PID"

# Vault 연결 대기
sleep 3

# 연결 확인
curl -s http://127.0.0.1:8200/v1/sys/health || echo "Vault 연결 중..."
```

### 3. Vault 초기화 스크립트 실행

```bash
# 환경변수 설정
export VAULT_ADDR=http://127.0.0.1:8200

# 스크립트 실행 (서브셸에서)
cd security/vault/init-scripts
chmod +x 01-init-unseal.sh
./01-init-unseal.sh

# 프로젝트 루트로 복귀
cd ~/blogstack-k8s
```

**출력 내용:**
- `security/vault/init-scripts/init-output.json` 파일 생성
- Unseal Keys 5개 (threshold 3)
- Root Token

**중요**: 
- ⚠️ `init-output.json`을 **안전한 오프라인 저장소에 백업**하세요!
- ⚠️ **Git에 커밋하지 마세요!** (.gitignore에 포함되어 있음)
- 이 파일을 분실하면 Vault를 다시 초기화해야 합니다 (데이터 손실)

### 4. Vault 상태 확인

```bash
# Vault Pod가 Ready 1/1 상태가 되어야 함 (약 10초 소요)
kubectl get pods -n vault
# NAME      READY   STATUS    RESTARTS   AGE
# vault-0   1/1     Running   0          Xm  ← 1/1 Ready 확인!

# Vault 상태 확인 (Unsealed, Initialized: true)
kubectl exec -n vault vault-0 -- vault status
# Initialized: true
# Sealed: false  ← false여야 함!
```

**중요**: vault-0 Pod이 1/1 Ready가 될 때까지 기다리세요. Unsealed 상태가 되어야 다음 단계를 진행할 수 있습니다.

## KV v2 엔진 활성화 (필수)

init 스크립트는 KV v2 엔진을 활성화하지 않으므로 **반드시 수동으로 활성화**해야 합니다.

```bash
# Root Token으로 인증
export VAULT_TOKEN=$(jq -r .root_token security/vault/init-scripts/init-output.json)

# VAULT_ADDR 환경변수 확인
echo $VAULT_ADDR
# http://127.0.0.1:8200

# KV v2 엔진 확인
vault secrets list

# KV v2 엔진 활성화 (필수)
vault secrets enable -path=kv kv-v2

# 확인
vault secrets list | grep "^kv/"
# kv/    kv    n/a    n/a    n/a    kv-v2    ← 이 줄이 보여야 함
```

**문제 발생 시:**
```bash
# "permission denied" 에러: VAULT_TOKEN 재설정
export VAULT_TOKEN=$(jq -r .root_token security/vault/init-scripts/init-output.json)

# "connection refused" 에러: Port-forward 재시작
kill $VAULT_PF_PID
kubectl port-forward -n vault svc/vault 8200:8200 &
VAULT_PF_PID=$!
sleep 3
```

## 정책 생성

```bash
# Ghost 정책
vault policy write ghost security/vault/policies/ghost.hcl

# MySQL 정책
vault policy write mysql security/vault/policies/mysql.hcl

# Cloudflared 정책
vault policy write cloudflared security/vault/policies/cloudflared.hcl

# 정책 확인
vault policy list
vault policy read ghost
```

## Kubernetes Auth 구성

### 1. Kubernetes Auth 이미 활성화됨 (init 스크립트)

확인:

```bash
vault auth list
# kubernetes/ 가 있어야 함
```

### 2. Kubernetes Auth 설정

Vault가 Kubernetes API와 통신하도록 설정:

```bash
# K8s API 서버 정보 (클러스터 내부 주소 사용)
# 중요: Vault Pod는 클러스터 내부에서 실행되므로 kubernetes.default.svc 사용
K8S_HOST="https://kubernetes.default.svc:443"

# ServiceAccount JWT 생성 (Kubernetes 1.24+ 호환)
# Vault Helm chart가 자동으로 'vault' SA를 생성했으므로 해당 SA로 토큰 생성
# 토큰 만료: 8760h = 1년 (보안과 관리 편의성 균형)
TOKEN_REVIEWER_JWT=$(kubectl create token vault -n vault --duration=8760h)

# CA Certificate
K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

# Vault Kubernetes Auth 설정
vault write auth/kubernetes/config \
    token_reviewer_jwt="$TOKEN_REVIEWER_JWT" \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CA_CERT" \
    disable_local_ca_jwt=true

# 설정 확인
vault read auth/kubernetes/config
# kubernetes_host가 https://kubernetes.default.svc:443 이어야 함
```

> **중요**: 
> - `kubernetes_host`는 **반드시** `https://kubernetes.default.svc:443`을 사용해야 합니다
> - `kubectl config view`로 얻는 `127.0.0.1:6443`은 로컬 개발 환경용이며, 클러스터 내부에서는 접근 불가능합니다
> - `disable_local_ca_jwt=true`를 설정하면 Vault가 Pod 내부의 SA 토큰이 아닌 위에서 생성한 장기 토큰을 사용합니다

### 3. Role 생성 (VSO 인증 설정)

실제 VaultAuth 리소스와 일치하도록 역할을 생성합니다:

```bash
# blog 역할 (blog와 vso namespace에서 사용)
# - blog namespace: VaultAuth가 sa=vault-reader, role=blog 사용
# - vso namespace: VaultAuth가 sa=default, role=blog 사용
vault write auth/kubernetes/role/blog \
    bound_service_account_names=vault-reader,default \
    bound_service_account_namespaces=blog,vso \
    policies=ghost,mysql,cloudflared \
    ttl=24h

# cloudflared 역할 (cloudflared namespace에서 사용)
# - cloudflared namespace: VaultAuth가 sa=vault-reader, role=cloudflared 사용
vault write auth/kubernetes/role/cloudflared \
    bound_service_account_names=vault-reader \
    bound_service_account_namespaces=cloudflared \
    policies=cloudflared \
    ttl=24h

# 역할 확인
vault list auth/kubernetes/role
# Keys
# ----
# blog
# cloudflared

# 상세 확인
vault read auth/kubernetes/role/blog
vault read auth/kubernetes/role/cloudflared
```

**역할 설명:**
- `blog` 역할: blog와 vso namespace에서 ghost, mysql, cloudflared 시크릿 접근
- `cloudflared` 역할: cloudflared namespace에서 cloudflared 시크릿 접근
- ServiceAccount: `vault-reader` (blog, cloudflared) + `default` (vso)

## 시크릿 입력

00-prerequisites.md에서 준비한 모든 자격증명을 Vault에 입력합니다.

팁: 각 명령 실행 후 즉시 검증하여 오류를 미리 방지하세요

---

### 1. Ghost 시크릿 입력

**먼저 도메인 확인:**
```bash
# config/prod.env에서 도메인 확인
grep "siteUrl" config/prod.env
# siteUrl=https://yourdomain.com

# 이 값을 Ghost url에 사용해야 함
```

**기본 구성 (SMTP 없이):**
```bash
# ⚠️ 아래 값들을 실제 값으로 변경하세요!
# - yourdomain.com: 실제 도메인
# - YOUR_DB_PASSWORD: 강력한 비밀번호 (최소 16자 권장)

vault kv put kv/blog/prod/ghost \
  url="https://yourdomain.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="YOUR_DB_PASSWORD" \
  database__connection__database="ghost"
```

**필드 설명:**
| 필드 | 값 | 주의사항 |
|------|------|----------|
| `url` | `config/prod.env`의 `siteUrl`과 동일 | **정확히 일치 필수** (https:// 포함) |
| `database__client` | `mysql` | 고정값 |
| `database__connection__host` | `mysql.blog.svc.cluster.local` | 고정값 (K8s 내부 DNS) |
| `database__connection__user` | `ghost` | 고정값 |
| `database__connection__password` | 직접 생성 | 최소 16자 권장, MySQL과 동일해야 함 |
| `database__connection__database` | `ghost` | 고정값 |

**중요:**
- ✅ `url`은 반드시 `config/prod.env`의 `siteUrl`과 **정확히 일치**해야 합니다
- ✅ `database__connection__password`는 다음 단계의 MySQL password와 **동일**해야 합니다
- ℹ️ SMTP를 설정하지 않으면 이메일 발송 기능이 작동하지 않지만, 블로그 게시 및 관리는 정상 작동합니다

입력 확인:
```bash
# Ghost 시크릿 확인
vault kv get kv/blog/prod/ghost

# 예상 출력:
# ====== Data ======
# Key                             Value
# ---                             -----
# url                             https://yourdomain.com
# database__client                mysql
# database__connection__host      mysql.blog.svc.cluster.local
# ...
```

---

### 2. MySQL 시크릿 입력

```bash
# ⚠️ 아래 값들을 실제 값으로 변경하세요!
# - YOUR_ROOT_PASSWORD: MySQL root 비밀번호 (최소 16자 권장)
# - YOUR_DB_PASSWORD: Ghost가 사용할 DB 비밀번호 (위에서 입력한 값과 동일!)

vault kv put kv/blog/prod/mysql \
  root_password="YOUR_ROOT_PASSWORD" \
  user="ghost" \
  password="YOUR_DB_PASSWORD" \
  database="ghost"
```

**필드 설명:**
| 필드 | 값 | 주의사항 |
|------|------|----------|
| `root_password` | 직접 생성 | 최소 16자 권장, root 계정용 |
| `user` | `ghost` | 고정값 |
| `password` | Ghost의 `database__connection__password`와 **동일** | **필수: 정확히 일치해야 함!** |
| `database` | `ghost` | 고정값 |

**필수 확인: 비밀번호 일치**

`password` 필드는 위 Ghost 시크릿의 `database__connection__password`와 **정확히 동일**해야 합니다!

입력 확인:
```bash
# MySQL 시크릿 확인
vault kv get kv/blog/prod/mysql

# 예상 출력:
# ====== Data ======
# Key              Value
# ---              -----
# root_password    (입력한 값)
# user             ghost
# password         (입력한 값)
# database         ghost
```

비밀번호 일치 확인:
```bash
# Ghost DB 비밀번호
vault kv get -field=database__connection__password kv/blog/prod/ghost

# MySQL 비밀번호
vault kv get -field=password kv/blog/prod/mysql

# 두 출력이 동일해야 함!
```

---

### 3. Cloudflare Tunnel 시크릿 입력

```bash
# ⚠️ YOUR_CLOUDFLARE_TUNNEL_TOKEN을 실제 토큰으로 변경하세요!
# 토큰은 00-prerequisites.md에서 Cloudflare Tunnel 생성 시 받은 값입니다

vault kv put kv/blog/prod/cloudflared \
  token="YOUR_CLOUDFLARE_TUNNEL_TOKEN"
```

**토큰 정보:**
- 출처: 00-prerequisites.md의 Cloudflare Tunnel 생성 단계
- 형식: 긴 Base64 인코딩 문자열 (약 200자)
- 예시: `eyJhIjoiYWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3ODkwIiwidCI6Imdi...`

입력 확인:
```bash
# Cloudflare Tunnel 토큰 확인
vault kv get kv/blog/prod/cloudflared

# 예상 출력:
# ===== Data =====
# Key      Value
# ---      -----
# token    eyJhIjoiYWJjZGVm...
```

---

### 모든 시크릿 입력 완료 확인 (기본 구성)

```bash
# 모든 시크릿 경로 확인
vault kv list kv/blog/prod

# 예상 출력:
# Keys
# ----
# cloudflared
# ghost
# mysql
```

각 시크릿 필드 개수 확인:
```bash
echo "=== Vault Secrets Check ==="

echo -n "Ghost fields: "
vault kv get -format=json kv/blog/prod/ghost | jq '.data.data | length'
# 예상: 6 (SMTP 없이)

echo -n "MySQL fields: "
vault kv get -format=json kv/blog/prod/mysql | jq '.data.data | length'
# 예상: 4

echo -n "Cloudflared fields: "
vault kv get -format=json kv/blog/prod/cloudflared | jq '.data.data | length'
# 예상: 1

echo "=== Check Complete ==="
```

## VSO Secret 동기화 확인 (중요!)

시크릿 입력 후 약 10-30초 내에 VSO가 K8s Secret을 자동으로 생성합니다:

```bash
# blog 네임스페이스 Secret 확인
kubectl get secrets -n blog
# NAME           TYPE     DATA   AGE
# ghost-env      Opaque   6      Xs  ← 생성되어야 함!
# mysql-secret   Opaque   4      Xs  ← 생성되어야 함!

# cloudflared 네임스페이스 Secret 확인
kubectl get secrets -n cloudflared
# NAME                TYPE     DATA   AGE
# cloudflared-token   Opaque   1      Xs  ← 생성되어야 함!

# Secret 내용 확인 (base64 디코딩)
kubectl get secret ghost-env -n blog -o jsonpath='{.data.url}' | base64 -d
# https://yourdomain.com (입력한 도메인이 출력되어야 함)

echo ""
kubectl get secret mysql-secret -n blog -o jsonpath='{.data.database}' | base64 -d
# ghost

echo ""
```

**Secret이 생성되지 않는 경우:**

1. **VaultStaticSecret 상태 확인:**
```bash
kubectl describe vaultstaticsecret ghost-env -n blog | tail -20
# Events 섹션에서 에러 확인

# 자주 보이는 에러:
# - "Vault is sealed": Vault가 아직 unsealed 안됨 (vault status 확인)
# - "permission denied": Role 설정 오류 또는 VSO 캐시 문제
# - "invalid role name": Kubernetes Auth 설정 변경 후 VSO 미재시작
# - "invalid path": 시크릿 경로 오류 (kv/blog/prod/ghost 경로 확인)
```

2. **VSO Pod 재시작 (중요!):**

Kubernetes Auth 설정을 변경한 경우 **반드시 VSO Pod을 재시작**해야 합니다:

```bash
# VSO Pod 재시작
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator

# 재시작 확인 (약 20초 소요)
kubectl get pods -n vso
# NAME                                             READY   STATUS    RESTARTS   AGE
# vso-vault-secrets-operator-controller-manager-*  2/2     Running   0          Xs

# Secret 생성 확인 (약 10-30초 후)
kubectl get secrets -n blog
kubectl get secrets -n cloudflared
```

**VSO 재시작이 필요한 이유:**
- VSO는 Vault 연결을 캐시하여 재사용합니다
- Kubernetes Auth 설정(`kubernetes_host`, Role 등)을 변경해도 캐시된 연결은 갱신되지 않습니다
- Pod 재시작 시 새로운 설정으로 Vault에 재연결합니다

3. **VSO 로그 확인:**
```bash
kubectl logs -n vso -l app.kubernetes.io/name=vault-secrets-operator --tail=50
# "permission denied" 또는 "invalid role name" 에러 확인
```

4. **Vault 연결 확인:**
```bash
# VaultAuth 상태
kubectl get vaultauth -A
# 모두 Valid 상태여야 함

kubectl describe vaultauth vault-auth -n blog
# Status가 Valid여야 함
```

## Cloudflare Tunnel 구성

Token을 입력했으면 Cloudflare에서 **Public Hostname** 설정이 필요합니다.

### 중요: Cloudflare Tunnel 설정 종류

Cloudflare Tunnel에는 2가지 라우트 방식이 있습니다:

1. **Hostname Routes** ← **우리가 사용할 방식**
   - Public 또는 Private Hostname으로 라우팅
   - 도메인 이름으로 트래픽 전달
   - HTTP/HTTPS 웹 서비스용
   - 예: `yourdomain.com` → 클러스터 내부 Ingress

2. **CIDR Routes** (Private Networks)
   - IP 주소 범위(CIDR)로 라우팅
   - 사설 네트워크 전체 접근용 (VPN 대체)
   - 모든 프로토콜 지원
   - 예: `10.0.0.0/24` → 사설 네트워크

**Ghost 블로그는 Hostname Routes를 사용합니다.** (도메인으로 접근하는 웹사이트이므로)

> **참고**: Hostname Routes는 현재 베타 기능일 수 있지만 정상적으로 작동합니다.

### 트래픽 흐름 이해

```
외부 사용자
  ↓ HTTPS
Cloudflare CDN
  ↓ Cloudflare Tunnel (암호화)
cloudflared Pod (클러스터 내부)
  ↓ HTTP (내부 통신)
Ingress-NGINX Controller
  ↓ HTTP + X-Forwarded-Proto: https
Ghost Service
```

Cloudflare Tunnel은 **Ingress Controller로 연결**해야 합니다.

### Hostname Routes 설정

1. **Cloudflare Zero Trust 대시보드 접속:**
   - https://one.dash.cloudflare.com/

2. **Tunnel 설정 페이지 이동:**
   - **Networks** → **Tunnels** → `blogstack-tunnel` (터널 이름) 클릭

3. **Published application routes 섹션으로 이동:**
   - 터널 상세 페이지에서 **"Published application routes"** 섹션 찾기
   - **"Add a published application route"** 버튼 클릭

4. **설정 입력:**

| 항목 | 입력 값 | 설명 |
|------|--------|------|
| **Hostname** | `yourdomain.com` | **구매한 도메인 이름 입력**<br>예: `sunghogigio.com`<br>서브도메인 사용 시: `blog.yourdomain.com` |
| **Service** | `http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80` | Ingress Controller 주소<br>**반드시 `http://` 프로토콜 포함!** |

5. **Description** (선택): 간단한 설명 입력 (예: "Blog main site")

6. **Create** 버튼 클릭

**입력 예시:**
```
Hostname: yourdomain.com
Service: http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
Description: Blog main site
```

> **중요:**
> - **Hostname**: 본인이 소유한 도메인을 그대로 입력 (Cloudflare에 등록된 도메인)
> - **Service**: 
>   - **반드시 `http://` 프로토콜 명시!** (`https://` 아님!)
>   - Ingress Controller의 클러스터 내부 DNS 이름 사용
>   - 포트 `80` 사용 (443 아님!)
> - **HTTP를 사용하는 이유:**
>   - 외부 → Cloudflare: HTTPS (Cloudflare가 처리)
>   - Cloudflare → Tunnel → 클러스터: 암호화됨 (Tunnel이 처리)
>   - 클러스터 내부: HTTP (안전한 내부망, 암호화 불필요)
>   - Ingress가 `X-Forwarded-Proto: https` 헤더 추가
>   - Ghost가 올바른 HTTPS 리다이렉트 생성

**Service 이름 확인:**
```bash
kubectl get svc -n ingress-nginx
# NAME                                 TYPE        CLUSTER-IP      PORT(S)
# ingress-nginx-controller             ClusterIP   10.43.x.x       80/TCP,443/TCP
```

### Zero Trust Access 정책

1. Access → Applications → Add an application
2. Application type: Self-hosted
3. Application domain: `sunghogigio.com`
4. Path: `/ghost/*`
5. Policies:
   - Name: `Ghost Admin Only`
   - Action: `Allow`
   - Session duration: `24h`
   - Include:
     - Emails: `<your-email@example.com>`
     - OR IdP Group (Google/GitHub 인증)

## Vault 메트릭 확인

Prometheus가 Vault 메트릭을 수집하는지 확인:

```bash
# ServiceMonitor 확인
kubectl get servicemonitor -n observers vault

# Prometheus Targets (Port-forward 후)
kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090
```

브라우저: `http://localhost:9090/targets`
- `vault/http` 타깃이 UP 상태여야 함

## 트러블슈팅

### Vault Pod이 CrashLoopBackOff

```bash
kubectl logs -n vault vault-0
```

Raft 스토리지 문제일 가능성. PVC 확인:

```bash
kubectl get pvc -n vault
```

### VSO Secret 생성 안됨

1. VaultAuth 상태:
```bash
kubectl describe vaultauth vault-auth -n vso
```

2. VaultConnection 상태:
```bash
kubectl get vaultconnection -n vso
```

3. Vault 주소 확인:
```bash
kubectl get svc -n vault
# vault 서비스가 ClusterIP로 노출되어야 함
```

### Token 만료

VSO의 K8s Auth Token이 만료되면 재생성:

```bash
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
```

## Pod 시작 확인

Secret이 생성되면 Ghost와 MySQL Pod이 자동으로 시작됩니다:

```bash
# Pod 상태 확인 (약 1-2분 소요)
kubectl get pods -n blog

# 예상 출력:
# NAME                     READY   STATUS    RESTARTS   AGE
# ghost-xxxxx-xxxxx        1/1     Running   0          Xm
# mysql-0                  1/1     Running   0          Xm

# cloudflared도 확인
kubectl get pods -n cloudflared
# NAME                     READY   STATUS    RESTARTS   AGE
# cloudflared-xxxxx-xxxxx  1/1     Running   0          Xm

# 전체 Applications 상태 확인
kubectl get applications -n argocd
# 모든 앱이 Synced Healthy여야 함 (약 2-3분 후)
```

**Pod이 시작되지 않는 경우:**

```bash
# Ghost Pod 로그 확인
kubectl logs -n blog -l app=ghost --tail=50

# MySQL Pod 로그 확인
kubectl logs -n blog mysql-0 --tail=50

# 일반적인 문제:
# - "Error: secret not found": Secret이 아직 생성 안됨 (위 VSO 확인 단계)
# - "Access denied for user": MySQL 비밀번호 불일치 (비밀번호 확인)
# - "Invalid url": Ghost url이 잘못됨 (siteUrl과 일치 확인)
```

## 최종 확인

모든 구성 요소가 정상 작동하는지 최종 확인:

```bash
echo "=== Vault 상태 ==="
kubectl get pods -n vault
kubectl exec -n vault vault-0 -- vault status | grep -E "Initialized|Sealed"

echo ""
echo "=== K8s Secrets ==="
kubectl get secrets -n blog | grep -E "ghost-env|mysql-secret"
kubectl get secrets -n cloudflared | grep cloudflared-token

echo ""
echo "=== Applications ==="
kubectl get applications -n argocd | grep -E "ghost|cloudflared|vault"

echo ""
echo "=== Pods ==="
kubectl get pods -n blog
kubectl get pods -n cloudflared

echo ""
echo "=== 완료 ==="
```

**예상 결과:**
- ✅ Vault: Initialized=true, Sealed=false
- ✅ Secrets: ghost-env, mysql-secret, cloudflared-token 생성됨
- ✅ Applications: 모두 Synced Healthy
- ✅ Pods: 모두 1/1 Running

## Port-forward 종료

Vault 설정이 완료되었으므로 Port-forward를 종료할 수 있습니다:

```bash
# Port-forward 프로세스 종료
kill $VAULT_PF_PID 2>/dev/null || pkill -f "port-forward.*vault"

# 확인
ps aux | grep port-forward
```

## 다음 단계

✅ Vault 초기화 완료
✅ 시크릿 입력 완료
✅ VSO가 K8s Secret 생성 완료
✅ Ghost, MySQL, Cloudflared Pod 시작 완료

이제 Cloudflare Tunnel 설정을 완료하고 블로그에 접속할 수 있습니다.

다음: [04-operations.md](./04-operations.md) 또는 아래 Cloudflare Tunnel 구성

---

## 선택 기능

### A. SMTP 이메일 발송 활성화

Ghost에서 이메일을 발송하려면 (비밀번호 재설정, 회원 초대 등):

1. 00-prerequisites.md의 "선택 기능 B" 섹션에 따라 SMTP 서비스 준비
2. Ghost 시크릿에 SMTP 필드 추가:

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

3. Ghost Pod 재시작:
```bash
kubectl rollout restart deployment/ghost -n blog
```

### B. 백업 자동화 활성화

MySQL과 Ghost 컨텐츠를 OCI Object Storage에 자동 백업하려면:

1. 00-prerequisites.md의 "선택 기능 A" 섹션에 따라 OCI Object Storage 준비
2. Vault에 백업 시크릿 입력:

```bash
vault kv put kv/blog/prod/backup \
  AWS_ACCESS_KEY_ID="YOUR_OCI_ACCESS_KEY" \
  AWS_SECRET_ACCESS_KEY="YOUR_OCI_SECRET_KEY" \
  AWS_ENDPOINT_URL_S3="https://YOUR_NAMESPACE.compat.objectstorage.YOUR_REGION.oraclecloud.com" \
  BUCKET_NAME="blog-backups"
```

3. VSO Secret 배포:
```bash
kubectl apply -f /home/ubuntu/git/blogstack-k8s/security/vso/secrets/optional/backup.yaml
```

4. Backup CronJob 배포:
```bash
kustomize build /home/ubuntu/git/blogstack-k8s/apps/ghost/optional | kubectl apply -f -
```

5. 백업 확인:
```bash
# CronJob 확인
kubectl get cronjob -n blog

# 수동 백업 테스트
kubectl create job --from=cronjob/mysql-backup mysql-backup-test -n blog
kubectl logs -f job/mysql-backup-test -n blog
```

자세한 운영 가이드는 apps/ghost/optional/README.md 참조

