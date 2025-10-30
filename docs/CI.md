# CI 파이프라인

본 리포지토리는 GitHub Actions로 매니페스트 유효성 검증을 수행합니다.

## validate.yaml

- 트리거: PR/Push to main
- 작업:
  - kustomize 설치 (v5.4.x)
  - kubeconform 설치 (v0.6.x)
  - prod/dev overlays 및 보안 디렉토리 빌드/검증

## theme-deploy.yaml

- 트리거: `theme/**` 변경
- TryGhost 액션으로 테마 배포
- 필요 Secrets:
  - `GHOST_ADMIN_API_URL`
  - `GHOST_ADMIN_API_KEY`

## 권장 사항

- PR은 Draft로 생성하고, Reviewer/Label 정책을 적용하세요.
