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

### 배포 전 Docker 검증

배포 전에 로컬에서 cloudflared 명령어를 검증합니다.

#### 토큰 추출

```bash
TUNNEL_TOKEN=$(kubectl get secret cloudflared-token -n cloudflared -o jsonpath='{.data.token}' | base64 -d)
echo "Token length: ${#TUNNEL_TOKEN}"  # 184 characters
```

#### 최소 설정 테스트

```bash
docker run --rm cloudflare/cloudflared:2025.10.0 \
  tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"
```

예상 출력: `Connection registered`

#### Metrics 포함 테스트

```bash
docker run --rm \
  -p 2000:2000 \
  -e TUNNEL_METRICS=0.0.0.0:2000 \
  cloudflare/cloudflared:2025.10.0 \
  tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"
```

다른 터미널에서 확인:
```bash
curl http://localhost:2000/metrics  # Prometheus metrics 출력
```

#### 성공한 명령어를 YAML로 적용

Docker에서 성공한 args를 `apps/cloudflared/base/deployment.yaml`에 적용:

```yaml
args:
  - tunnel
  - --no-autoupdate
  - run
  - --token
  - $(TUNNEL_TOKEN)
env:
  - name: TUNNEL_METRICS
    value: "0.0.0.0:2000"
```

```bash
git add apps/cloudflared/base/deployment.yaml
git commit -m "fix: validated cloudflared args"
git push
```

#### Flag 개별 검증

특정 flag가 지원되는지 확인:

```bash
docker run --rm cloudflare/cloudflared:2025.10.0 tunnel run --help | grep "metrics"
docker run --rm cloudflare/cloudflared:2025.10.0 tunnel run --help | grep "\[$"
# [$로 끝나는 것들은 환경변수로 설정 가능
```

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
