# Ghost 선택 기능

## 백업 (Backup)

MySQL 데이터베이스와 Ghost 컨텐츠를 OCI Object Storage에 자동 백업합니다.

### 사전 요구사항

1. OCI Object Storage 버킷 생성
2. S3 호환 API Access Key 발급
3. Vault에 백업 시크릿 저장

### 활성화 방법

1. Vault에 백업 시크릿 입력:
```bash
vault kv put kv/blog/prod/backup \
  AWS_ACCESS_KEY_ID="(OCI Access Key)" \
  AWS_SECRET_ACCESS_KEY="(OCI Secret Key)" \
  AWS_ENDPOINT_URL_S3="https://NAMESPACE.compat.objectstorage.REGION.oraclecloud.com" \
  BUCKET_NAME="blog-backups"
```

2. VSO Secret 활성화:
```bash
kubectl apply -f /home/ubuntu/git/blogstack-k8s/security/vso/secrets/optional/backup.yaml
```

3. CronJob 배포:
```bash
kustomize build /home/ubuntu/git/blogstack-k8s/apps/ghost/optional | kubectl apply -f -
```

### 백업 스케줄

- MySQL: 매일 03:00 (KST 12:00)
- Ghost 컨텐츠: 매일 03:30 (KST 12:30)

### 복구 방법

docs/04-operations.md의 "백업 및 복구" 섹션 참조

