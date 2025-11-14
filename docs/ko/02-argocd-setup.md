# 02. Argo CD 설치 및 구성

GitOps를 위한 Argo CD 설치 및 App-of-Apps 패턴 배포

## 개요

- Argo CD: Git 기반 선언적 배포 도구
- Applications가 CRD 의존성 해결을 위해 8개로 분리됨
- 예상 소요 시간: 15분

## 전제 조건

- k3s 설치 완료 (01-infrastructure.md)
- VM SSH 접속
- 프로젝트 디렉토리: `~/blogstack-k8s`
- 모든 명령어는 프로젝트 루트에서 실행

### Git URL 변경 확인 (필수)

```bash
cd ~/blogstack-k8s

# your-org가 없어야 함
grep -r "your-org/blogstack-k8s" iac/ clusters/prod/
# 출력 없으면 OK
```

변경 안 됨 → CUSTOMIZATION.md 참조

## 설치 단계

### 1. 네임스페이스 생성

```bash
kubectl create namespace argocd
```

### 2. Argo CD 설치

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 3. Pod 배포 대기 (2-3분)

```bash
# 실시간 모니터링
kubectl get pods -n argocd -w
# Ctrl+C로 종료

# 또는
kubectl wait --for=condition=available --timeout=300s deployment -n argocd --all
```

확인:
```bash
kubectl get pods -n argocd
# 모두 Running
```

### 4. Admin 비밀번호 확인

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

### 5. Argo CD 설정 (Kustomize Helm 지원)

```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm --load-restrictor LoadRestrictionsNone"}}'

kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd
```

### 6. AppProject 생성

```bash
kubectl apply -f ./clusters/prod/project.yaml
```

확인:
```bash
kubectl get appproject blog -n argocd

# destinations 확인 (argocd 네임스페이스 필수)
kubectl get appproject blog -n argocd -o yaml | grep -A 15 "destinations:"
```

### 7. Root App 배포

```bash
kubectl apply -f ./iac/argocd/root-app.yaml
```

확인:
```bash
kubectl get applications -n argocd
```

예상 출력 (30초 후):
```
NAME               SYNC STATUS   HEALTH STATUS   
blogstack-root     Synced        Healthy
observers          Synced        Progressing
observers-probes   Synced        Progressing
ingress-nginx      Synced        Progressing
cloudflared        Synced        Progressing
vault              Synced        Progressing
vso-operator       Synced        Progressing
vso-resources      Synced        Progressing
ghost              Synced        Progressing
```

## Applications 동기화 대기

Sync Wave 순서 (총 5-10분):

| Wave | App | 역할 | 소요 |
|------|-----|------|------|
| `-2` | observers | Prometheus, Grafana, Loki | 3-5분 |
| `-1` | observers-probes | Blackbox Exporter | 30초 |
| `-1` | ingress-nginx | Ingress Controller | 1-2분 |
| `0` | cloudflared | Cloudflare Tunnel | 1분 |
| `1` | vault | HashiCorp Vault | 1-2분 |
| `2` | vso-operator | Vault Secrets Operator | 1분 |
| `3` | vso-resources | Vault 연결 및 시크릿 매핑 | 30초 |
| `4` | ghost | Ghost + MySQL | 2-3분 |

실시간 모니터링:
```bash
watch -n 5 kubectl get applications -n argocd
```

예상 최종 상태 (10분 후):
```bash
kubectl get applications -n argocd

# NAME               SYNC STATUS   HEALTH STATUS
# blogstack-root     Synced        Healthy
# observers          Synced        Healthy
# observers-probes   Synced        Healthy
# ingress-nginx      Synced        Healthy
# cloudflared        Synced        Degraded      ← 정상 (Vault 시크릿 대기)
# vault              Synced        Progressing   ← 정상 (미초기화)
# vso-operator       Synced        Healthy
# vso-resources      Synced        Healthy
# ghost              Synced        Degraded      ← 정상 (Vault 시크릿 대기)
```

Degraded/Progressing: Vault 미초기화 및 시크릿 미입력 (다음 단계에서 해결)

Pod 상태:
```bash
kubectl get pods -A | grep -E "NAMESPACE|blog|vault|cloudflared"

# vault/vault-0: 0/1 Running (Sealed - 미초기화)
# cloudflared/cloudflared-*: 0/1 CreateContainerConfigError (시크릿 없음)
# blog/mysql-0: 0/1 CreateContainerConfigError (시크릿 없음)
# blog/ghost-*: 0/1 CreateContainerConfigError (시크릿 없음)
```

CreateContainerConfigError는 정상 (Vault 미초기화로 시크릿 미생성)

## 설치 완료 확인

```bash
echo "=== Argo CD 확인 ==="

# Argo CD Pods
kubectl get pods -n argocd --no-headers | awk '{print $1 " - " $3}'

# Vault Pod
kubectl get pods -n vault --no-headers | awk '{print $1 " - " $3}'

# Applications
kubectl get applications -n argocd --no-headers | awk '{print $1 " - " $2 " - " $3}'

echo "=== 완료 ==="
```

진행 조건:
- Argo CD Pod 모두 Running
- Vault Pod Running (0/1 정상 - 미초기화)
- 모든 Application Synced (9개)
- vault, cloudflared, ghost Degraded/Progressing (정상)

## 트러블슈팅

### Root App "project blog which does not exist"

```bash
kubectl apply -f ./clusters/prod/project.yaml
kubectl delete application blogstack-root -n argocd
kubectl apply -f ./iac/argocd/root-app.yaml
```

### "do not match any of the allowed destinations"

원인: AppProject의 destinations에 argocd 네임스페이스 없음

```bash
kubectl get appproject blog -n argocd -o yaml | grep -A 15 "destinations:"

# argocd 없으면 파일 수정 후
kubectl apply -f ./clusters/prod/project.yaml
kubectl delete application blogstack-root -n argocd
kubectl apply -f ./iac/argocd/root-app.yaml
```

### "must specify --enable-helm"

```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm --load-restrictor LoadRestrictionsNone"}}'

kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd

# Application refresh
kubectl patch application observers -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Git URL "your-org"

```bash
kubectl delete application blogstack-root -n argocd

cd ~/blogstack-k8s
OLD_URL="https://github.com/your-org/blogstack-k8s"
NEW_URL="https://github.com/<본인계정>/blogstack-k8s"

sed -i "s|$OLD_URL|$NEW_URL|g" iac/argocd/root-app.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/apps.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/project.yaml

git add iac/ clusters/
git commit -m "Fix: Update Git URL"
git push origin main

git pull origin main
kubectl apply -f ./iac/argocd/root-app.yaml
```

### Helm Chart 다운로드 실패

```bash
curl -I https://prometheus-community.github.io/helm-charts
# OCI Security List: Egress 0.0.0.0/0:443 필요
```

### ImagePullBackOff

```bash
curl -I https://registry.hub.docker.com
# 잠시 후 자동 재시도
```

## Argo CD UI 접근 (선택)

VM:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

로컬:
```bash
ssh -L 8080:localhost:8080 -i ~/.ssh/oci_key ubuntu@<VM_IP>
```

브라우저: `https://localhost:8080`
- Username: `admin`
- Password: (4번에서 확인한 비밀번호)

## 다음 단계

Argo CD 설치 완료

현재 상태:
- Argo CD 설치 완료
- 모든 Application 배포 (Synced)
- VSO 리소스 생성 완료
- Vault Pod Running (0/1 - 미초기화)
- cloudflared, ghost Pod이 시크릿 대기 중

다음 필수 단계: Vault 초기화 및 시크릿 입력

→ [03-vault-setup.md](./03-vault-setup.md) - Vault 초기화 및 시크릿 입력
