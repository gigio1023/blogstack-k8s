# 03-2. Cloudflare Tunnel and Zero Trust Setup

## Configure Cloudflare Tunnel

### Set Hostname Routes

1. https://one.dash.cloudflare.com/
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

## Configure Zero Trust Access

### Create Access Application

1. https://one.dash.cloudflare.com/
2. Access → Applications → Add an application
3. Select Self-hosted

### Basic Information

- Application name: Ghost Blog Admin
- Session Duration: 24 hours
- Public hostname:
  - Domain: yourdomain.com
  - Path: /ghost/*

### Policy

- Policy name: Ghost Admin Only
- Action: Allow
- Include: Emails - your-email@example.com

### Save

Next → Add application

### Test

```bash
curl -I https://yourdomain.com  # HTTP/2 200
curl -I https://yourdomain.com/ghost/  # HTTP/2 302 (Access redirect)
```

## Optional: GitHub Authentication

### GitHub OAuth App

1. https://github.com/settings/developers → New OAuth App
2. Configure:
   - Application name: Cloudflare Access - Ghost Blog
   - Homepage URL: https://<team-name>.cloudflareaccess.com
   - Callback URL: https://<team-name>.cloudflareaccess.com/cdn-cgi/access/callback
3. Copy Client ID/Secret

### Cloudflare Zero Trust

1. Settings → Authentication → Add new
2. Select GitHub
3. Enter Client ID/Secret
4. Save

## Troubleshooting

### Error 1033

```bash
kubectl logs -n cloudflared -l app=cloudflared --tail=100
kubectl exec -n cloudflared -l app=cloudflared -- \
  nc -zv ingress-nginx-controller.ingress-nginx.svc.cluster.local 80
```

Verify Service configuration in Cloudflare Tunnel dashboard.

## Next Steps

Next: [03-3-verification.md](./03-3-verification.md)

