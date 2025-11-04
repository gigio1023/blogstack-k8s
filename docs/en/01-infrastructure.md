# 01. Infrastructure Setup

k3s installation and configuration on OCI ARM64 VM.

---

## Prerequisites

- OCI VM created (ARM64, Ubuntu 22.04, 4 OCPU, 24GB RAM)
- SSH access to VM
- VM outbound 443/tcp allowed

---

## Install k3s

### 1. SSH into VM

```bash
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>
```

### 2. Update System

```bash
sudo apt update
sudo apt upgrade -y
```

### 3. Install k3s

```bash
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --write-kubeconfig-mode 644
```

Installation time: Approximately 1-2 minutes

### 4. Verify Installation

```bash
# Check k3s service
sudo systemctl status k3s

# Check node
kubectl get nodes

# Expected output:
# NAME       STATUS   ROLES                  AGE   VERSION
# instance   Ready    control-plane,master   1m    v1.28.x+k3s1
```

### 5. Verify kubectl Access

```bash
# Without sudo
kubectl get pods -A

# Expected: List of kube-system pods
```

If kubectl requires sudo:

```bash
# Method 1: Copy kubeconfig (recommended)
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Method 2: Set permission
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# Verify
kubectl get nodes  # No sudo required
```

---

## System Configuration

### 1. Check Resources

```bash
# CPU
nproc
# Expected: 4

# Memory
free -h
# Expected: ~24GB total

# Disk
df -h /
# Expected: Minimum 50GB available
```

### 2. Verify Network

```bash
# External connectivity
curl -I https://github.com
curl -I https://registry.hub.docker.com

# Expected: HTTP/2 200 or 3xx
```

### 3. Check k3s Components

```bash
kubectl get pods -n kube-system

# Expected pods:
# - coredns
# - local-path-provisioner
# - metrics-server
```

---

## Storage Configuration

k3s includes Local Path Provisioner by default.

### Verify Default StorageClass

```bash
kubectl get storageclass

# Expected output:
# NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
# local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer
```

### Test PVC Creation

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
EOF

# Check status
kubectl get pvc test-pvc

# Delete test
kubectl delete pvc test-pvc
```

---

## Verification

Run verification check:

```bash
echo "=== k3s Installation Check ==="

# 1. Node Status
kubectl get nodes

# 2. System Pods
kubectl get pods -n kube-system

# 3. StorageClass
kubectl get storageclass

# 4. Resource Usage
kubectl top nodes 2>/dev/null || echo "Metrics not yet available (normal)"

echo "=== Check Complete ==="
```

Expected conditions:
- Node Status: Ready
- All kube-system pods: Running
- StorageClass: local-path exists
- kubectl works without sudo

---

## Troubleshooting

### 1. k3s Service Failed to Start

```bash
# Check logs
sudo journalctl -u k3s -f

# Common causes:
# - Port 6443 already in use
# - Insufficient resources
```

### 2. kubectl Permission Denied

```bash
# Symptom
kubectl get nodes
# Error: permission denied

# Solution: Copy kubeconfig
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
```

### 3. Node Not Ready

```bash
# Check node status
kubectl describe node

# Check k3s logs
sudo journalctl -u k3s --since "10 minutes ago"

# Restart k3s
sudo systemctl restart k3s
```

### 4. Port Conflict

```bash
# Check if port 6443 in use
sudo netstat -tulpn | grep 6443

# If conflict, uninstall and reinstall
/usr/local/bin/k3s-uninstall.sh
# Then reinstall k3s
```

### 5. Image Pull Failure

```bash
# Symptom: Pods stuck in ImagePullBackOff

# Check network
curl -I https://registry.hub.docker.com

# Verify OCI Security List: Egress 0.0.0.0/0, TCP/443 allowed
```

---

## k3s Management

### Start/Stop/Restart

```bash
# Stop
sudo systemctl stop k3s

# Start
sudo systemctl start k3s

# Restart
sudo systemctl restart k3s

# Status
sudo systemctl status k3s
```

### Uninstall (if needed)

```bash
/usr/local/bin/k3s-uninstall.sh
```

---

## Resource Limits

Recommended resource allocation:

| Component | CPU | Memory |
|-----------|-----|--------|
| k3s system | 0.5 OCPU | 1GB |
| Argo CD | 0.3 OCPU | 512MB |
| Vault | 0.2 OCPU | 256MB |
| Ghost + MySQL | 0.5 OCPU | 1GB |
| Observers | 1.0 OCPU | 2GB |
| **Reserve** | 1.5 OCPU | 19GB |

---

## Next Steps

k3s installation complete.

Current state:
- k3s running
- kubectl access configured
- Storage provisioner ready

Next: [02-argocd-setup.md](./02-argocd-setup.md) - Install Argo CD (15 min)

---

## References

- [k3s Official Documentation](https://docs.k3s.io/)
- [k3s Installation Options](https://docs.k3s.io/installation/configuration)
- [Local Path Provisioner](https://github.com/rancher/local-path-provisioner)

