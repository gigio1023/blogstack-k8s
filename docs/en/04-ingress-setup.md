# 04. Ingress-nginx Admission Webhook

## Problem

Argo CD Helm integration doesn't set caBundle for ingress-nginx admission webhook

Error:
```
x509: certificate signed by unknown authority
```

## Fix

```bash
# Set caBundle
CA=$(kubectl get secret ingress-nginx-admission -n ingress-nginx -o jsonpath='{.data.ca}')
kubectl patch validatingwebhookconfiguration ingress-nginx-admission \
  --type='json' \
  -p='[{"op": "add", "path": "/webhooks/0/clientConfig/caBundle", "value":"'$CA'"}]'

# Verify
kubectl get validatingwebhookconfiguration ingress-nginx-admission \
  -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | wc -c
# 700+

# Sync Ghost app
kubectl patch application ghost -n argocd \
  -p '{"operation": {"sync": {"revision": "HEAD"}}}' --type merge

# Check ingress created
kubectl get ingress -n blog
# ghost ingress present
```

## Troubleshooting

### Ingress Not Created

```bash
kubectl describe application ghost -n argocd | grep -A 10 "Message:"
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
```

### Regenerate Certificate

```bash
kubectl delete secret ingress-nginx-admission -n ingress-nginx
kubectl delete pod -n ingress-nginx -l app.kubernetes.io/component=controller
```

## Next Steps

→ [05-cloudflare-setup.md](./05-cloudflare-setup.md) - Cloudflare Tunnel public hostname
