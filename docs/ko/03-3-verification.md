# 03-3. 전체 시스템 검증

## Pod 상태 확인

```bash
kubectl get pods -n blog  # ghost, mysql: 1/1 Running
kubectl get pods -n cloudflared  # 1/1 Running
kubectl get applications -n argocd  # Synced Healthy
kubectl get ingress -n blog  # ghost ingress 생성
```

## 네트워크 테스트

```bash
# MySQL 연결
kubectl exec -n blog mysql-0 -- mysql \
  -u ghost -p$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.password}' | base64 -d) \
  ghost -e "SELECT 1;"

# 외부 접근
curl -I https://yourdomain.com  # HTTP/2 200
curl -I https://yourdomain.com/ghost/  # HTTP/2 302 (Access)
```

## Ghost 초기 설정

1. `https://yourdomain.com/ghost/` 접속
2. Cloudflare Access 인증
3. 관리자 계정 생성
4. 첫 게시글 작성

## 모니터링

```bash
# Prometheus
kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090 &
# http://localhost:9090/targets

# Grafana
kubectl port-forward -n observers svc/kube-prometheus-stack-grafana 3000:80 &
# http://localhost:3000 (admin/prom-operator)
```

## 백업 테스트 (선택)

```bash
kubectl create job --from=cronjob/mysql-backup mysql-backup-test -n blog
kubectl logs -f job/mysql-backup-test -n blog
```

## 최종 체크리스트

- [ ] Vault unsealed
- [ ] 모든 Pod Running
- [ ] Ingress 생성
- [ ] Cloudflare Tunnel 연결
- [ ] 블로그 접근 가능
- [ ] Ghost 관리자 Access 인증 작동
- [ ] Ghost 초기 설정 완료

## 다음 단계

- [04-operations.md](./04-operations.md)
- [03-troubleshooting.md](./03-troubleshooting.md)
