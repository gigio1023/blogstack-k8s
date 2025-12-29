# 09. 트러블슈팅

## Vault

### Pod CrashLoopBackOff

```bash
kubectl logs -n vault vault-0
kubectl get pvc -n vault
# Bound 확인
```

### Sealed 상태

```bash
kubectl exec -n vault vault-0 -- vault operator unseal <KEY1>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY2>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY3>
```

### Token 만료

```bash
export VAULT_TOKEN=$(jq -r .root_token ~/blogstack-k8s/security/vault/init-scripts/init-output.json)
```

## Ingress-nginx

### Ingress 생성 안됨 (x509 error)

```bash
CA=$(kubectl get secret ingress-nginx-admission -n ingress-nginx -o jsonpath='{.data.ca}')
kubectl patch validatingwebhookconfiguration ingress-nginx-admission \
  --type='json' \
  -p='[{"op": "add", "path": "/webhooks/0/clientConfig/caBundle", "value":"'$CA'"}]'

kubectl patch application ghost -n argocd \
  -p '{"operation": {"sync": {"revision": "HEAD"}}}' --type merge
```

## Cloudflared

### 배포 전 Docker 검증

```bash
TUNNEL_TOKEN=$(kubectl get secret cloudflared-token -n cloudflared -o jsonpath='{.data.token}' | base64 -d)
echo "Token length: ${#TUNNEL_TOKEN}"  # 184

docker run --rm docker.io/cloudflare/cloudflared:2025.10.0 \
  tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"
# Connection registered 출력
```

Metrics 포함:
```bash
docker run --rm -p 2000:2000 \
  -e TUNNEL_METRICS=0.0.0.0:2000 \
  docker.io/cloudflare/cloudflared:2025.10.0 \
  tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"

curl http://localhost:2000/metrics
```

### Pod CrashLoopBackOff

```bash
kubectl logs -n cloudflared -l app=cloudflared

# 일반 원인:
# - Token 오류
# - Tunnel 삭제됨 (Cloudflare Dashboard 확인)
```

## Ghost

### CrashLoopBackOff

```bash
kubectl logs -n blog deployment/ghost --tail=100

# 일반 원인:
# - MySQL 연결 실패
# - MySQL Service에 ready endpoint가 없음 (예: mysql-0 NotReady)
# - database__connection__password 불일치

# MySQL endpoint readiness 확인 (Service -> EndpointSlice)
kubectl get pod -n blog mysql-0
kubectl get endpointslice -n blog -l kubernetes.io/service-name=mysql

# mysql-exporter 시크릿 동기화 실패로 mysql-0가 NotReady인 경우
kubectl get secret -n blog mysql-exporter-secret
kubectl describe vaultstaticsecret -n blog mysql-exporter-secret

# MySQL 비밀번호 확인
kubectl get secret -n blog ghost-env -o jsonpath='{.data.database__connection__password}' | base64 -d
kubectl get secret -n blog mysql-secret -o jsonpath='{.data.password}' | base64 -d
# 두 값 동일해야 함
```

### 503 Service Unavailable

```bash
kubectl get pods -n blog
kubectl get ingress -n blog
kubectl describe ingress ghost -n blog
```

### "Failed to send email"

```bash
kubectl logs -n blog deployment/ghost | grep -i mail

# SMTP 설정 확인
kubectl get secret -n blog ghost-env -o jsonpath='{.data.mail__options__auth__pass}' | base64 -d

# Vault 확인
vault kv get -format=json kv/blog/prod/ghost | jq -r '.data.data | keys | .[]' | grep mail__
```

## MySQL

### Pod Pending

```bash
kubectl describe pod mysql-0 -n blog
# Events: PVC Bound 확인

kubectl get pvc -n blog
# STATUS: Bound
```

### 연결 실패

```bash
kubectl exec -n blog mysql-0 -- mysql \
  -u root \
  -p$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.root_password}' | base64 -d) \
  -e "SELECT 1;"
```

## Argo CD

### Application OutOfSync

```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd | grep -A 10 "Message:"

# 수동 동기화
kubectl patch application <app-name> -n argocd \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}' --type merge
```

### "project blog which does not exist"

```bash
kubectl apply -f ./clusters/prod/project.yaml
kubectl delete application blogstack-root -n argocd
kubectl apply -f ./iac/argocd/root-app.yaml
```

## 모니터링

### vmagent Targets가 비어 있음

```bash
# vmagent 설정 확인
kubectl get configmap -n observers vmagent-scrape -o yaml

# vmagent 로그 확인
kubectl logs -n observers deploy/vmagent
```

대상 서비스 확인:
```bash
kubectl get svc -n blog mysql-exporter
kubectl get svc -n ingress-nginx
kubectl get svc -n cloudflared
kubectl get svc -n vault
```

### Grafana 데이터 없음

1. 데이터소스 확인: Configuration → Data Sources → VictoriaMetrics → Save & Test
2. vmsingle 접근 확인:
   ```bash
   kubectl port-forward -n observers svc/vmsingle 8428:8428 &
   # http://localhost:8428/vmui
   ```

### Blackbox 응답 실패

1. vmagent 설정의 blackbox targets 확인
2. blackbox-exporter 상태 확인:
   ```bash
   kubectl get pods -n observers -l app.kubernetes.io/instance=blackbox-exporter
   ```

## VSO

### Secret 생성 안됨

```bash
kubectl get vaultstaticsecret -n vso
kubectl describe vaultstaticsecret <name> -n vso

# VSO 재시작
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator

# 30초 후 확인
kubectl get secrets -n blog
```

## 네트워크

### 외부 접근 실패

```bash
# DNS 확인
dig yourdomain.com +short

# Cloudflare Tunnel 확인
kubectl logs -n cloudflared -l app=cloudflared | grep "Connection registered"

# Ingress 확인
kubectl get ingress -n blog

# Ghost Pod 확인
kubectl get pods -n blog
```

### 내부 DNS 실패

```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup mysql.blog.svc.cluster.local
```

## 디스크 공간

```bash
df -h /var/lib/rancher/k3s/storage
# 여유 공간 50GB 미만 시 정리 필요

# 미사용 이미지 정리
sudo k3s crictl rmi --prune
```

## 로그 수집

```bash
# 전체 Pod 상태
kubectl get pods -A > pods-status.txt

# 특정 Pod 로그
kubectl logs -n <namespace> <pod-name> > pod-log.txt

# 이벤트
kubectl get events -A --sort-by='.lastTimestamp' > events.txt
```
