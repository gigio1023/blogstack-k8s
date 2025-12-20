# 06. System Verification

## Check Pod Status

```bash
kubectl get pods -n blog
# ghost, mysql: 1/1 Running

kubectl get pods -n cloudflared
# 1/1 Running

kubectl get applications -n argocd
# Synced Healthy

kubectl get ingress -n blog
# ghost ingress present
```

## Network Tests

```bash
# MySQL connection
kubectl exec -n blog mysql-0 -- mysql \
  -u ghost \
  -p$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.password}' | base64 -d) \
  ghost -e "SELECT 1;"

# External access
curl -I https://yourdomain.com
# HTTP/2 200

curl -I https://yourdomain.com/ghost/
# HTTP/2 302 (Access auth)
```

## Ghost Initial Setup

1. Visit `https://yourdomain.com/ghost/`
2. Cloudflare Access auth (if configured)
3. Create admin account
4. Write first post

## Monitoring Access (Optional)

### VictoriaMetrics (vmagent)

```bash
kubectl port-forward -n observers svc/vmagent 8429:8429 &
# http://localhost:8429/targets
```

### VictoriaMetrics (vmsingle)

```bash
kubectl port-forward -n observers svc/vmsingle 8428:8428 &
# http://localhost:8428/vmui
```

### Grafana

```bash
kubectl port-forward -n observers svc/grafana 3000:80 &
# http://localhost:3000
# admin / admin
```

## Test Backup (Optional)

```bash
kubectl create job --from=cronjob/mysql-backup mysql-backup-test -n blog
kubectl logs -f job/mysql-backup-test -n blog
```

## Troubleshooting

### Ghost Pod CrashLoopBackOff

```bash
kubectl logs -n blog <ghost-pod>
# Check MySQL connection failure

# Verify MySQL passwords match
kubectl get secret -n blog ghost-env -o jsonpath='{.data.database__connection__password}' | base64 -d
kubectl get secret -n blog mysql-secret -o jsonpath='{.data.password}' | base64 -d
# Must be identical
```

### 503 Service Unavailable

```bash
kubectl get pods -n blog
kubectl get ingress -n blog

kubectl describe ingress ghost -n blog
```

## Next Steps

→ [07-smtp-setup.md](./07-smtp-setup.md) - SMTP email setup (required)

→ [08-operations.md](./08-operations.md) - Operations & maintenance

→ [09-troubleshooting.md](./09-troubleshooting.md) - Troubleshooting
