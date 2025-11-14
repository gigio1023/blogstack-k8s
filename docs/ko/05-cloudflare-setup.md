# 05. Cloudflare Tunnel 및 Zero Trust 설정

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

## Zero Trust Access 설정 (선택)

Ghost Admin (`/ghost/*`) 보호

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

### 테스트

```bash
curl -I https://yourdomain.com
# HTTP/2 200

curl -I https://yourdomain.com/ghost/
# HTTP/2 302 (Access 인증 페이지)
```

## 트러블슈팅

### Tunnel 연결 안됨

```bash
kubectl logs -n cloudflared -l app=cloudflared

# Tunnel Token 확인
kubectl get secret cloudflared-token -n cloudflared -o jsonpath='{.data.token}' | base64 -d
```

### 502 Bad Gateway

Ingress-nginx 상태 확인:
```bash
kubectl get pods -n ingress-nginx
kubectl get ingress -n blog
```

## 다음 단계

→ [06-verification.md](./06-verification.md) - 전체 시스템 검증
