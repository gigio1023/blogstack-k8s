# 01. 인프라 설치 (k3s)

Oracle Cloud ARM64 VM에 k3s Kubernetes 클러스터를 설치합니다.

---

## ℹ️ k3s 선택 이유

- **경량**: 단일 바이너리, 최소 리소스 사용 (~100MB)
- **ARM64 네이티브 지원**: Oracle ARM64 최적화
- **기본 컴포넌트 포함**: 
  - Local Path Provisioner (PVC 자동 지원)
  - CoreDNS
  - Traefik Ingress Controller (우리는 nginx로 교체)
- **프로덕션 ready**: CNCF 인증, 엔터프라이즈 사용

---

## 📋 전제 조건

- [x] **CUSTOMIZATION.md** 완료 (Git URL, 도메인 설정 및 Push)
- [x] VM에 SSH 접속 가능
- [x] VM 디스크 여유 공간 50GB 이상

---

## 🚀 설치 단계

### 1. VM 접속 및 준비

```bash
# VM에 SSH 접속
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>

# 시스템 정보 확인
echo "=== System Information ==="
uname -m  # aarch64 확인
df -h     # 디스크 여유 확인
free -h   # 메모리 확인
```

**예상 출력:**
```
=== System Information ===
aarch64
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        97G  5.2G   87G   6% /
Mem:           23Gi  1.2Gi   20Gi
```

---

### 2. 시스템 업데이트

```bash
# 패키지 업데이트
sudo apt update && sudo apt upgrade -y

# 필요한 도구 설치
sudo apt install -y curl git jq

# 완료 확인
echo "✅ System update complete"
```

**예상 소요 시간**: 2-3분

---

### 3. k3s 설치

```bash
# k3s 설치 스크립트 실행
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --write-kubeconfig-mode 644

# 설치 진행 상황 확인
echo "⏳ Installing k3s..."
```

**옵션 설명:**
- `--disable traefik`: Ingress-NGINX를 사용하므로 Traefik 비활성화
- `--write-kubeconfig-mode 644`: kubeconfig 읽기 권한 부여 (sudo 없이 kubectl 사용 가능)

**예상 소요 시간**: 1-2분

**설치 중 출력 예시:**
```
[INFO]  Finding release for channel stable
[INFO]  Using v1.28.5+k3s1 as release
[INFO]  Downloading hash https://github.com/k3s-io/k3s/releases/download/v1.28.5+k3s1/sha256sum-arm64.txt
[INFO]  Downloading binary https://github.com/k3s-io/k3s/releases/download/v1.28.5+k3s1/k3s-arm64
[INFO]  Verifying binary download
[INFO]  Installing k3s to /usr/local/bin/k3s
[INFO]  Skipping installation of SELinux RPM
[INFO]  Creating /usr/local/bin/kubectl symlink to k3s
[INFO]  Creating /usr/local/bin/crictl symlink to k3s
[INFO]  Creating /usr/local/bin/ctr symlink to k3s
[INFO]  Creating killall script /usr/local/bin/k3s-killall.sh
[INFO]  Creating uninstall script /usr/local/bin/k3s-uninstall.sh
[INFO]  env: Creating environment file /etc/systemd/system/k3s.service.env
[INFO]  systemd: Creating service file /etc/systemd/system/k3s.service
[INFO]  systemd: Enabling k3s unit
Created symlink /etc/systemd/system/multi-user.target.wants/k3s.service → /etc/systemd/system/k3s.service.
[INFO]  systemd: Starting k3s
```

---

### 4. 설치 확인

#### 4.1. k3s 서비스 상태 확인

```bash
# k3s 서비스 상태
sudo systemctl status k3s

# 예상 출력: active (running)
```

**예상 출력:**
```
● k3s.service - Lightweight Kubernetes
     Loaded: loaded (/etc/systemd/system/k3s.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2024-11-04 10:00:00 UTC; 30s ago
       Docs: https://k3s.io
   Main PID: 12345 (k3s-server)
      Tasks: 50
     Memory: 512.0M
        CPU: 5.123s
     CGroup: /system.slice/k3s.service
             └─12345 /usr/local/bin/k3s server --disable traefik --write-kubeconfig-mode 644
```

> ✅ **확인**: `Active: active (running)` 이어야 함

#### 4.2. kubectl 접근 확인

```bash
# kubectl 명령 테스트 (sudo 없이)
kubectl get nodes

# 예상 출력:
# NAME       STATUS   ROLES                  AGE   VERSION
# instance-1 Ready    control-plane,master   1m    v1.28.5+k3s1
```

**실제 출력 예시:**
```
NAME                 STATUS   ROLES                  AGE   VERSION
instance-20241104    Ready    control-plane,master   45s   v1.28.5+k3s1
```

> ✅ **확인**: STATUS가 `Ready` 이어야 함

#### 4.3. 기본 네임스페이스 확인

```bash
# 네임스페이스 목록
kubectl get namespaces

# 예상 출력:
# NAME              STATUS   AGE
# default           Active   1m
# kube-system       Active   1m
# kube-public       Active   1m
# kube-node-lease   Active   1m
```

#### 4.4. 시스템 Pod 확인

```bash
# kube-system Pod 상태
kubectl get pods -n kube-system

# 예상 출력: 모두 Running 또는 Completed 상태
```

**예상 출력:**
```
NAME                                      READY   STATUS      RESTARTS   AGE
coredns-5c69c9f4d8-abc12                  1/1     Running     0          2m
local-path-provisioner-7b7dc8d6f5-xyz34   1/1     Running     0          2m
metrics-server-84c8d9784-def56            1/1     Running     0          2m
helm-install-traefik-crd-abc12            0/1     Completed   0          2m
helm-install-traefik-xyz34                0/1     Completed   0          2m
```

> ⚠️ **참고**: traefik Pod는 `--disable traefik` 옵션으로 비활성화했지만, Helm install job은 남아있을 수 있습니다 (정상).

---

### 5. StorageClass 확인 (Local Path Provisioner)

k3s는 기본적으로 Local Path Provisioner를 제공합니다.

```bash
# StorageClass 확인
kubectl get storageclass

# 예상 출력:
# NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
# local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  3m
```

**특징:**
- PVC 생성 시 자동으로 로컬 디렉토리에 볼륨 할당
- 기본 경로: `/var/lib/rancher/k3s/storage/`
- Single-node 환경에 최적

**스토리지 용량 확인:**
```bash
# 디스크 사용량
df -h /var/lib/rancher/k3s/storage

# 예상 출력:
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/sda1        97G  5.5G   87G   6% /
```

> ✅ **권장**: 최소 50GB 여유 공간

### 5. kubeconfig 설정 (로컬 개발용)

로컬 머신에서 원격 클러스터 접근:

```bash
# VM에서 kubeconfig 복사
scp -i ~/.ssh/oci_key ubuntu@<VM_IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/config-oci

# 로컬에서 server IP 변경
sed -i 's/127.0.0.1/<VM_PUBLIC_IP>/' ~/.kube/config-oci

# KUBECONFIG 환경변수 설정
export KUBECONFIG=~/.kube/config-oci

# 확인
kubectl get nodes
```

## Local Path Provisioner 확인

k3s는 기본적으로 Local Path Provisioner를 제공합니다.

```bash
# StorageClass 확인
kubectl get storageclass

# 예상 출력:
# NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
# local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer
```

**특징:**
- PVC 생성 시 자동으로 로컬 디렉토리에 볼륨 할당
- 기본 경로: `/var/lib/rancher/k3s/storage/`
- Single-node 환경에 최적

## 스토리지 용량 확인

```bash
# 디스크 사용량
df -h /var/lib/rancher/k3s/storage

# 권장: 최소 50GB 여유 공간
```

## 네임스페이스 사전 생성 (선택)

Argo CD가 자동 생성하지만, 수동으로도 가능:

```bash
kubectl create namespace argocd
kubectl create namespace blog
kubectl create namespace observers
kubectl create namespace vault
kubectl create namespace vso
kubectl create namespace cloudflared
kubectl create namespace ingress-nginx
```

## 리소스 제한 설정 (선택)

### LimitRange (네임스페이스별 기본값)

```yaml
# limitrange.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: blog
spec:
  limits:
  - default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
```

```bash
kubectl apply -f limitrange.yaml
```

---

## 🔧 트러블슈팅

### ❌ 문제 1: k3s 서비스 시작 실패

**증상:**
```bash
sudo systemctl status k3s
# Active: failed (Result: exit-code)
```

**해결 방법:**

```bash
# 1. 로그 확인
sudo journalctl -u k3s -n 50 --no-pager

# 2. 일반적인 원인: 메모리 부족
free -h

# 3. k3s 재시작
sudo systemctl restart k3s

# 4. 상태 재확인
sudo systemctl status k3s
```

**근본 원인:**
- 메모리 부족 (최소 2GB 필요)
- 디스크 공간 부족
- 네트워크 연결 문제 (이미지 다운로드 실패)

---

### ❌ 문제 2: kubectl 권한 오류

**증상:**
```bash
kubectl get nodes
# error: error loading config file "/etc/rancher/k3s/k3s.yaml": open /etc/rancher/k3s/k3s.yaml: permission denied
```

**해결 방법:**

```bash
# kubeconfig 권한 수정
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# 확인
kubectl get nodes
```

---

### ❌ 문제 3: Node 상태가 NotReady

**증상:**
```bash
kubectl get nodes
# NAME       STATUS     ROLES                  AGE   VERSION
# instance   NotReady   control-plane,master   2m    v1.28.5+k3s1
```

**해결 방법:**

```bash
# 1. Node 상세 정보 확인
kubectl describe node <NODE_NAME>

# 2. 일반적인 원인: CNI 플러그인 초기화 대기 중
# 2-3분 대기 후 재확인
kubectl get nodes
```

---

### ❌ 문제 4: 포트 충돌 (6443)

k3s API 서버가 6443 포트를 사용. 충돌 시:

**증상:**
```bash
sudo journalctl -u k3s -n 20
# bind: address already in use
```

**해결 방법:**

```bash
# 1. 6443 포트 사용 중인 프로세스 확인
sudo netstat -tulpn | grep 6443

# 2. k3s 제거 후 재설치 (포트 변경)
/usr/local/bin/k3s-uninstall.sh

curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --https-listen-port 6444 \
  --write-kubeconfig-mode 644
```

---

### ❌ 문제 5: 이미지 Pull 실패

**증상:**
```bash
kubectl get pods -n kube-system
# NAME                   READY   STATUS         RESTARTS   AGE
# coredns-xxx            0/1     ImagePullBackOff   0       2m
```

**해결 방법:**

```bash
# 1. Pod 상세 정보 확인
kubectl describe pod <POD_NAME> -n kube-system

# 2. 네트워크 연결 확인
curl -I https://registry.k8s.io
curl -I https://docker.io

# 3. k3s 재시작
sudo systemctl restart k3s

# 4. OCI Security List 확인
# Egress Rule에 0.0.0.0/0:443 허용 확인
```

---

### ❌ 문제 6: kubeconfig 파일 없음

**증상:**
```bash
kubectl get nodes
# The connection to the server localhost:8080 was refused
```

**해결 방법:**

```bash
# 1. kubeconfig 파일 확인
ls -la /etc/rancher/k3s/k3s.yaml

# 2. KUBECONFIG 환경변수 설정
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 3. 영구 설정 (선택)
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
source ~/.bashrc
```

---

## ✅ 완료 확인

모든 항목이 ✅ 이어야 다음 단계로 진행 가능:

```bash
# 종합 확인 스크립트
echo "=== k3s Installation Check ==="

# 1. k3s 서비스
echo -n "k3s Service: "
sudo systemctl is-active k3s

# 2. Node 상태
echo -n "Node Status: "
kubectl get nodes --no-headers | awk '{print $2}'

# 3. 시스템 Pod
echo "System Pods:"
kubectl get pods -n kube-system --no-headers | awk '{print $1 " " $3}'

# 4. StorageClass
echo -n "StorageClass: "
kubectl get storageclass --no-headers | wc -l

echo "=== Check Complete ==="
```

**예상 출력:**
```
=== k3s Installation Check ===
k3s Service: active
Node Status: Ready
System Pods:
coredns-xxx Running
local-path-provisioner-xxx Running
metrics-server-xxx Running
StorageClass: 1
=== Check Complete ===
```

---

## 📚 다음 단계

k3s 설치가 완료되었습니다! 🎉

이제 GitOps를 위한 Argo CD를 설치합니다:

**👉 [02-argocd-setup.md](./02-argocd-setup.md)** - Argo CD 설치 및 App-of-Apps 배포 (10분)

