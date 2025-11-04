# 환경 구성 (dev/prod)

본 리포지토리는 다중 환경을 다음과 같이 지원합니다.

## 설정 파일

- `config/prod.env`: 프로덕션 설정
- `config/dev.env`: 개발 설정

## Kustomize overlays

- dev: `apps/*/overlays/dev` (네임스페이스: `*-dev`)
- prod: `apps/*/overlays/prod`

## Argo CD Root (예시)

- prod: `iac/argocd/root-app.yaml` → `clusters/prod`
- dev: 별도 Root App 생성 후 `clusters/dev`를 소스로 지정

## 주입 항목

- 도메인/URL: `config/<env>.env` → ConfigMap → replacements
- 시크릿: Vault (공통), 네임스페이스는 환경별로 구분

## 배포 순서(동일)

- observers → ingress-nginx → cloudflared → vault → vso → ghost
