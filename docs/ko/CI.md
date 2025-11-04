# CI 파이프라인

본 리포지토리는 GitHub Actions로 매니페스트 유효성 검증을 수행합니다.

## `.github/workflows/validate.yaml`

매니페스트 빌드 및 스키마 검증을 자동화합니다.

### 트리거
- Push to `main` 브랜치
- Pull Request to `main` 브랜치

### 작업 내용
1. **Kustomize 설치** (v5.4.3)
2. **Kubeconform 설치** (v0.6.7)
3. **모든 overlay 빌드 및 검증**:
   - `apps/ghost/overlays/prod`
   - `apps/ingress-nginx/overlays/prod`
   - `apps/cloudflared/overlays/prod`
   - `apps/observers/overlays/prod`
   - `security/vault`
   - `security/vso`

### 검증 항목
- Kubernetes 리소스 스키마 유효성
- CRD (Prometheus Operator, VSO 등) 스키마
- Kustomize 빌드 오류 여부

### 로컬 검증

CI 실행 전 로컬에서 미리 검증:

```bash
# Makefile 사용
make validate

# 또는 수동
kustomize build apps/ghost/overlays/prod | kubeconform -summary -strict
```

## (선택) Theme 자동 배포

Ghost 테마를 자동 배포하려면 `.github/workflows/theme-deploy.yaml` 생성:

```yaml
name: Deploy Ghost Theme
on:
  push:
    paths:
      - 'theme/**'
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: TryGhost/action-deploy-theme@v1
        with:
          api-url: ${{ secrets.GHOST_ADMIN_API_URL }}
          api-key: ${{ secrets.GHOST_ADMIN_API_KEY }}
          theme-name: "my-theme"
          file: "theme"
```

**필요 Secrets:**
- `GHOST_ADMIN_API_URL`: `https://yourdomain.com`
- `GHOST_ADMIN_API_KEY`: Ghost Admin → Integrations → Custom Integration

## 권장 사항

- PR은 Draft로 생성하고, Reviewer/Label 정책을 적용하세요.
- CI가 통과한 후에만 main 브랜치에 머지하세요.
