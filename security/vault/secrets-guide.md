# Vault Secrets Guide

이 문서는 Vault에 수동으로 입력해야 하는 시크릿 목록과 경로를 설명합니다.

> **주의**: 예시에서 `sunghogigio.com`은 실제 도메인으로 변경하세요. 도메인은 `config/prod.env`에서 중앙 관리됩니다.

## KV v2 Mount

- Mount path: `kv`
- 모든 시크릿은 KV v2 엔진을 사용합니다.

## 시크릿 경로 및 키

### 1. Ghost Application (`kv/blog/prod/ghost`)

Ghost 애플리케이션 설정 및 DB 연결 정보:

```bash
vault kv put kv/blog/prod/ghost \
  url="https://sunghogigio.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="<SECURE_PASSWORD>" \
  database__connection__database="ghost" \
  mail__transport="SMTP" \
  mail__options__service="Mailgun" \
  mail__options__host="smtp.mailgun.org" \
  mail__options__port="587" \
  mail__options__auth__user="<SMTP_USER>" \
  mail__options__auth__pass="<SMTP_PASSWORD>"
```

### 2. MySQL (`kv/blog/prod/mysql`)

MySQL root 및 사용자 자격증명:

```bash
vault kv put kv/blog/prod/mysql \
  root_password="<MYSQL_ROOT_PASSWORD>" \
  user="ghost" \
  password="<MYSQL_GHOST_PASSWORD>" \
  database="ghost"
```

### 3. Cloudflare Tunnel (`kv/blog/prod/cloudflared`)

Cloudflare Tunnel 토큰:

```bash
vault kv put kv/blog/prod/cloudflared \
  token="<CLOUDFLARE_TUNNEL_TOKEN>"
```

### 4. Backup (OCI Object Storage S3) (`kv/blog/prod/backup`)

OCI Object Storage S3 호환 API 자격증명:

```bash
vault kv put kv/blog/prod/backup \
  AWS_ACCESS_KEY_ID="<OCI_ACCESS_KEY>" \
  AWS_SECRET_ACCESS_KEY="<OCI_SECRET_KEY>" \
  AWS_ENDPOINT_URL_S3="https://<namespace>.compat.objectstorage.<region>.oraclecloud.com" \
  BUCKET_NAME="<your-backup-bucket>"
```

## 초기화 순서

1. **Vault 초기화 및 Unseal**
   ```bash
   ./security/vault/init-scripts/01-init-unseal.sh
   ```

2. **KV v2 엔진 활성화** (이미 활성화되어 있을 수 있음)
   ```bash
   vault secrets enable -path=kv kv-v2
   ```

3. **정책 생성**
   ```bash
   vault policy write ghost security/vault/policies/ghost.hcl
   vault policy write mysql security/vault/policies/mysql.hcl
   vault policy write cloudflared security/vault/policies/cloudflared.hcl
   ```

4. **Kubernetes Auth 역할 생성**
   ```bash
   vault write auth/kubernetes/role/blog \
     bound_service_account_names=default \
     bound_service_account_namespaces=blog,cloudflared,vso \
     policies=ghost,mysql,cloudflared \
     ttl=24h
   ```

5. **시크릿 입력** (위의 명령어 사용)

## 보안 주의사항

- **Init/Unseal Keys**: 오프라인에 안전하게 보관. Git에 커밋 금지.
- **Root Token**: 초기 설정 후 폐기하고 개별 정책 기반 토큰 사용.
- **주기적 로테이션**: 민감 자격증명은 정기적으로 교체.
- **Audit Log**: `/vault/logs/audit.log`를 주기적으로 검토.

## VSO 동기화 확인

VSO가 Secret을 생성했는지 확인:

```bash
kubectl get secrets -n blog
kubectl get secrets -n cloudflared
```

예상 Secret:
- `ghost-env` (namespace: blog)
- `mysql-secret` (namespace: blog)
- `cloudflared-token` (namespace: cloudflared)
- `backup-s3` (namespace: blog)

