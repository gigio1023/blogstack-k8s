# 01. Infrastructure Setup (k3s)

Install k3s Kubernetes cluster on Oracle Cloud ARM64 VM

## Overview

Why k3s:
- Lightweight: single binary, minimal resources (~100MB)
- Native ARM64 support
- Batteries included: Local Path Provisioner, CoreDNS
- CNCF certified

Expected time: 5 minutes

## Prerequisites

- CUSTOMIZATION.md completed (Git URL, domain config pushed)
- VM SSH access
- VM disk space 50GB+ available

## Installation

### 1. Connect & Check

```bash
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>

uname -m  # aarch64
df -h     # disk space
free -h   # memory
```

### 2. System Update

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git jq
```

### 3. Install k3s

```bash
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --write-kubeconfig-mode 644
```

Options:
- `--disable traefik`: Using ingress-nginx instead
- `--write-kubeconfig-mode 644`: kubectl without sudo

### 4. Verify

#### k3s Service

```bash
sudo systemctl status k3s
# Active: active (running)
```

#### kubectl Access

```bash
kubectl get nodes
# STATUS: Ready
```

Expected output:
```
NAME       STATUS   ROLES                  AGE   VERSION
instance   Ready    control-plane,master   1m    v1.28.5+k3s1
```

#### System Pods

```bash
kubectl get pods -n kube-system
# All Running or Completed
```

### 5. Check StorageClass

```bash
kubectl get storageclass
# local-path (default)
```

k3s Local Path Provisioner:
- Auto volume provisioning
- Path: `/var/lib/rancher/k3s/storage/`
- Optimized for single-node

Check storage:
```bash
df -h /var/lib/rancher/k3s/storage
# Recommend 50GB+ free
```

## Local kubeconfig (Optional)

Access cluster from local machine:

```bash
# Copy kubeconfig from VM
scp -i ~/.ssh/oci_key ubuntu@<VM_IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/config-oci

# Update server IP
sed -i 's/127.0.0.1/<VM_PUBLIC_IP>/' ~/.kube/config-oci

# Set env
export KUBECONFIG=~/.kube/config-oci

# Verify
kubectl get nodes
```

## Troubleshooting

### k3s Service Failed

```bash
# Check logs
sudo journalctl -u k3s -n 50 --no-pager

# Common causes: out of memory, disk full, network issues

# Restart
sudo systemctl restart k3s
```

### kubectl Permission Denied

```bash
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
```

### Node NotReady

```bash
kubectl describe node <NODE_NAME>
# Wait for CNI init (2-3 min)
```

### Port Conflict (6443)

```bash
sudo netstat -tulpn | grep 6443

# Reinstall with different port
/usr/local/bin/k3s-uninstall.sh

curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --https-listen-port 6444 \
  --write-kubeconfig-mode 644
```

### ImagePullBackOff

```bash
kubectl describe pod <POD_NAME> -n kube-system

# Check network
curl -I https://registry.k8s.io
curl -I https://docker.io

# OCI Security List: Egress 0.0.0.0/0:443 required
```

## Verify Installation

```bash
echo "=== k3s Check ==="

# Service
sudo systemctl is-active k3s

# Node
kubectl get nodes --no-headers | awk '{print $2}'
# Ready

# System pods
kubectl get pods -n kube-system --no-headers | awk '{print $1 " " $3}'
# Running

# StorageClass
kubectl get storageclass --no-headers | wc -l
# 1

echo "=== Done ==="
```

## Next Steps

k3s installation complete

→ [02-argocd-setup.md](./02-argocd-setup.md) - Argo CD & App-of-Apps deployment
