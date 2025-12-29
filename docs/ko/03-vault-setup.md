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

### MySQL Exporter (필수)

이 리포지토리는 `mysql` StatefulSet에 `mysql-exporter` 사이드카가 포함되어 있습니다.
- `kv/blog/prod/mysql-exporter`가 없거나 VSO가 `mysql-exporter-secret`을 생성하지 못하면 `mysql-0`가 NotReady로 남을 수 있고, Ghost가 MySQL 연결 실패로 장애가 날 수 있습니다.

```bash
vault kv put kv/blog/prod/mysql-exporter \
  user="mysql_exporter" \
  password="YOUR_EXPORTER_PASSWORD"
```

MySQL 사용자 생성 (`mysql` 컨테이너에서 실행):

```bash
MYSQL_ROOT_PASSWORD=$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.root_password}' | base64 -d)
MYSQL_EXPORTER_PASSWORD="YOUR_EXPORTER_PASSWORD"

kubectl exec -n blog mysql-0 -c mysql -- mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "
CREATE USER IF NOT EXISTS 'mysql_exporter'@'%' IDENTIFIED BY '${MYSQL_EXPORTER_PASSWORD}';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'mysql_exporter'@'%';
GRANT SELECT ON performance_schema.* TO 'mysql_exporter'@'%';
FLUSH PRIVILEGES;
"
```

### Cloudflared

```bash
vault kv put kv/blog/prod/cloudflared \
  token="YOUR_CLOUDFLARE_TUNNEL_TOKEN"
```

### 확인

```bash
vault kv list kv/blog/prod  # cloudflared, ghost, mysql, mysql-exporter
```

## VSO Secret 동기화 확인

```bash
# 10-30초 후 Secret 생성됨
kubectl get secrets -n blog  # ghost-env, mysql-secret, mysql-exporter-secret
kubectl get secrets -n cloudflared  # cloudflared-token

# 생성 안되면 VSO 재시작
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
kubectl get secrets -n blog  # 30초 후 재확인
```

## 선택 기능

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

→ [04-ingress-setup.md](./04-ingress-setup.md) - Ingress-nginx Admission Webhook
