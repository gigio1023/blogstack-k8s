# 03. Vault 초기화 및 시크릿 주입

HashiCorp Vault를 초기화하고 VSO를 통해 K8s Secret을 동기화합니다.

## 전제 조건

- Argo CD가 Vault와 VSO를 배포한 상태
- Vault Pod가 Running (아직 Sealed 상태)

```bash
kubectl get pods -n vault
# vault-0   0/1  Running  (ready 0/1 = Sealed 상태)
```

## Vault 초기화 프로세스

### 1. Vault Pod에 Port-forward

```bash
kubectl port-forward -n vault svc/vault 8200:8200
```

### 2. Vault 초기화 스크립트 실행

```bash
cd security/vault/init-scripts
chmod +x 01-init-unseal.sh

# 환경변수 설정
export VAULT_ADDR=http://127.0.0.1:8200

# 초기화 실행
./01-init-unseal.sh
```

**출력 내용:**
- `init-output.json` 파일 생성
- Unseal Keys 5개 (threshold 3)
- Root Token

**중요: `init-output.json`을 안전한 오프라인 저장소에 백업하고 Git에 커밋하지 마세요!**

### 3. Vault 상태 확인

```bash
# Vault Pod가 Ready 1/1 상태가 되어야 함
kubectl get pods -n vault

# Vault 상태 (Unsealed, Initialized: true)
kubectl exec -n vault vault-0 -- vault status
```

## KV v2 엔진 활성화

```bash
# Root Token으로 인증
export VAULT_TOKEN=$(jq -r .root_token security/vault/init-scripts/init-output.json)

# KV v2 엔진 확인 (이미 활성화되어 있을 수 있음)
vault secrets list

# 활성화 (필요시)
vault secrets enable -path=kv kv-v2
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
# K8s API 서버 정보
K8S_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.server}')

# ServiceAccount JWT 생성 (Kubernetes 1.24+ 호환)
# Vault Helm chart가 자동으로 'vault' SA를 생성했으므로 해당 SA로 토큰 생성
TOKEN_REVIEWER_JWT=$(kubectl create token vault -n vault --duration=87600h)

# CA Certificate
K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

# Vault Kubernetes Auth 설정
vault write auth/kubernetes/config \
    token_reviewer_jwt="$TOKEN_REVIEWER_JWT" \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CA_CERT" \
    disable_local_ca_jwt=true
```

> **참고**: `disable_local_ca_jwt=true`를 설정하면 Vault가 Pod 내부의 SA 토큰이 아닌 위에서 생성한 토큰을 사용합니다.

### 3. Role 생성 (네임스페이스/SA별 최소권한)

```bash
# blog 역할 (ns=blog, sa=vault-reader)
vault write auth/kubernetes/role/blog \
    bound_service_account_names=vault-reader \
    bound_service_account_namespaces=blog \
    policies=ghost,mysql \
    ttl=24h

# cloudflared 역할 (ns=cloudflared, sa=vault-reader)
vault write auth/kubernetes/role/cloudflared \
    bound_service_account_names=vault-reader \
    bound_service_account_namespaces=cloudflared \
    policies=cloudflared \
    ttl=24h
```

## 시크릿 입력

00-prerequisites.md에서 준비한 모든 자격증명을 Vault에 입력합니다.

팁: 각 명령 실행 후 즉시 검증하여 오류를 미리 방지하세요

---

### 1. Ghost 시크릿 입력

기본 구성 (SMTP 없이):
```bash
# Vault에 Ghost 시크릿 입력
vault kv put kv/blog/prod/ghost \
  url="https://yourdomain.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="YOUR_DB_PASSWORD" \
  database__connection__database="ghost"
```

필드 설명:
| 필드 | 출처 | 주의사항 |
|------|------|----------|
| `url` | `config/prod.env`의 `siteUrl` | 정확히 일치해야 함 |
| `database__connection__password` | 직접 생성 | 8자 이상 권장 |

중요: `url`은 반드시 `config/prod.env`의 `siteUrl`과 정확히 일치해야 함

참고: SMTP를 설정하지 않으면 이메일 발송 기능이 작동하지 않지만, 블로그 게시 및 관리는 정상 작동합니다.

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
# Vault에 MySQL 시크릿 입력
vault kv put kv/blog/prod/mysql \
  root_password="YOUR_ROOT_PASSWORD" \
  user="ghost" \
  password="YOUR_DB_PASSWORD" \
  database="ghost"
```

필드 설명:
| 필드 | 주의사항 |
|------|----------|
| `root_password` | 직접 생성 (8자 이상 권장) |
| `password` | Ghost의 `database__connection__password`와 동일해야 함 |

필수: `password`는 위 Ghost 시크릿의 `database__connection__password`와 정확히 동일해야 함

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
# Vault에 Cloudflare Tunnel 토큰 입력
vault kv put kv/blog/prod/cloudflared \
  token="YOUR_CLOUDFLARE_TUNNEL_TOKEN"
```

토큰 출처: 00-prerequisites.md의 3.3 단계에서 복사한 Cloudflare Tunnel Token

토큰 형식: 긴 Base64 인코딩 문자열 (약 200자)

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

## VSO Secret 동기화 확인

VSO가 Vault에서 K8s Secret을 생성했는지 확인:

```bash
# blog 네임스페이스
kubectl get secrets -n blog
# 예상: ghost-env, mysql-secret, backup-s3

# cloudflared 네임스페이스
kubectl get secrets -n cloudflared
# 예상: cloudflared-token

# Secret 내용 확인 (base64 디코딩)
kubectl get secret ghost-env -n blog -o jsonpath='{.data.url}' | base64 -d
```

### VSO 로그 확인 (문제 발생 시)

```bash
kubectl logs -n vso -l app.kubernetes.io/name=vault-secrets-operator
```

## Cloudflare Tunnel 구성

Token을 입력했으면 Cloudflare에서 Public Hostname 설정:

### 중요: 트래픽 흐름 이해

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

### Public Hostname 설정

1. Cloudflare Zero Trust 대시보드: https://one.dash.cloudflare.com/
2. Networks → Tunnels → `blogstack` → Configure
3. **Public Hostnames** → Add a public hostname:

| 항목 | 값 | 설명 |
|------|-----|------|
| Subdomain | (비워둠) | Apex 도메인 사용 |
| Domain | `yourdomain.com` | 실제 도메인 입력 |
| Path | (비워둠) | 모든 경로 |
| Service Type | **HTTP** | 클러스터 내부는 HTTP |
| URL | `ingress-nginx-controller.ingress-nginx.svc.cluster.local:80` | Ingress Controller (Service:Port) |

> **왜 Ghost Service가 아닌 Ingress로?**
> - Ingress가 `X-Forwarded-Proto: https` 헤더를 추가해야 Ghost가 올바른 리다이렉트를 생성합니다.
> - Ghost 설정(`url=https://...`)과 실제 프로토콜을 맞춰주는 역할입니다.
> 
> **참고**: Service 이름은 `kubectl get svc -n ingress-nginx`로 확인 가능합니다.

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

## 다음 단계

Vault와 VSO 구성이 완료되었습니다. 이제 Ghost가 자동으로 시크릿을 받아 시작됩니다.

다음: [04-operations.md](./04-operations.md)

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

