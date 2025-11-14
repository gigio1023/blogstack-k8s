# 01. 인프라 설치 (k3s)

Oracle Cloud ARM64 VM에 k3s Kubernetes 클러스터 설치

## 개요

k3s 선택 이유:
- 경량: 단일 바이너리, 최소 리소스 (~100MB)
- ARM64 네이티브 지원
- 기본 컴포넌트 포함: Local Path Provisioner, CoreDNS
- CNCF 인증

예상 소요 시간: 5분

## 전제 조건

- CUSTOMIZATION.md 완료 (Git URL, 도메인 설정 및 Push)
- VM SSH 접속 가능
- VM 디스크 여유 50GB 이상

## 설치 단계

### 1. VM 접속 및 확인

```bash
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>

uname -m  # aarch64 확인
df -h     # 디스크 여유 확인
free -h   # 메모리 확인
```

### 2. 시스템 업데이트

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git jq
```

### 3. k3s 설치

```bash
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --write-kubeconfig-mode 644
```

옵션:
- `--disable traefik`: Ingress-NGINX 사용
- `--write-kubeconfig-mode 644`: sudo 없이 kubectl 사용

### 4. 설치 확인

#### k3s 서비스

```bash
sudo systemctl status k3s
# Active: active (running) 확인
```

#### kubectl 접근

```bash
kubectl get nodes
# STATUS: Ready 확인
```

예상 출력:
```
NAME       STATUS   ROLES                  AGE   VERSION
instance   Ready    control-plane,master   1m    v1.28.5+k3s1
```

#### 시스템 Pod

```bash
kubectl get pods -n kube-system
# 모두 Running 또는 Completed
```

### 5. StorageClass 확인

```bash
kubectl get storageclass
# local-path (default) 확인
```

k3s Local Path Provisioner:
- 자동 볼륨 할당
- 경로: `/var/lib/rancher/k3s/storage/`
- Single-node 최적

스토리지 용량 확인:
```bash
df -h /var/lib/rancher/k3s/storage
# 최소 50GB 여유 권장
```

## 로컬 kubeconfig 설정 (선택)

로컬에서 클러스터 접근:

```bash
# VM에서 kubeconfig 복사
scp -i ~/.ssh/oci_key ubuntu@<VM_IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/config-oci

# server IP 변경
sed -i 's/127.0.0.1/<VM_PUBLIC_IP>/' ~/.kube/config-oci

# 환경변수 설정
export KUBECONFIG=~/.kube/config-oci

# 확인
kubectl get nodes
```

## 트러블슈팅

### k3s 서비스 시작 실패

```bash
# 로그 확인
sudo journalctl -u k3s -n 50 --no-pager

# 일반 원인: 메모리 부족, 디스크 부족, 네트워크 문제

# 재시작
sudo systemctl restart k3s
```

### kubectl 권한 오류

```bash
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
```

### Node NotReady

```bash
kubectl describe node <NODE_NAME>
# CNI 초기화 대기 (2-3분)
```

### 포트 충돌 (6443)

```bash
sudo netstat -tulpn | grep 6443

# k3s 제거 후 재설치 (다른 포트)
/usr/local/bin/k3s-uninstall.sh

curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --https-listen-port 6444 \
  --write-kubeconfig-mode 644
```

### ImagePullBackOff

```bash
kubectl describe pod <POD_NAME> -n kube-system

# 네트워크 확인
curl -I https://registry.k8s.io
curl -I https://docker.io

# OCI Security List: Egress 0.0.0.0/0:443 필요
```

## 완료 확인

```bash
echo "=== k3s 설치 확인 ==="

# k3s 서비스
sudo systemctl is-active k3s

# Node 상태
kubectl get nodes --no-headers | awk '{print $2}'
# Ready 출력

# 시스템 Pod
kubectl get pods -n kube-system --no-headers | awk '{print $1 " " $3}'
# Running 확인

# StorageClass
kubectl get storageclass --no-headers | wc -l
# 1 출력

echo "=== 완료 ==="
```

## 다음 단계

k3s 설치 완료

→ [02-argocd-setup.md](./02-argocd-setup.md) - Argo CD 설치 및 App-of-Apps 배포
