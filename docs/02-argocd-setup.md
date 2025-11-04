# 02. Argo CD 설치 및 구성

GitOps를 위한 Argo CD 설치 및 App-of-Apps 패턴 배포

---

## 개요

- Argo CD: Git 기반 선언적 배포 도구
- 수동 설치 권장 (투명성, 학습, 디버깅 용이)
- 예상 소요 시간: 15분

---

## 전제 조건

- k3s 설치 완료 ([01-infrastructure.md](./01-infrastructure.md))
- VM SSH 접속 상태
- 프로젝트 디렉토리: `~/blogstack-k8s`

### Git URL 변경 확인 (필수)

3개 파일에서 `your-org`가 없어야 함:

```bash
cd ~/blogstack-k8s

# 1. Root App
grep "repoURL" iac/argocd/root-app.yaml

# 2. Child Apps (6개)
grep "repoURL" clusters/prod/apps.yaml

# 3. Project
grep "sourceRepos" clusters/prod/project.yaml

# 한 번에 확인
grep -r "your-org/blogstack-k8s" iac/ clusters/prod/
# 출력 없으면 OK
```

변경 안 됨 → [CUSTOMIZATION.md](./CUSTOMIZATION.md) 참조

---

## 설치 단계

### 1. 네임스페이스 생성

```bash
kubectl create namespace argocd
```

### 2. Argo CD 설치

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

약 30-50개 리소스 생성 (CustomResourceDefinition, ServiceAccount, Deployment 등)

### 3. Pod 배포 대기 (2-3분)

```bash
# 실시간 모니터링
kubectl get pods -n argocd -w
# Ctrl+C로 종료

# 또는 wait 명령어
kubectl wait --for=condition=available --timeout=300s deployment -n argocd --all
```

모든 Pod이 Running 상태 확인:

```bash
kubectl get pods -n argocd

# 예상 출력:
# NAME                                  READY   STATUS    RESTARTS   AGE
# argocd-application-controller-0       1/1     Running   0          2m
# argocd-dex-server-xyz                 1/1     Running   0          2m
# argocd-redis-xyz                      1/1     Running   0          2m
# argocd-repo-server-xyz                1/1     Running   0          2m
# argocd-server-xyz                     1/1     Running   0          2m
```

### 4. Admin 비밀번호 확인

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

비밀번호 저장 (선택):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d > ~/argocd-password.txt
```

### 5. Root App 배포

```bash
kubectl apply -f ./iac/argocd/root-app.yaml
```

확인:

```bash
kubectl get applications -n argocd

# 예상 출력 (약 30초 후):
# NAME              SYNC STATUS   HEALTH STATUS   
# blogstack-root    Synced        Healthy
# observers         Synced        Progressing
# ingress-nginx     Synced        Progressing
# cloudflared       Synced        Progressing
# vault             Synced        Progressing
# vso               Synced        Progressing
# ghost             Synced        Progressing
```

---

## Applications 동기화 대기

Sync Wave 순서에 따라 자동 배포 (총 5-10분):

| Wave | App | 역할 | 소요 시간 |
|------|-----|------|-----------|
| `-2` | observers | Prometheus, Grafana, Loki | 3-5분 |
| `-1` | ingress-nginx | Ingress Controller | 1-2분 |
| `0` | cloudflared | Cloudflare Tunnel | 1분 |
| `1` | vault | HashiCorp Vault | 1-2분 |
| `2` | vso | Vault Secrets Operator | 1분 |
| `3` | ghost | Ghost + MySQL | 2-3분 |

### 실시간 모니터링

```bash
# 5초마다 갱신
watch -n 5 kubectl get applications -n argocd
```

### 예상 최종 상태 (10분 후)

```bash
kubectl get applications -n argocd

# NAME              SYNC STATUS   HEALTH STATUS
# blogstack-root    Synced        Healthy
# observers         Synced        Healthy
# ingress-nginx     Synced        Healthy
# cloudflared       Synced        Degraded      ⚠️ 정상
# vault             Synced        Healthy
# vso               Synced        Healthy
# ghost             Synced        Degraded      ⚠️ 정상
```

Degraded 이유: Vault 시크릿 미입력 (다음 단계에서 해결)

```bash
# Pod 상태 확인
kubectl get pods -A | grep -E "NAMESPACE|blog|vault|cloudflared"

# 예상:
# vault/vault-0: Running (0/1 정상 - Sealed 상태)
# cloudflared/cloudflared-*: CrashLoopBackOff (시크릿 대기)
# blog/mysql-0: Running
# blog/ghost-*: CrashLoopBackOff (시크릿 대기)
```

---

## 설치 완료 확인

```bash
echo "=== Argo CD Check ==="

# Argo CD Pods
kubectl get pods -n argocd --no-headers | awk '{print $1 " - " $3}'

# Vault Pod
kubectl get pods -n vault --no-headers | awk '{print $1 " - " $3}'

# Applications
kubectl get applications -n argocd --no-headers | awk '{print $1 " - " $2 " - " $3}'

echo "=== Check Complete ==="
```

진행 조건:
- Argo CD Pod 모두 Running
- Vault Pod Running (0/1 정상)
- 모든 Application Synced
- cloudflared, ghost만 Degraded

---

## 트러블슈팅

### 1. Argo CD Pod Pending

```bash
kubectl describe pod -n argocd <pod-name>

# Events 확인:
# - Insufficient cpu/memory → VM 리소스 부족
# - Failed to pull image → 네트워크 문제
```

### 2. Root App OutOfSync

```bash
# 자동 동기화 대기 (3분) 또는 수동 동기화
kubectl patch application blogstack-root -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'
```

### 3. Git URL이 "your-org"로 되어 있음

```bash
# 1. Root App 삭제
kubectl delete application blogstack-root -n argocd

# 2. 모든 Git URL 확인
cd ~/blogstack-k8s
grep -r "your-org/blogstack-k8s" iac/ clusters/prod/

# 3. Git URL 변경 (CUSTOMIZATION.md 참조)
# 3개 파일 변경:
# - iac/argocd/root-app.yaml
# - clusters/prod/apps.yaml (6곳)
# - clusters/prod/project.yaml (1곳)

OLD_URL="https://github.com/your-org/blogstack-k8s"
NEW_URL="https://github.com/<본인계정>/blogstack-k8s"

sed -i "s|$OLD_URL|$NEW_URL|g" iac/argocd/root-app.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/apps.yaml
sed -i "s|$OLD_URL|$NEW_URL|g" clusters/prod/project.yaml

# 4. 확인
grep -r "your-org" iac/ clusters/prod/
# 출력 없으면 OK

# 5. Git commit & push
git add iac/ clusters/
git commit -m "Fix: Update Git URL to personal repository"
git push origin main

# 6. VM에서 pull
git pull origin main

# 7. Root App 재배포
kubectl apply -f ~/blogstack-k8s/iac/argocd/root-app.yaml
```

### 4. Helm Chart 다운로드 실패

```bash
# 네트워크 확인
curl -I https://prometheus-community.github.io/helm-charts

# OCI Security List: Egress 0.0.0.0/0, TCP/443 허용 필요

# DNS 확인
nslookup prometheus-community.github.io
```

### 5. ImagePullBackOff

```bash
# 네트워크 확인
curl -I https://registry.hub.docker.com

# 잠시 후 자동 재시도 대기
```

---

## Argo CD UI 접근 (선택)

### Port-forward 설정

VM:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

로컬 PC:
```bash
ssh -L 8080:localhost:8080 -i ~/.ssh/oci_key ubuntu@<VM_IP>
```

브라우저: `https://localhost:8080`
- Username: `admin`
- Password: `cat ~/argocd-password.txt`

---

## 다음 단계

Argo CD 설치 완료

현재 상태:
- Argo CD 설치 완료
- 모든 Application 배포 (Synced)
- Vault Pod Running (Sealed)
- cloudflared, ghost 시크릿 대기 중 (정상)

다음: [03-vault-setup.md](./03-vault-setup.md) - Vault 초기화 및 시크릿 입력 (15분)

---

## 부록: 빠른 설치 스크립트

재설치 또는 테스트 환경 구축 시 사용:

```bash
cd ~/blogstack-k8s

# Git URL 확인 (중요)
grep -r "your-org" iac/ clusters/prod/
# 출력 없어야 함

# 스크립트 실행
chmod +x ./scripts/bootstrap.sh
./scripts/bootstrap.sh
```

주의: 처음 설치 시 수동 설치 권장 (학습, 디버깅 용이)

---

## 참고

- [Argo CD 공식 문서](https://argo-cd.readthedocs.io/)
- [App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
