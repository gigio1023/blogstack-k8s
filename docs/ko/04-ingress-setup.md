# 04. Ingress-nginx Admission Webhook 설정

## 문제

Argo CD Helm 통합으로 ingress-nginx 배포 시 admission webhook의 caBundle 미설정

에러:
```
x509: certificate signed by unknown authority
```

## 해결

```bash
# caBundle 설정
CA=$(kubectl get secret ingress-nginx-admission -n ingress-nginx -o jsonpath='{.data.ca}')
kubectl patch validatingwebhookconfiguration ingress-nginx-admission \
  --type='json' \
  -p='[{"op": "add", "path": "/webhooks/0/clientConfig/caBundle", "value":"'$CA'"}]'

# 확인
kubectl get validatingwebhookconfiguration ingress-nginx-admission \
  -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | wc -c
# 700+ 출력

# Ghost Application Sync
kubectl patch application ghost -n argocd \
  -p '{"operation": {"sync": {"revision": "HEAD"}}}' --type merge

# Ingress 생성 확인
kubectl get ingress -n blog
# ghost ingress 생성됨
```

## 트러블슈팅

### Ingress 생성 안됨

```bash
kubectl describe application ghost -n argocd | grep -A 10 "Message:"
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
```

### 인증서 재생성

```bash
kubectl delete secret ingress-nginx-admission -n ingress-nginx
kubectl delete pod -n ingress-nginx -l app.kubernetes.io/component=controller
```

## 다음 단계

→ [05-cloudflare-setup.md](./05-cloudflare-setup.md) - Cloudflare Tunnel Public Hostname 설정
