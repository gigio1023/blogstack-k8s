# 02. Argo CD 설치 및 구성

GitOps를 위한 Argo CD 설치 및 App-of-Apps 패턴 구성

## Argo CD란?

- **선언적 GitOps CD**: Git을 단일 진실 원천(Single Source of Truth)으로 사용
- **자동 동기화**: Git commit → 클러스터 자동 반영
- **웹 UI 제공**: 시각적 배포 상태 확인

## 설치

### 1. Argo CD 네임스페이스 생성

```bash
kubectl create namespace argocd
```

### 2. Argo CD 설치 (공식 매니페스트)

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 3. 설치 확인

```bash
# Pod 상태 확인 (모두 Running이 될 때까지 대기)
kubectl get pods -n argocd

# 예상 Pod 목록:
# - argocd-application-controller
# - argocd-dex-server
# - argocd-redis
# - argocd-repo-server
# - argocd-server
```

### 4. Admin 비밀번호 확인

```bash
# 초기 비밀번호는 argocd-initial-admin-secret에 저장됨
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

### 5. Argo CD UI 접근

#### 방법 1: kubectl port-forward

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

브라우저: `https://localhost:8080`
- Username: `admin`
- Password: (위에서 확인한 비밀번호)

#### 방법 2: Ingress (선택)

나중에 Ingress-NGINX 설치 후 Ingress 리소스 생성 가능

## Git 리포지토리 설정

### 1. GitHub에 리포지토리 Push

```bash
cd /path/to/blogstack-k8s

# Git 초기화 (아직 안했다면)
git init
git add .
git commit -m "Initial blogstack-k8s setup"

# GitHub 리모트 추가 및 Push
git remote add origin https://github.com/<your-org>/blogstack-k8s.git
git branch -M main
git push -u origin main
```

### 2. Root App YAML 수정

`iac/argocd/root-app.yaml` 파일의 `repoURL` 수정:

```yaml
spec:
  source:
    repoURL: https://github.com/<your-org>/blogstack-k8s  # 여기를 실제 URL로 변경
    targetRevision: HEAD
    path: clusters/prod
```

`clusters/prod/apps.yaml`의 모든 Application `repoURL`도 동일하게 수정

## Root App 배포

### 1. Root App 적용

```bash
kubectl apply -f iac/argocd/root-app.yaml
```

### 2. 동기화 확인

```bash
# Root App 상태
kubectl get application -n argocd

# 자세한 상태
kubectl describe application blogstack-root -n argocd
```

### 3. Argo CD UI에서 확인

- Root App: `blogstack-root`
- 자식 Apps (sync-wave 순서):
  - `-2`: `observers` (kube-prometheus-stack, loki, blackbox)
  - `-1`: `ingress-nginx`
  - `0`: `cloudflared`
  - `1`: `vault`
  - `2`: `vso`
  - `3`: `ghost`

## 자동 동기화 활성화 (선택)

Root App에 이미 `syncPolicy.automated`가 설정되어 있어 Git 변경 시 자동 동기화됩니다.

수동 동기화 원하면:

```yaml
# iac/argocd/root-app.yaml
spec:
  syncPolicy:
    # automated 섹션 제거 또는 주석 처리
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
```

## CLI로 동기화

Argo CD CLI 설치 (선택):

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```

로그인 및 동기화:

```bash
# 로그인
argocd login localhost:8080 --username admin --password <password> --insecure

# App 목록
argocd app list

# 수동 동기화
argocd app sync blogstack-root

# 동기화 대기
argocd app wait blogstack-root
```

## Kustomize 버전 고정 (권장)

Argo CD가 사용하는 Kustomize/Helm 버전 명시:

```bash
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"kustomize.buildOptions":"--enable-helm --load-restrictor=LoadRestrictionsNone"}}'
```

## 트러블슈팅

### App이 OutOfSync 상태

```bash
# Diff 확인
argocd app diff <app-name>

# 강제 동기화
argocd app sync <app-name> --force
```

### Helm Chart 다운로드 실패

- 네트워크 확인: VM에서 Helm repo에 접근 가능한지
- 방화벽: 443/tcp 아웃바운드 허용

### CRD 관련 오류

`SkipDryRunOnMissingResource=true` 옵션이 각 App의 syncOptions에 있는지 확인

## 다음 단계

Argo CD를 통해 관측 스택과 Ingress-NGINX가 자동 배포됩니다.
다음은 Vault를 초기화하고 시크릿을 주입합니다.

다음: [03-vault-setup.md](./03-vault-setup.md)

