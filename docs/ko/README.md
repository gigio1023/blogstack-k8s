# blogstack-k8s 문서

GitOps 기반 Ghost 블로그 인프라 구축 가이드

OCI 무료 ARM VM + k3s + Argo CD + Vault + Ghost

---

## 설치 순서

```
00 → 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08
```

- [00-prerequisites.md](./00-prerequisites.md) - 사전 요구사항
- [01-infrastructure.md](./01-infrastructure.md) - k3s 클러스터 설치
- [02-argocd-setup.md](./02-argocd-setup.md) - Argo CD 설치 및 App-of-Apps 구성
- [03-vault-setup.md](./03-vault-setup.md) - Vault 초기화 및 시크릿 주입
- [04-ingress-setup.md](./04-ingress-setup.md) - Ingress-nginx Admission Webhook
- [05-cloudflare-setup.md](./05-cloudflare-setup.md) - Cloudflare Tunnel 및 Zero Trust
- [06-verification.md](./06-verification.md) - 전체 시스템 검증
- [07-smtp-setup.md](./07-smtp-setup.md) - SMTP 이메일 설정 (필수)
- [08-operations.md](./08-operations.md) - 운영 및 유지보수
- [09-troubleshooting.md](./09-troubleshooting.md) - 트러블슈팅
- [10-monitoring.md](./10-monitoring.md) - 모니터링 구성 (VictoriaMetrics/Grafana)

---

## 운영 및 참고

### 운영
- [RESET.md](./RESET.md) - Applications 재시작

### 설정
- [CUSTOMIZATION.md](./CUSTOMIZATION.md) - Git URL, 도메인, 환경별 설정 변경
- [ENVIRONMENTS.md](./ENVIRONMENTS.md) - dev/prod 환경 구성

### 아키텍처
- [CONFORMANCE.md](./CONFORMANCE.md) - 전체 아키텍처 및 컴포넌트 검증
- [SECURITY.md](./SECURITY.md) - 보안 가이드
- [CI.md](./CI.md) - CI 파이프라인 구성

---

## 기술 스택

- Kubernetes: k3s
- GitOps: Argo CD
- 시크릿: Vault + VSO
- 인그레스: ingress-nginx + Cloudflare Tunnel
- 애플리케이션: Ghost 5.x + MySQL 8.0
- 관측성: VictoriaMetrics + Grafana + Loki
