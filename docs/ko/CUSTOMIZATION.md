# 커스터마이징

blogstack-k8s를 본인의 블로그로 커스터마이징

## 빠른 시작

Fork 후 배포를 위한 최소 수정 (VM에서 실행)

### 전제조건

- 00-prerequisites.md 완료
- VM SSH 접속
- 준비: 도메인, Git 저장소 URL

### 1단계: 리포지토리 Clone (VM 내부)

```bash
# VM에 SSH 접속
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>

# 작업 디렉토리로 이동
cd ~

# 리포지토리 Clone (본인이 fork한 저장소)
git clone https://github.com/YOUR_GITHUB_USERNAME/blogstack-k8s.git
cd blogstack-k8s

# 현재 위치 확인
pwd
# 예상 출력: /home/ubuntu/blogstack-k8s
```

참고: 원본 저장소가 아닌 본인이 fork한 저장소를 clone하세요

---

### 2단계: Git URL 일괄 변경

```bash
# 현재 URL 확인
grep "repoURL" iac/argocd/root-app.yaml

# 변수 설정 (실제 값으로 변경)
OLD_URL="https://github.com/your-org/blogstack-k8s"
NEW_URL="https://github.com/YOUR_GITHUB_USERNAME/blogstack-k8s"

# 일괄 변경 (Linux - VM에서)
sed -i "s|$OLD_URL|$NEW_URL|g" \
  iac/argocd/root-app.yaml \
  clusters/prod/apps.yaml \
  clusters/prod/project.yaml

# 변경 확인
grep "repoURL" iac/argocd/root-app.yaml
# 예상 출력: repoURL: https://github.com/YOUR_GITHUB_USERNAME/blogstack-k8s
```

실제 예시:
```bash
# 예: GitHub 사용자명이 "johndoe"인 경우
OLD_URL="https://github.com/your-org/blogstack-k8s"
NEW_URL="https://github.com/johndoe/blogstack-k8s"

sed -i "s|$OLD_URL|$NEW_URL|g" \
  iac/argocd/root-app.yaml \
  clusters/prod/apps.yaml \
  clusters/prod/project.yaml
```

---

### 3단계: 도메인 변경

```bash
# config/prod.env 파일 수정
vi config/prod.env
```

변경 전:
```env
domain=yourdomain.com
siteUrl=https://yourdomain.com
email=admin@yourdomain.com
timezone=Asia/Seoul
```

변경 후 (실제 예시):
```env
domain=myblog.com
siteUrl=https://myblog.com
email=admin@myblog.com
timezone=Asia/Seoul
```

저장 및 종료: `ESC` → `:wq`

변경 확인:
```bash
cat config/prod.env | grep -E "^domain=|^siteUrl=|^email="

# 예상 출력:
# domain=myblog.com
# siteUrl=https://myblog.com
# email=admin@myblog.com
```

---

### 4단계: Commit & Push

```bash
# Git 설정 (최초 1회만)
git config --global user.name "Your Name"
git config --global user.email "your-email@example.com"

# 변경사항 확인
git status

# 예상 출력:
# modified:   iac/argocd/root-app.yaml
# modified:   clusters/prod/apps.yaml
# modified:   clusters/prod/project.yaml
# modified:   config/prod.env

# 스테이징
git add iac/argocd/root-app.yaml \
        clusters/prod/apps.yaml \
        clusters/prod/project.yaml \
        config/prod.env

# 커밋
git commit -m "Customize: Update Git URL and domain to myblog.com"

# Push (GitHub 인증 필요)
git push origin main
```

GitHub 인증 방법:
```bash
# Personal Access Token 사용 (권장)
# GitHub → Settings → Developer settings → Personal access tokens → Generate new token
# Scopes: repo (전체)

# Push 시 Username: YOUR_GITHUB_USERNAME
# Password: (생성한 Personal Access Token)
```

---

### 5단계: 외부 서비스 준비 완료 확인

다음이 **모두 준비**되었는지 재확인:

```bash
# 체크리스트 (터미널에서 복사하여 사용)
cat << 'EOF'
외부 서비스 준비 완료 확인:
□ Cloudflare Tunnel Token 복사 완료
□ MySQL 비밀번호 2개 생성 완료 (Root, Ghost)

선택 (필요 시):
□ OCI S3 Access Key/Secret Key 복사 완료 (백업 활성화 시)
□ SMTP 자격증명 복사 완료 (이메일 발송 시)
EOF
```

---

### 완료

이제 다음 단계로:

→ [01-infrastructure.md](./01-infrastructure.md) - k3s 설치 (5분)

---

## 설계 원칙

**중앙화된 설정**: 기본 설정은 `config/prod.env`에서 관리하며, 모니터링 타깃은 `apps/observers/overlays/prod/vmagent-scrape.yml`에서 관리합니다.

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

# 모니터링 타깃은 vmagent-scrape.yml에서 변경 (아래 2단계 참고)
```

### 중요: 기본 설정은 이 파일에서 수정합니다

- ✅ **이 파일 수정**: `config/prod.env`
- ✅ **모니터링 타깃 수정**: `apps/observers/overlays/prod/vmagent-scrape.yml`
- ❌ **수정하지 않아도 됨**:
  - `apps/ghost/base/ingress.yaml` (자동 주입)
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

기본 구성 (SMTP 없이):
```bash
vault kv put kv/blog/prod/ghost \
  url="https://yourdomain.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="<your-secure-password>" \
  database__connection__database="ghost"
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

### 선택 기능

SMTP 이메일 발송(필수)은 docs/07-smtp-setup.md, 백업 자동화는 apps/ghost/optional/README.md 참조

## 자동 주입 확인

설정이 올바르게 주입되는지 확인:

### 1. Ghost Ingress Host

```bash
kubectl get ingress -n blog ghost -o yaml | grep host
# 출력: host: yourdomain.com (config/prod.env의 domain 값)
```

### 2. Blackbox Targets

```bash
kubectl get configmap -n observers vmagent-scrape -o yaml | grep -A5 blackbox
# 출력: vmagent-scrape.yml의 targets 값들
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

필수:
- [ ] `config/prod.env`에 실제 도메인/이메일 입력
- [ ] `iac/argocd/root-app.yaml`의 repoURL 변경
- [ ] `clusters/prod/apps.yaml`의 모든 repoURL 변경
- [ ] Vault 시크릿 준비 (도메인 포함)
- [ ] Cloudflare Tunnel 생성 및 토큰 발급

선택:
- [ ] OCI Object Storage 버킷 및 키 생성 (백업 활성화 시)
- [ ] SMTP 자격증명 준비 (이메일 발송 시)

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

### Blackbox Targets가 example.invalid 체크

**원인**: `vmagent-scrape.yml`에서 도메인을 변경하지 않았거나, observers 앱이 아직 동기화되지 않음

**해결**:
```bash
# 파일 수정 후 커밋/푸시
git add apps/observers/overlays/prod/vmagent-scrape.yml
git commit -m "docs(monitoring): update blackbox targets"
git push

# 필요 시 Argo CD 강제 리프레시
kubectl patch app observers -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge
```

## 추가 리소스

- [config/README.md](../config/README.md) - 설정 파일 상세 설명
- [security/vault/secrets-guide.md](../security/vault/secrets-guide.md) - Vault 시크릿 가이드
- [docs/03-vault-setup.md](./03-vault-setup.md) - Vault 초기화 방법
