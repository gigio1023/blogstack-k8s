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

```bash
# K8s API 서버 정보
K8S_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.server}')

# ServiceAccount JWT
TOKEN_REVIEWER_JWT=$(kubectl get secret -n vault $(kubectl get sa -n vault vault -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 -d)

# CA Certificate
K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

# Vault Kubernetes Auth 설정
vault write auth/kubernetes/config \
    token_reviewer_jwt="$TOKEN_REVIEWER_JWT" \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CA_CERT"
```

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

`security/vault/secrets-guide.md`를 참조하여 필요한 시크릿을 입력합니다.

### 1. Ghost

```bash
vault kv put kv/blog/prod/ghost \
  url="https://sunghogigio.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="<YOUR_SECURE_PASSWORD>" \
  database__connection__database="ghost" \
  mail__transport="SMTP" \
  mail__options__service="Mailgun" \
  mail__options__host="smtp.mailgun.org" \
  mail__options__port="587" \
  mail__options__auth__user="<YOUR_SMTP_USER>" \
  mail__options__auth__pass="<YOUR_SMTP_PASSWORD>"
```

### 2. MySQL

```bash
vault kv put kv/blog/prod/mysql \
  root_password="<YOUR_MYSQL_ROOT_PASSWORD>" \
  user="ghost" \
  password="<YOUR_MYSQL_GHOST_PASSWORD>" \
  database="ghost"
```

**중요: `database__connection__password`와 `password`는 동일한 값이어야 합니다!**

### 3. Cloudflare Tunnel

먼저 Cloudflare에서 Tunnel 생성:

1. https://one.dash.cloudflare.com/ 접속
2. Networks → Tunnels → Create a tunnel
3. Connector: Cloudflared
4. Tunnel 이름: `blogstack`
5. Token 복사

```bash
vault kv put kv/blog/prod/cloudflared \
  token="<CLOUDFLARE_TUNNEL_TOKEN>"
```

### 4. Backup (OCI S3)

```bash
vault kv put kv/blog/prod/backup \
  AWS_ACCESS_KEY_ID="<OCI_ACCESS_KEY>" \
  AWS_SECRET_ACCESS_KEY="<OCI_SECRET_KEY>" \
  AWS_ENDPOINT_URL_S3="https://<namespace>.compat.objectstorage.<region>.oraclecloud.com"
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

1. Tunnel → `blogstack` → Configure
2. Public Hostnames → Add a public hostname:
   - Subdomain: (비워두거나 www)
   - Domain: `sunghogigio.com`
   - Service Type: `HTTP`
   - URL: `http://ghost.blog.svc.cluster.local`

3. `/ghost` 경로 추가:
   - Path: `/ghost/*`
   - Service: `http://ghost.blog.svc.cluster.local`

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

