# 03. Vault 초기화 및 시크릿 주입

## 전제 조건

- 02-argocd-setup.md 완료
- Vault Pod Running (0/1 미초기화 상태)
- Vault CLI 설치 필수

## Vault 초기화

### Port-forward

```bash
cd ~/blogstack-k8s
kubectl port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR=http://127.0.0.1:8200
```

### 초기화 실행

```bash
cd security/vault/init-scripts
chmod +x 01-init-unseal.sh
./01-init-unseal.sh
cd ~/blogstack-k8s
```

중요: init-output.json 백업 후 Git에 커밋 금지

### 상태 확인

```bash
kubectl get pods -n vault  # 1/1 Ready 확인
kubectl exec -n vault vault-0 -- vault status  # Sealed: false
```

## KV v2 엔진 활성화

```bash
export VAULT_TOKEN=$(jq -r .root_token security/vault/init-scripts/init-output.json)
vault secrets enable -path=kv kv-v2
vault secrets list | grep "^kv/"
```

## 정책 생성

```bash
vault policy write ghost security/vault/policies/ghost.hcl
vault policy write mysql security/vault/policies/mysql.hcl
vault policy write cloudflared security/vault/policies/cloudflared.hcl
```

## Kubernetes Auth 구성

```bash
# 설정
K8S_HOST="https://kubernetes.default.svc:443"
TOKEN_REVIEWER_JWT=$(kubectl create token vault -n vault --duration=8760h)
K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

vault write auth/kubernetes/config \
    token_reviewer_jwt="$TOKEN_REVIEWER_JWT" \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CA_CERT" \
    disable_local_ca_jwt=true

# Role 생성
vault write auth/kubernetes/role/blog \
    bound_service_account_names=vault-reader,default \
    bound_service_account_namespaces=blog,vso \
    policies=ghost,mysql,cloudflared \
    ttl=24h

vault write auth/kubernetes/role/cloudflared \
    bound_service_account_names=vault-reader \
    bound_service_account_namespaces=cloudflared \
    policies=cloudflared \
    ttl=24h
```

## 시크릿 입력

### Ghost

```bash
# config/prod.env의 siteUrl 확인
grep "siteUrl" config/prod.env

vault kv put kv/blog/prod/ghost \
  url="https://yourdomain.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="YOUR_DB_PASSWORD" \
  database__connection__database="ghost"
```

### MySQL

```bash
vault kv put kv/blog/prod/mysql \
  root_password="YOUR_ROOT_PASSWORD" \
  user="ghost" \
  password="YOUR_DB_PASSWORD" \
  database="ghost"
```

중요: Ghost와 MySQL의 password 동일해야 함

### Cloudflared

```bash
vault kv put kv/blog/prod/cloudflared \
  token="YOUR_CLOUDFLARE_TUNNEL_TOKEN"
```

### 확인

```bash
vault kv list kv/blog/prod  # cloudflared, ghost, mysql
```

## VSO Secret 동기화 확인

```bash
# 10-30초 후 Secret 생성됨
kubectl get secrets -n blog  # ghost-env, mysql-secret
kubectl get secrets -n cloudflared  # cloudflared-token

# 생성 안되면 VSO 재시작
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
kubectl get secrets -n blog  # 30초 후 재확인
```

## 선택 기능

### SMTP 이메일

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

kubectl rollout restart deployment/ghost -n blog
```

### OCI 백업

```bash
vault kv put kv/blog/prod/backup \
  AWS_ACCESS_KEY_ID="YOUR_OCI_ACCESS_KEY" \
  AWS_SECRET_ACCESS_KEY="YOUR_OCI_SECRET_KEY" \
  AWS_ENDPOINT_URL_S3="https://YOUR_NAMESPACE.compat.objectstorage.YOUR_REGION.oraclecloud.com" \
  BUCKET_NAME="blog-backups"

kubectl apply -f security/vso/secrets/optional/backup.yaml
kustomize build apps/ghost/optional | kubectl apply -f -
```

## 다음 단계

다음: [03-1-ingress-setup.md](./03-1-ingress-setup.md)
