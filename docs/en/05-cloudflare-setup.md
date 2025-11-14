# 05. Cloudflare Tunnel & Zero Trust

## Cloudflare Tunnel Config

### Set Hostname Routes

1. Go to https://one.dash.cloudflare.com/
2. Networks → Tunnels → blogstack-tunnel
3. Published application routes → Add
4. Configure:
   - Hostname: yourdomain.com
   - Service: http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
5. Create

### Verify Connection

```bash
kubectl logs -n cloudflared -l app=cloudflared --tail=50
# INF Connection <UUID> registered connIndex=0
```

## Zero Trust Access (Optional)

Protect Ghost Admin (`/ghost/*`)

### Create Access Application

1. Go to https://one.dash.cloudflare.com/
2. Access → Applications → Add an application
3. Select Self-hosted

### Basic Info

- Application name: Ghost Blog Admin
- Session Duration: 24 hours
- Public hostname:
  - Domain: yourdomain.com
  - Path: /ghost/*

### Policy

- Policy name: Ghost Admin Only
- Action: Allow
- Include: Emails - your-email@example.com

### Test

```bash
curl -I https://yourdomain.com
# HTTP/2 200

curl -I https://yourdomain.com/ghost/
# HTTP/2 302 (Access auth page)
```

## Troubleshooting

### Tunnel Not Connected

```bash
kubectl logs -n cloudflared -l app=cloudflared

# Check token
kubectl get secret cloudflared-token -n cloudflared -o jsonpath='{.data.token}' | base64 -d
```

### 502 Bad Gateway

Check ingress-nginx:
```bash
kubectl get pods -n ingress-nginx
kubectl get ingress -n blog
```

## Next Steps

→ [06-verification.md](./06-verification.md) - System verification
