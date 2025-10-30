# 01. 인프라 설치 (k3s)

Oracle Cloud ARM64 VM에 k3s Kubernetes 클러스터를 설치합니다.

## k3s 선택 이유

- **경량**: 단일 바이너리, 최소 리소스 사용
- **ARM64 네이티브 지원**
- **기본 컴포넌트 포함**: 
  - Local Path Provisioner (PVC 자동 지원)
  - CoreDNS
  - Traefik Ingress Controller (우리는 nginx로 교체)
- **프로덕션 ready**: CNCF 인증

## 설치

### 1. VM 접속

```bash
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>
```

### 2. 시스템 업데이트

```bash
sudo apt update && sudo apt upgrade -y
```

### 3. k3s 설치

```bash
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --write-kubeconfig-mode 644
```

**옵션 설명:**
- `--disable traefik`: Ingress-NGINX를 사용하므로 Traefik 비활성화
- `--write-kubeconfig-mode 644`: kubeconfig 읽기 권한 부여

### 4. 설치 확인

```bash
# k3s 서비스 상태
sudo systemctl status k3s

# 노드 확인
kubectl get nodes

# 예상 출력:
# NAME       STATUS   ROLES                  AGE   VERSION
# vm-node    Ready    control-plane,master   1m    v1.28.x+k3s1
```

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

## 트러블슈팅

### k3s 시작 실패

```bash
# 로그 확인
sudo journalctl -u k3s -f

# 재시작
sudo systemctl restart k3s
```

### kubectl 권한 오류

```bash
# kubeconfig 권한 수정
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
```

### 포트 충돌 (6443)

k3s API 서버가 6443 포트를 사용. 충돌 시:

```bash
# 다른 서비스 확인
sudo netstat -tulpn | grep 6443

# k3s 재설치 (포트 변경)
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --https-listen-port 6444
```

## 다음 단계

k3s 설치가 완료되었습니다. 이제 Argo CD를 설치하여 GitOps 파이프라인을 구성합니다.

다음: [02-argocd-setup.md](./02-argocd-setup.md)

