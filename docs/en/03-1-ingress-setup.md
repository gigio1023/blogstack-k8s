# 03-1. Ingress-nginx Admission Webhook Setup

## Problem

Helm-based ingress-nginx deployment via Argo CD leaves admission webhook caBundle unset.

**Error**:
```
x509: certificate signed by unknown authority
```

## Solution

```bash
# Set caBundle
CA=$(kubectl get secret ingress-nginx-admission -n ingress-nginx -o jsonpath='{.data.ca}')
kubectl patch validatingwebhookconfiguration ingress-nginx-admission \
  --type='json' \
  -p='[{"op": "add", "path": "/webhooks/0/clientConfig/caBundle", "value":"'$CA'"}]'

# Verify
kubectl get validatingwebhookconfiguration ingress-nginx-admission \
  -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | wc -c  # 700+

# Sync Argo CD Application
kubectl patch application ghost -n argocd \
  -p '{"operation": {"sync": {"revision": "HEAD"}}}' --type merge

# Verify Ingress creation
kubectl get ingress -n blog  # ghost ingress created
```

## Troubleshooting

### Ingress Still Not Created

```bash
kubectl describe application ghost -n argocd | grep -A 10 "Message:"
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
```

### Certificate Regeneration Required

```bash
kubectl delete secret ingress-nginx-admission -n ingress-nginx
kubectl delete pod -n ingress-nginx -l app.kubernetes.io/component=controller
```

## Next Steps

Next: [03-2-cloudflare-setup.md](./03-2-cloudflare-setup.md)

