# 08. 운영 가이드

일상 운영, 모니터링, 유지보수

## 서비스 접근

### Ghost Admin

- URL: `https://yourdomain.com/ghost`
- Cloudflare Zero Trust Access 인증 (설정한 경우)

### Grafana

```bash
kubectl port-forward -n observers svc/kube-prometheus-stack-grafana 3000:80 &
# http://localhost:3000
# admin / admin (기본값)
```

### Argo CD

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443 &
# https://localhost:8080
```

## 모니터링

### Prometheus Targets

```bash
kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090 &
# http://localhost:9090/targets
```

확인 대상:
- ingress-nginx (포트 10254)
- cloudflared (포트 2000)
- vault (sys/metrics)
- blackbox/blog-external (외부 헬스체크)

### Grafana 대시보드

기본 제공:
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace (Pods)
- NGINX Ingress Controller

커스텀 대시보드 추가:
1. Grafana → Dashboards → Import
2. ID 입력: `7587` (nginx), `11159` (Cloudflare), `12904` (Vault)

### 외부 헬스체크

```promql
probe_success{job="blog-external"}
# 1: 정상, 0: 장애
```

### 로그 확인 (Loki)

Grafana → Explore → Loki

```logql
# Ghost 로그
{namespace="blog", app="ghost"}

# MySQL 에러
{namespace="blog", app="mysql"} |= "error"

# Cloudflared
{namespace="cloudflared"}
```

## 일반 문제 해결

### Ghost 로그인 루프

원인: X-Forwarded-Proto 미전달

```bash
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o jsonpath='{.data.use-forwarded-headers}'
# true 확인

kubectl get ingress -n blog ghost -o jsonpath='{.spec.ingressClassName}'
# nginx 확인
```

### Pod CrashLoopBackOff

```bash
kubectl get pods -A | grep -v Running | grep -v Completed
kubectl logs -n <namespace> <pod-name> --tail=50

# 이전 컨테이너 로그
kubectl logs -n <namespace> <pod-name> --previous
```

### 502 Bad Gateway

```bash
kubectl get pods -n blog
kubectl get ingress -n blog
kubectl describe ingress ghost -n blog

# Ghost 헬스체크
kubectl exec -n blog deployment/ghost -- wget -qO- http://localhost:2368
```

### CreateContainerConfigError

```bash
kubectl describe pod <pod-name> -n <namespace>
# Events: Secret "xxx" not found

# Vault 확인
kubectl get pods -n vault
vault kv list kv/blog/prod

# VSO 재시작
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
```

## 업데이트

### 시스템 패키지

```bash
ssh ubuntu@<VM_IP>
sudo apt update && sudo apt upgrade -y
```

### kubectl 플러그인

```bash
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## 백업

### MySQL 수동 백업

```bash
kubectl exec -n blog mysql-0 -- mysqldump -u root -p$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.root_password}' | base64 -d) --all-databases > backup.sql
```

### Ghost 컨텐츠 백업

```bash
kubectl cp blog/ghost-xxx:/var/lib/ghost/content ./ghost-content-backup
```

### 백업 자동화

자세한 설정: `apps/ghost/optional/README.md`

## Git 동기화

### 변경 사항 Pull

```bash
cd ~/blogstack-k8s
git pull origin main

# Argo CD 자동 동기화 (3분 대기)
kubectl get applications -n argocd
```

### 수동 동기화

```bash
kubectl patch application <app-name> -n argocd \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}' --type merge
```

## Vault 관리

### 토큰 갱신

```bash
export VAULT_TOKEN=$(jq -r .root_token ~/blogstack-k8s/security/vault/init-scripts/init-output.json)
```

### 시크릿 수정

```bash
kubectl port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR=http://127.0.0.1:8200

vault kv patch kv/blog/prod/ghost \
  url="https://newdomain.com"
```

### Unseal (재부팅 후)

```bash
kubectl exec -n vault vault-0 -- vault operator unseal <KEY1>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY2>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY3>
```

## 리소스 사용량

### 클러스터 전체

```bash
kubectl top nodes
kubectl top pods -A --sort-by=memory
kubectl top pods -A --sort-by=cpu
```

### 네임스페이스별

```bash
kubectl top pods -n blog
kubectl top pods -n observers
```

## SMTP 설정 변경

자세한 설정: docs/07-smtp-setup.md

```bash
vault kv patch kv/blog/prod/ghost \
  mail__from="'New Name' <newemail@yourdomain.com>"

kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
kubectl rollout restart deployment ghost -n blog
```

## Cloudflare Tunnel 변경

```bash
# 새 Token 생성 (Cloudflare Dashboard)
vault kv patch kv/blog/prod/cloudflared token="NEW_TOKEN"

kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
kubectl rollout restart deployment cloudflared -n cloudflared
```

## 전체 재시작

```bash
cd ~/blogstack-k8s
./scripts/quick-reset.sh
```

자세한 방법: RESET.md
