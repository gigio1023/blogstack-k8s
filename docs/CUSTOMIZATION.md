# 커스터마이징 가이드

이 문서는 blogstack-k8s를 본인의 블로그로 커스터마이징하는 방법을 설명합니다.

## 설계 원칙

**중앙화된 설정**: 모든 개인화 설정은 `config/prod.env` 한 곳에서 관리합니다. Kubernetes 리소스에는 도메인이나 개인 정보가 하드코딩되지 않습니다.

**재사용 가능한 인프라**: 이 리포지토리의 코드는 누구나 fork해서 `config/prod.env`만 수정하면 바로 사용할 수 있습니다.

## 1단계: config/prod.env 수정

리포지토리 최상위의 `config/prod.env` 파일을 열어 다음 값들을 수정합니다:

```env
# 기본 설정
domain=yourdomain.com                    # 실제 도메인으로 변경
siteUrl=https://yourdomain.com           # 도메인과 일치하도록
email=admin@yourdomain.com               # 관리자 이메일
timezone=Asia/Seoul                      # 시간대 (변경 가능)
alertEmail=admin@yourdomain.com          # 알림 수신 이메일

# 모니터링 URL (도메인만 변경하면 자동 맞춤)
monitorUrlHome=https://yourdomain.com/
monitorUrlSitemap=https://yourdomain.com/sitemap.xml
monitorUrlGhost=https://yourdomain.com/ghost/
```

### 중요: 이 파일만 수정하면 됩니다!

- ✅ **이 파일 수정**: `config/prod.env`
- ❌ **수정하지 않아도 됨**:
  - `apps/ghost/base/ingress.yaml` (자동 주입)
  - `apps/observers/base/probe.yaml` (자동 주입)
  - 기타 모든 Kubernetes 리소스

## 2단계: Git Repository URL 변경

### Root Application

`iac/argocd/root-app.yaml`:

```yaml
spec:
  source:
    repoURL: https://github.com/your-org/blogstack-k8s  # 여기를 변경
```

### Child Applications

`clusters/prod/apps.yaml`:

```yaml
# 모든 Application의 repoURL을 변경
spec:
  source:
    repoURL: https://github.com/your-org/blogstack-k8s  # 여기를 변경
```

## 3단계: Vault 시크릿 준비

`security/vault/secrets-guide.md`를 참조하여 입력할 시크릿을 준비합니다:

### Ghost 시크릿 (`kv/blog/prod/ghost`)

```bash
vault kv put kv/blog/prod/ghost \
  url="https://yourdomain.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="<your-secure-password>" \
  database__connection__database="ghost" \
  mail__transport="SMTP" \
  mail__options__host="smtp.mailgun.org" \
  mail__options__port="587" \
  mail__options__auth__user="<your-smtp-user>" \
  mail__options__auth__pass="<your-smtp-password>"
```

### MySQL 시크릿 (`kv/blog/prod/mysql`)

```bash
vault kv put kv/blog/prod/mysql \
  root_password="<mysql-root-password>" \
  user="ghost" \
  password="<same-as-ghost-db-password>"
```

### Cloudflare Tunnel (`kv/blog/prod/cloudflared`)

```bash
vault kv put kv/blog/prod/cloudflared \
  token="<cloudflare-tunnel-token>"
```

### 백업 S3 (`kv/blog/prod/backup`)

```bash
vault kv put kv/blog/prod/backup \
  AWS_ACCESS_KEY_ID="<oci-access-key>" \
  AWS_SECRET_ACCESS_KEY="<oci-secret-key>" \
  AWS_ENDPOINT_URL_S3="https://<namespace>.compat.objectstorage.<region>.oraclecloud.com"
```

## 자동 주입 확인

설정이 올바르게 주입되는지 확인:

### 1. Ghost Ingress Host

```bash
kubectl get ingress -n blog ghost -o yaml | grep host
# 출력: host: yourdomain.com (config/prod.env의 domain 값)
```

### 2. Blackbox Probe Targets

```bash
kubectl get probe -n observers blog-external -o yaml | grep -A3 static:
# 출력: config/prod.env의 monitorUrl* 값들
```

### 3. Ghost URL 환경변수

```bash
kubectl get pods -n blog -l app=ghost -o jsonpath='{.items[0].spec.containers[0].env}' | jq
# url: config/prod.env의 siteUrl
```

## 다중 환경 (선택사항)

dev/staging 환경을 추가하려면:

### 1. 설정 파일 복사

```bash
cp config/prod.env config/dev.env
vim config/dev.env  # dev 도메인으로 수정
```

### 2. Overlay 생성

```bash
mkdir -p apps/ghost/overlays/dev
# kustomization.yaml에서 dev.env 참조
```

### 3. Cluster 디렉토리 생성

```bash
mkdir -p clusters/dev
# apps.yaml, project.yaml 복사 및 수정
```

## 문서의 예시 도메인

문서와 가이드에서 `sunghogigio.com`은 **예시**입니다. 실제 구축 시에는:

- ✅ `config/prod.env`의 값 사용
- ✅ Vault 시크릿에 실제 도메인 입력
- ✅ Cloudflare에서 실제 도메인 설정

## 검증 체크리스트

배포 전 확인사항:

- [ ] `config/prod.env`에 실제 도메인/이메일 입력
- [ ] `iac/argocd/root-app.yaml`의 repoURL 변경
- [ ] `clusters/prod/apps.yaml`의 모든 repoURL 변경
- [ ] Vault 시크릿 준비 (도메인 포함)
- [ ] Cloudflare Tunnel 생성 및 토큰 발급
- [ ] OCI Object Storage 버킷 및 키 생성

## 트러블슈팅

### Ingress에 잘못된 도메인

**원인**: `config/prod.env`가 업데이트되지 않았거나 Argo CD가 동기화 안됨

**해결**:
```bash
# config/prod.env 수정 후
git add config/prod.env
git commit -m "Update domain"
git push

# Argo CD 수동 동기화
kubectl patch app ghost -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge
```

### Blackbox Probe가 example.invalid 체크

**원인**: observers 앱이 아직 동기화되지 않음

**해결**:
```bash
kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-repo-server
# Argo CD가 재시작되면 자동 동기화
```

## 추가 리소스

- [config/README.md](../config/README.md) - 설정 파일 상세 설명
- [security/vault/secrets-guide.md](../security/vault/secrets-guide.md) - Vault 시크릿 가이드
- [docs/03-vault-setup.md](./03-vault-setup.md) - Vault 초기화 방법

