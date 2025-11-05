# 03-2. Cloudflare Tunnel 및 Zero Trust 설정

## Cloudflare Tunnel 구성

### Hostname Routes 설정

1. https://one.dash.cloudflare.com/
2. Networks → Tunnels → blogstack-tunnel
3. Published application routes → Add
4. 설정:
   - Hostname: yourdomain.com
   - Service: http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
5. Create

### 연결 확인

```bash
kubectl logs -n cloudflared -l app=cloudflared --tail=50
# INF Connection <UUID> registered connIndex=0
```

## Zero Trust Access 설정

### Access Application 생성

1. https://one.dash.cloudflare.com/
2. Access → Applications → Add an application
3. Self-hosted 선택

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

### 저장

Next → Add application

### 테스트

```bash
curl -I https://yourdomain.com  # HTTP/2 200
curl -I https://yourdomain.com/ghost/  # HTTP/2 302 (Access 리다이렉트)
```

## 선택: GitHub 인증

### GitHub OAuth App

1. https://github.com/settings/developers → New OAuth App
2. 설정:
   - Application name: Cloudflare Access - Ghost Blog
   - Homepage URL: https://<team-name>.cloudflareaccess.com
   - Callback URL: https://<team-name>.cloudflareaccess.com/cdn-cgi/access/callback
3. Client ID/Secret 복사

### Cloudflare Zero Trust

1. Settings → Authentication → Add new
2. GitHub 선택
3. Client ID/Secret 입력
4. Save

## 트러블슈팅

### Error 1033

```bash
kubectl logs -n cloudflared -l app=cloudflared --tail=100
kubectl exec -n cloudflared -l app=cloudflared -- \
  nc -zv ingress-nginx-controller.ingress-nginx.svc.cluster.local 80
```

Cloudflare Tunnel 대시보드에서 Service 설정 확인

## 다음 단계

다음: [03-3-verification.md](./03-3-verification.md)
