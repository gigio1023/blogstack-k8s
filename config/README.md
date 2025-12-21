# Config Directory

이 디렉토리는 **퍼블릭 설정**만 포함합니다. 민감 정보는 Vault에 저장됩니다.

## prod.env

프로덕션 환경의 중앙 설정 파일입니다.

### 포함 항목

**기본 설정:**
- `domain`: 블로그 도메인 (예: yourdomain.com)
- `siteUrl`: Ghost URL (예: https://yourdomain.com)
- `email`: 관리자 이메일
- `timezone`: 시간대 (예: Asia/Seoul)
- `alertEmail`: 알림 수신 이메일

모니터링(Blackbox) URL은 `apps/observers/overlays/prod/vmagent-scrape.yml`에서 관리합니다.

### 사용 방식

각 앱의 `overlays/prod/kustomization.yaml`에서 `configMapGenerator`로 읽어옵니다:

```yaml
configMapGenerator:
  - name: prod-config
    envs:
      - ../../../../config/prod.env
```

생성된 `prod-config` ConfigMap은 Kustomize `replacements` 기능으로 다른 리소스에 주입됩니다.

### 예시: Ingress host 주입

```yaml
replacements:
  - source:
      kind: ConfigMap
      name: prod-config
      fieldPath: data.domain
    targets:
      - select:
          kind: Ingress
          name: ghost
        fieldPaths:
          - spec.rules.0.host
```

## 커스터마이징

새로운 환경(dev, staging)을 추가하려면:

1. `config/dev.env` 생성
2. `apps/*/overlays/dev/kustomization.yaml` 생성
3. `clusters/dev/` 생성 및 App-of-Apps 구성

## 보안 주의사항

**이 파일에는 시크릿을 넣지 마세요!**

민감 정보는 항상 Vault에 저장:
- 비밀번호, API 키, 토큰
- DB 연결 정보 (비밀번호 포함)
- SMTP 자격증명
- Cloudflare Tunnel 토큰
- OCI Object Storage 키

Vault 시크릿 경로는 `security/vault/secrets-guide.md` 참조
