# 03. 트러블슈팅

## Vault

### Pod CrashLoopBackOff

```bash
kubectl logs -n vault vault-0
kubectl get pvc -n vault  # Bound 확인
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

kubectl patch application ghost -n argocd -p '{"operation": {"sync": {"revision": "HEAD"}}}' --type merge
```

## Cloudflared

### CrashLoopBackOff (--metrics 오류)

`apps/cloudflared/base/deployment.yaml` 수정:

```yaml
args:
  - tunnel
  - --no-autoupdate
  - run
  - --token
  - $(TUNNEL_TOKEN)
  - --metrics=0.0.0.0:2000  # = 기호로 연결
```

```bash
git add apps/cloudflared/base/deployment.yaml
git commit -m "Fix cloudflared metrics flag"
git push
kubectl patch application cloudflared -n argocd -p '{"operation": {"sync": {"revision": "HEAD"}}}' --type merge
```

### Error 1033

```bash
kubectl logs -n cloudflared -l app=cloudflared --tail=50
kubectl exec -n cloudflared -l app=cloudflared -- \
  nc -zv ingress-nginx-controller.ingress-nginx.svc.cluster.local 80
```

Cloudflare Tunnel 설정 확인 (Service: `http://ingress-nginx-controller...`)

## Ghost

### CrashLoopBackOff (Migration Lock)

```bash
# Ingress 확인
kubectl get ingress -n blog

# Lock 해제
kubectl exec -n blog mysql-0 -- mysql \
  -u root -p$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.root_password}' | base64 -d) \
  ghost -e "UPDATE migrations_lock SET locked=0 WHERE lock_key='km01';"

kubectl rollout restart deployment/ghost -n blog
```

### URL 설정 오류

```bash
grep siteUrl config/prod.env
vault kv get -field=url kv/blog/prod/ghost
# 두 값 일치 필수

vault kv patch kv/blog/prod/ghost url="https://yourdomain.com"
kubectl rollout restart deployment/ghost -n blog
```

## MySQL

### 비밀번호 불일치

```bash
vault kv get -field=database__connection__password kv/blog/prod/ghost
vault kv get -field=password kv/blog/prod/mysql
# 동일해야 함

NEW_PASSWORD="your-password"
vault kv patch kv/blog/prod/ghost database__connection__password="$NEW_PASSWORD"
vault kv patch kv/blog/prod/mysql password="$NEW_PASSWORD"
kubectl rollout restart deployment/ghost -n blog
```

## VSO

### Secret 생성 안됨

```bash
kubectl describe vaultstaticsecret ghost-env -n blog | tail -20
kubectl logs -n vso -l app.kubernetes.io/name=vault-secrets-operator --tail=50

# VSO 재시작
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
kubectl get secrets -n blog  # 30초 후
```

### VaultAuth Invalid

```bash
vault read auth/kubernetes/config

TOKEN_REVIEWER_JWT=$(kubectl create token vault -n vault --duration=8760h)
vault write auth/kubernetes/config \
    token_reviewer_jwt="$TOKEN_REVIEWER_JWT" \
    kubernetes_host="https://kubernetes.default.svc:443" \
    kubernetes_ca_cert="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)" \
    disable_local_ca_jwt=true

kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
```

## 네트워크

### Pod 간 통신 실패

```bash
kubectl exec -n blog -l app=ghost -- nslookup mysql.blog.svc.cluster.local
kubectl exec -n blog -l app=ghost -- nc -zv mysql.blog.svc.cluster.local 3306
kubectl get networkpolicy -A
```

## 로그 수집

```bash
mkdir -p ~/debug-logs
kubectl logs -n blog -l app=ghost --tail=200 > ~/debug-logs/ghost.log
kubectl logs -n blog mysql-0 --tail=200 > ~/debug-logs/mysql.log
kubectl logs -n cloudflared -l app=cloudflared --tail=200 > ~/debug-logs/cloudflared.log
kubectl logs -n vso -l app.kubernetes.io/name=vault-secrets-operator --tail=200 > ~/debug-logs/vso.log
tar -czf debug-logs-$(date +%Y%m%d-%H%M%S).tar.gz ~/debug-logs/
```

## 이벤트 확인

```bash
kubectl get events -A --sort-by='.lastTimestamp' | grep -E "Warning|Error"
kubectl get events -n blog --sort-by='.lastTimestamp'
```
