# 보안 가이드

본 문서는 최소권한 원칙으로 운영하기 위한 설정을 요약합니다.

## Argo CD AppProject 경계

- `clusters/prod/project.yaml`에서 허용 소스/대상 네임스페이스를 명시적으로 제한했습니다.
- 운영 환경에서는 실제 리포지토리 URL을 정확히 설정하세요.

## Pod Security Standards (PSS)

- 각 overlay에 `Namespace` 리소스를 추가하여 라벨을 부여했습니다.
  - `pod-security.kubernetes.io/enforce: baseline`
  - `pod-security.kubernetes.io/warn: restricted`

## NetworkPolicy

- `blog` 네임스페이스: 기본 Ingress 차단, `ghost`는 Ingress Controller에서만, `mysql`은 `ghost`에서만 접근 허용
- `cloudflared`: 기본 Ingress 차단, `observers` 네임스페이스에서의 메트릭 접근만 허용
- `vault`: 기본 Ingress 차단, `vso`/`observers`에서 8200 접근 허용

## Vault + VSO

- 각 네임스페이스에 전용 `ServiceAccount`(vault-reader)와 `VaultAuth`를 생성했습니다.
- Vault의 Kubernetes Auth Role은 네임스페이스/SA 별로 분리하여 바인딩하세요.
  - 예: `blog` 역할은 `ns=blog, sa=vault-reader`에, `cloudflared` 역할은 `ns=cloudflared, sa=vault-reader`에 바인딩
- TLS는 초기에는 비활성(HTTP)로 시작하고, 추후 mTLS 또는 Ingress로 TLS 종단을 고려하세요.

## Ingress Controller 하드닝

- `use-forwarded-headers`, `real-ip`, `Cloudflare CIDR` 설정 적용
- 업로드/대용량 요청 지원을 위해 다음 값을 추가했습니다:
  - `proxy-body-size: 50m`
  - `proxy-read-timeout: 600`, `proxy-send-timeout: 600`

## 시크릿 저장 위치

- 퍼블릭 값: `config/prod.env`
- 민감 값: Vault (VSO로 앱 네임스페이스에 동기화)
