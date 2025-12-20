# Applications 재시작

Argo CD Applications 재시작 절차

## 언제 사용하나요?

- Applications이 OutOfSync에서 벗어나지 못할 때
- Manifest를 수정한 후 깔끔하게 다시 배포하고 싶을 때
- 에러가 계속 발생해서 처음부터 다시 시작하고 싶을 때

---

## 빠른 재시작 (권장)

### 자동 스크립트 사용

```bash
# 프로젝트 디렉토리에서 실행
cd ~/blogstack-k8s
./scripts/quick-reset.sh
```

---

## 수동 재시작

스크립트 없이 직접 실행:

### 1. 프로젝트 디렉토리로 이동

```bash
cd ~/blogstack-k8s
```

### 2. 최신 코드 가져오기

```bash
git pull origin main
```

### 3. Root App 삭제

```bash
# Root App 삭제 (child applications도 자동 삭제됨)
kubectl delete application blogstack-root -n argocd
```

**참고**: 이 명령은 Applications만 삭제합니다. 실제 워크로드(Pod, Service 등)는 약간의 시간이 걸려 삭제됩니다.

### 4. 삭제 확인 (선택)

```bash
# Applications가 모두 사라질 때까지 대기
kubectl get applications -n argocd
# blogstack-root만 있거나, 아무것도 없으면 OK
```

### 5. Root App 재배포

```bash
kubectl apply -f iac/argocd/root-app.yaml
```

### 6. 자동 배포 모니터링

```bash
# 실시간 모니터링
watch -n 5 kubectl get applications -n argocd
```

**배포 순서** (자동 진행):
1. Wave -2 (3~5분): observers
2. Wave -1 (1~2분): ingress-nginx
3. Wave 0~1 (2~3분): cloudflared, vault
4. Wave 2~3 (1~2분): vso-operator, vso-resources
5. Wave 4 (2~3분): ghost

**최종 예상 상태** (10분 후):
```
NAME               SYNC STATUS   HEALTH STATUS
blogstack-root     Synced        Healthy
observers          Synced        Healthy
ingress-nginx      Synced        Healthy
cloudflared        Synced        Degraded      ⚠️ 정상 (Vault 시크릿 대기)
vault              Synced        Healthy       (0/1 Sealed 정상)
vso-operator       Synced        Healthy
vso-resources      Synced        Healthy
ghost              Synced        Degraded      ⚠️ 정상 (Vault 시크릿 대기)
```

---

## 트러블슈팅

### 1. Applications가 삭제되지 않음

**증상:**
```bash
kubectl delete application blogstack-root -n argocd
# 명령이 멈춤
```

**해결:**
```bash
# 강제 삭제
kubectl delete application blogstack-root -n argocd --grace-period=0 --force
```

### 2. Child applications가 생성되지 않음

**증상:**
```bash
kubectl get applications -n argocd
# blogstack-root만 있고 다른 applications가 안 보임
```

**원인**: AppProject가 없거나 Git URL 문제

**해결:**
```bash
# AppProject 확인
kubectl get appproject blog -n argocd

# 없으면 생성
kubectl apply -f clusters/prod/project.yaml

# Root App 재생성
kubectl delete application blogstack-root -n argocd
kubectl apply -f iac/argocd/root-app.yaml
```

### 3. Applications가 계속 OutOfSync

**원인**: 이전 operation이 retry 중

**해결:**
```bash
# 해당 application 삭제 후 재생성 (Root App이 자동 재생성)
kubectl delete application observers -n argocd

# 또는 모두 재생성
kubectl delete application blogstack-root -n argocd
sleep 10
kubectl apply -f iac/argocd/root-app.yaml
```

### 4. 워크로드가 완전히 삭제되지 않음

네임스페이스에 워크로드가 남아있으면:

```bash
# 특정 네임스페이스 삭제
kubectl delete namespace observers --grace-period=30

# 여러 네임스페이스 한번에
kubectl delete namespace observers blog vault vso cloudflared ingress-nginx --wait=false
```

**참고**: 네임스페이스 삭제는 필수가 아닙니다. Applications를 재배포하면 자동으로 정리됩니다.

---

## 완전 초기화 (극단적인 경우)

위 방법으로 해결되지 않을 때만 사용:

```bash
# 1. 모든 applications 삭제
kubectl delete application --all -n argocd

# 2. 네임스페이스 삭제
kubectl delete namespace observers blog vault vso cloudflared ingress-nginx

# 3. AppProject 재생성
kubectl delete appproject blog -n argocd
kubectl apply -f clusters/prod/project.yaml

# 4. Root App 재배포
kubectl apply -f iac/argocd/root-app.yaml
```

---

## FAQ

### Q: 데이터가 삭제되나요?

**A**: Applications 재시작만으로는 PVC 데이터가 삭제되지 않습니다. 
네임스페이스를 삭제하면 PVC도 삭제됩니다.

### Q: Vault를 다시 초기화해야 하나요?

**A**: 
- Applications만 재시작: Vault 데이터 유지, 재초기화 불필요
- 네임스페이스 삭제: Vault PVC 삭제됨, 재초기화 필요 ([03-vault-setup.md](./03-vault-setup.md), [07-smtp-setup.md](./07-smtp-setup.md))

### Q: 얼마나 자주 재시작해야 하나요?

**A**: 
- 정상 운영: 재시작 불필요 (automated sync 작동)
- Manifest 수정 후: Git push만 하면 자동 sync
- 에러 발생 시: 이 가이드 사용

---

## 참고

- [02-argocd-setup.md](./02-argocd-setup.md): 초기 설치 가이드
- [03-vault-setup.md](./03-vault-setup.md): Vault 초기화
- [07-smtp-setup.md](./07-smtp-setup.md): SMTP 이메일 설정
- [08-operations.md](./08-operations.md): 운영 가이드
