# 03-3. System Verification

## Verify Pod Status

```bash
kubectl get pods -n blog  # ghost, mysql: 1/1 Running
kubectl get pods -n cloudflared  # 1/1 Running
kubectl get applications -n argocd  # Synced Healthy
kubectl get ingress -n blog  # ghost ingress created
```

## Network Tests

```bash
# MySQL connection
kubectl exec -n blog mysql-0 -- mysql \
  -u ghost -p$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.password}' | base64 -d) \
  ghost -e "SELECT 1;"

# External access
curl -I https://yourdomain.com  # HTTP/2 200
curl -I https://yourdomain.com/ghost/  # HTTP/2 302 (Access)
```

## Ghost Initial Setup

1. Visit `https://yourdomain.com/ghost/`
2. Complete Cloudflare Access authentication
3. Create admin account
4. Write first post

## Monitoring

```bash
# Prometheus
kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090 &
# http://localhost:9090/targets

# Grafana
kubectl port-forward -n observers svc/kube-prometheus-stack-grafana 3000:80 &
# http://localhost:3000 (admin/prom-operator)
```

## Backup Test (Optional)

```bash
kubectl create job --from=cronjob/mysql-backup mysql-backup-test -n blog
kubectl logs -f job/mysql-backup-test -n blog
```

## Final Checklist

- [ ] Vault unsealed
- [ ] All Pods Running
- [ ] Ingress created
- [ ] Cloudflare Tunnel connected
- [ ] Blog accessible
- [ ] Ghost admin Access authentication working
- [ ] Ghost initial setup complete

## Next Steps

- [04-operations.md](./04-operations.md)
- [03-troubleshooting.md](./03-troubleshooting.md)

