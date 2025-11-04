# VSO 선택 시크릿

## backup.yaml

OCI Object Storage 백업을 위한 S3 호환 API 시크릿

사용법:
```bash
kubectl apply -f backup.yaml
```

필수: Vault에 `kv/blog/prod/backup` 경로에 시크릿이 저장되어 있어야 함

상세 설정: apps/ghost/optional/README.md 참조

