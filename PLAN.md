좋아. **blogstack-k8s** 모노레포에 “시크릿/설정 주입”까지 **완전 자급(Self-hosted)** 으로 돌릴 수 있게, 외부 AI IDE가 이 문서 **하나만 읽고** 초기 셋업을 수행할 수 있는 **최종 구축 계획서**를 정리했어. (핵심 선택지는 해시코프 Vault 기반이고, 대안인 Sealed Secrets / SOPS / Infisical도 비교에 포함함.)

---

# blogstack-k8s — Monorepo 초기 구축 계획(ARM64/OCI, 단일 prod, Self-Hosted Secret)

## 0) 목표·전제

* **목표:**

  1. 코드(테마/인프라) 변경은 **GitOps 자동 반영**,
  2. 글은 Ghost Admin에서 **즉시 출고**,
  3. 서비스 상태는 **지표/알림으로 한눈에**,
  4. **시크릿/설정**은 **Self-hosted** 비밀관리로 주입.
* **플랫폼/제약:** Oracle Cloud **VM.Standard.A1.Flex**(ARM64, 4 OCPU/24GB). 단일 **prod** 만 운용.
* **노출/보안:** **Cloudflare Tunnel**로 공인 포트 개방 없이 노출, 터널은 **CNAME → `<UUID>.cfargotunnel.com`** 으로 라우팅. `/ghost/*` 경로는 **Zero Trust Access** 정책으로 보호. ([Cloudflare Docs][1])
* **프록시 주의:** Ghost는 리버스 프록시 뒤에서 **`X-Forwarded-Proto: https`** 를 반드시 받아야 리다이렉트 루프/멤버 포털 오류가 없다. ([Ghost Docs][2])

---

## 1) 리포지토리 구조(모노레포)

```
blogstack-k8s/
├─ docs/                         # 개요/런북/보안정책(이 문서 포함)
├─ clusters/
│  └─ prod/                      # Kustomize overlay(엔트리)
├─ iac/
│  ├─ argocd/                    # App-of-Apps 루트 및 하위 App 정의
│  └─ rbac/                      # SA/Role/NetworkPolicy 등
├─ apps/
│  ├─ ingress-nginx/             # Ingress Controller(+metrics:10254)
│  ├─ cloudflared/               # Cloudflare Tunnel(HA, /ready, /metrics)
│  ├─ ghost/                     # Ghost + MySQL(PVC)
│  ├─ observers/                 # kube-prometheus-stack + blackbox + loki
│  ├─ uptime-kuma/               # (선택) 외부 헬스/알림 보조
│  └─ comments/                  # (선택) Remark42/HYVOR/Disqus 배치
├─ security/
│  ├─ vault/                     # Vault(Helm values, 정책, 초기화 가이드)
│  ├─ vso/                       # Vault Secrets Operator 매니페스트
│  └─ external-secrets/          # (선택) ESO 연동 템플릿
├─ theme/                        # Ghost 테마(액션으로 배포)
└─ .github/workflows/            # Deploy Ghost Theme 등
```

* **App-of-Apps**(Argo CD)로 하위 앱 일괄 오케스트레이션. **Kustomize overlay**는 `prod/` 하나로 단순화. ([HashiCorp Developer][3])

---

## 2) Self-hosted 시크릿/설정 — 권장안과 대안

### A. **권장: HashiCorp Vault(OSS) + Vault Secrets Operator(VSO)**

* **왜 이 조합인가?**

  * Vault는 **Kubernetes 공식 Helm 차트**로 배포/운영이 표준화. **Raft(Integrated Storage)** 로 외부 의존 없이 단일 노드도 안정적. **Kubernetes Auth** + **Agent Injector**/VSO로 주입 경로가 다양함. **Prometheus 포맷** 메트릭 제공. ([HashiCorp Developer][3])
  * **VSO(공식 오퍼레이터)** 는 Vault를 비밀 소스로 삼아 **K8s Secret을 자동 동기화**(변경 시 롤링갱신 트리거 가능). 앱은 평소처럼 Secret/env를 쓰면 됨. ([HashiCorp Developer][4])
* **장점:** Git에 평문 시크릿 無, 주입/회수 체계 표준, 메트릭/감사로그 체계적.
* **보완:** etcd 평문을 피하려면 **Injector 사이드카**로 “파일/메모리 볼륨 주입”도 선택 가능(Secret 생성 자체를 최소화). ([HashiCorp Developer][5])

### B. **대안1: Bitnami Sealed Secrets(컨트롤러 + RSA)**

* Git에 **암호화된 SealedSecret** 저장, 클러스터 컨트롤러만 복호화. “서비스”라기보다 **암복호화 컨트롤러**에 가까움. 간단·저자원. (동적 회전/감사/권한모델은 제한) ([GitHub][6])

### C. **대안2: Mozilla SOPS(+KSOPS) Git-암호화**

* Git에 **SOPS(AGE 권장)** 로 암호화된 매니페스트를 저장하고, Argo CD/Kustomize 플러그인(KSOPS)으로 배포 시 복호. 외부 서비스 無, GitOps 친화. (실시간 회전/감사/세분권한은 제한) ([GitHub][7])

### D. **대안3: Infisical(오픈소스, 자체 호스팅 가능)**

* **자체 호스팅 UI/서버** + **K8s 오퍼레이터**. ESO 통합 또는 자체 오퍼레이터로 **싱크/롤링 재시작/동적 시크릿** 지원. (구축 복잡도는 Vault와 유사) ([GitHub][8])

> **우리 선택(본 문서 기본 경로):** **A안(Vault + VSO)**.
> 이유: 표준성/확장성/감사/메트릭/Injector 경로 모두 확보.

---

## 3) 배포 순서(End-to-End)

1. **Kubernetes(권장: k3s) 설치** — ARM64에 경량/기본 **Local Path Provisioner** 로 PVC 바로 사용 가능. ([docs.k3s.io][9])
2. **Argo CD 배포 → App-of-Apps 등록** — 이 레포를 **단일 사실원천**으로 동기화.
3. **Ingress-NGINX 배포(메트릭 on)** — 컨트롤러 **:10254** 의 `/metrics` 스크레이프. ([kubernetes.github.io][10])
4. **Cloudflare Tunnel 배포** — **Named Tunnel** 구성, 도메인은 **CNAME → `<UUID>.cfargotunnel.com`**. `/ready`/`--metrics` 활성. `/ghost/*` 는 Access 정책. ([Cloudflare Docs][11])
5. **Vault 배포(Helm) + 초기화**

   * 스토리지: **Integrated Storage(Raft)** 단일 노드 시작 → 나중에 확장.
   * **Init/Unseal**(Shamir), **Root Token** 수령, **Audit** 활성, **Kubernetes Auth** enable. ([HashiCorp Developer][12])
6. **VSO 배포 & 시크릿 싱크**

   * `SecretStore/ClusterSecretStore` 로 Vault 연결 → 앱 네임스페이스마다 `ExternalSecret`(VSO 명칭은 `SecretSync` 계열)로 **K8s Secret 생성/갱신**. ([HashiCorp Developer][4])
   * (대안) **Vault Agent Injector** 주석으로 파일/ENV 직접 주입(etc d 평문 최소화). ([HashiCorp Developer][5])
7. **Ghost + MySQL 배포** — `url=https://...` 지정, Ingress에서 **`X-Forwarded-Proto=https`** 전달 확인. ([Ghost Docs][2])
8. **관측/알림 스택**

   * **kube-prometheus-stack + blackbox + Loki**.
   * Blackbox로 `/`, `/ghost`, `/sitemap.xml` 외부 SLI, Ingress(:10254), cloudflared(메트릭) 계측. Grafana **이메일 Contact Point** 설정. ([GitHub][13])
9. **댓글 위젯(전원 공개 원칙)** — **Ghost 네이티브 댓글은 멤버십 전제**이므로, **Remark42/HYVOR/Disqus** 중 택1 임베드. ([Ghost][14])
10. **테마 CI** — GitHub Actions **Deploy Ghost Theme**로 Admin API 업로드/활성. (다운타임 無)

---

## 4) Vault 설계(요점)

### 4.1 구성

* **배포:** 공식 **Vault Helm 차트**, **Raft(Integrated Storage)**, `server.ha.enabled=false` 로 단일 시작. 필요 시 서버 Replica + Raft 노드 확장. ([HashiCorp Developer][3])
* **초기화/언실:** Shamir 키 분할(예: 3/5) → 보관(오프라인).
* **인증:** **Kubernetes Auth**(SA/Namespace 맵핑)로 폿이 Vault에서 토큰 발급. **정책(Policy)** 으로 경로별 최소권한. ([HashiCorp Developer][5])
* **주입 경로:**

  * **VSO**: Vault(KV) → K8s Secret 동기화(앱은 envFrom/SecretRef). ([HashiCorp Developer][4])
  * **Injector**: 사이드카가 **템플릿으로 파일/ENV**를 공유 볼륨에 렌더링(etc d 비노출). ([HashiCorp Developer][5])
* **모니터링:** `/v1/sys/metrics?format=prometheus` 스크레이프, Grafana 대시보드(공식/커뮤니티). ([HashiCorp Developer][15])
* **감사:** Audit device(파일/소켓) 활성화(액세스 트레일).

### 4.2 Vault-백업

* **Raft 스냅샷** + 원격 보관소(OCI **Object Storage S3 호환 API**) 업로드를 추천. (버킷 보존정책/버전관리) ([Oracle Docs][16])

### 4.3 시크릿 네이밍 & 정책 예

* `kv/blog/prod/ghost`: `database_url`, `smtp_*`, `admin_api_key`
* 정책: `path "kv/data/blog/prod/ghost" { capabilities = ["read"] }` (필요 최소권한)

---

## 5) 관측·알림(요약)

* **외부 SLI:** Blackbox HTTP 모듈로 `/`, `/sitemap.xml`, `/ghost` 상태/지연 측정. ([GitHub][13])
* **엣지/터널:** cloudflared **`--metrics`** 로 메트릭 노출(+ `/ready` 헬스). ([Cloudflare Docs][17])
* **Ingress:** 컨트롤러 **:10254** 메트릭 스크레이프. ([kubernetes.github.io][10])
* **Vault:** `/sys/metrics?format=prometheus` 스크레이프. ([HashiCorp Developer][18])
* **알림:** Grafana **Contact Points(이메일)**, 필요 시 Alertmanager/업타임 쿠마 병행. ([Grafana Labs][19])

---

## 6) 스토리지/자산 백업

* **Ghost DB**: 정기 `mysqldump` + 버킷 보관(OCI Object Storage **S3 호환 API**). ([Oracle Docs][16])
* **Ghost content/**: 주기 스냅샷/동기화.
* **복구 리허설:** 월 1회 샌드박스 복구.

---

## 7) 네트워킹/보안 요점

* Cloudflare Tunnel은 **아웃바운드 전용** 연결, 하나의 터널에 **다중 커넥터** 가능(HA). DNS는 **CNAME → `<UUID>.cfargotunnel.com`**. 경로 단위 Access 정책으로 `/ghost/*` 보호. ([Cloudflare Docs][11])
* Ghost 프록시 앞단에서는 **`X-Forwarded-Proto=https`** 강제. ([Ghost Docs][2])

---

## 8) 실행 체크리스트(AI IDE용)

1. **k3s/K8s** 설치 → `kubectl` 컨텍스트 확인. 로컬 PVC(기본 Local Path) 사용. ([docs.k3s.io][9])
2. **Argo CD** 설치 → 본 레포 `clusters/prod` App-of-Apps 등록.
3. **ingress-nginx** 배포(Helm) → 컨트롤러 **metrics enabled** 확인(**:10254**). ([kubernetes.github.io][10])
4. **cloudflared** 배포 → **Named Tunnel** 토큰/구성, `--metrics`, `/ready` 활성, DNS **CNAME → `<UUID>.cfargotunnel.com`**. ([Cloudflare Docs][20])
5. **Vault** 배포(Helm) → 초기화/언실, Kubernetes Auth enable, 정책 생성. ([HashiCorp Developer][3])
6. **VSO** 배포 → `ClusterSecretStore`(Vault 연결) + `SecretSync`(네임스페이스별 매핑) 생성. ([HashiCorp Developer][4])
7. **Ghost** 배포 → `url=https://...` + Ingress에서 **`X-Forwarded-Proto=https`** 전달 확인. ([Ghost Docs][2])
8. **관측** 배포 → kube-prometheus-stack + blackbox + Loki, Grafana **이메일** Contact Point 설정. ([GitHub][13])
9. **댓글** → Remark42/HYVOR/Disqus 임베드(전원 공개 댓글). **Ghost 네이티브 댓글은 “멤버만”** 가능. ([Ghost][14])
10. **테마 CI** → GitHub Marketplace **Deploy Ghost Theme** 사용(옵션).

---

## 9) 운영·문제해결(발췌)

* **리다이렉트 루프/포털 오류:** 프록시가 **`X-Forwarded-Proto=https`** 미전달. Ingress 주석/설정 확인. ([Ghost Docs][2])
* **터널 불안정:** cloudflared **/ready** 및 **메트릭**으로 연결/재시도 수 확인. ([Cloudflare Docs][17])
* **메트릭 미수집:** ingress **:10254**, blackbox 타깃/리레이블, Vault `/sys/metrics` 권한 확인. ([kubernetes.github.io][10])

---

## 부록 A) 시크릿 옵션 비교 요약

| 옵션                       | 운영형태             | 장점                     | 주의              |               |
| ------------------------ | ---------------- | ---------------------- | --------------- | ------------- |
| **Vault + VSO/Injector** | **서비스형(자체 호스팅)** | 표준/확장/감사/메트릭/세분권한/동적주입 | 초기화·운영 러닝커브     |               |
| **Sealed Secrets**       | 컨트롤러+키쌍          | Git 보관 간편/저자원          | 동적 회전/감사 한계     | ([GitHub][6]) |
| **SOPS(+KSOPS)**         | Git 암호화          | 외부 서비스 無, GitOps 친화    | 실시간 회전/권한미세화 한계 | ([GitHub][7]) |
| **Infisical(자체 호스팅)**    | 서비스형             | UI/오퍼레이터/ESO·네이티브 연동   | 구성요소 다수         | ([GitHub][8]) |

---

## 부록 B) 예시: Vault-기반 시크릿 흐름(요약)

1. Vault 설치(Helm) → **Raft 저장소**, Init/Unseal, Audit on. ([HashiCorp Developer][3])
2. `kv/blog/prod/ghost` 경로에 시크릿 작성(KV v2).
3. **Kubernetes Auth** enable → `role: ghost` (SA/NS 바인딩). ([HashiCorp Developer][5])
4. **VSO**: `ClusterSecretStore` 로 Vault 연결 → `SecretSync` 또는 `ExternalSecret` 정의로 `ghost-env` 같은 K8s Secret을 자동 생성/갱신. ([HashiCorp Developer][4])
5. Ghost Deployment가 `envFrom: secretRef: ghost-env` 로 소비.
6. **메트릭/알림**: Vault `/sys/metrics?format=prometheus` 스크레이프 + Grafana 이메일 알림. ([HashiCorp Developer][18])

---

## 부록 C) 기타 선택지/확장

* **Canary 릴리스**(원할 때): ingress-nginx **canary 주석/가중치**로 점진 전개(또는 Argo Rollouts). ([kubernetes.github.io][21])
* **오브젝트 스토리지**: 콘텐츠/백업은 OCI Object Storage **S3 호환 API**로 통합. ([Oracle Docs][16])

---

필요하면 위 내용을 `docs/SETUP.md`와 `security/vault/README.md`(초기화·정책 샘플), `security/vso/`(CRD 샘플), `clusters/prod/`(App-of-Apps 스켈레톤) 형태로 **바로 커밋 가능한 문서/주석 매니페스트**로 풀어줄게.

[1]: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/dns/?utm_source=chatgpt.com "DNS records - Cloudflare Zero Trust"
[2]: https://docs.ghost.org/faq/proxying-https-infinite-loops?utm_source=chatgpt.com "Reverse Proxying To Ghost - Ghost Developer Docs"
[3]: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/helm?utm_source=chatgpt.com "Helm chart | Vault"
[4]: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/sources/vault?utm_source=chatgpt.com "Vault Secrets Operator"
[5]: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/injector?utm_source=chatgpt.com "Vault Agent Injector"
[6]: https://github.com/bitnami-labs/sealed-secrets?utm_source=chatgpt.com "bitnami-labs/sealed-secrets: A Kubernetes controller ..."
[7]: https://github.com/getsops/sops?utm_source=chatgpt.com "getsops/sops: Simple and flexible tool for managing secrets"
[8]: https://github.com/Infisical/infisical?utm_source=chatgpt.com "Infisical is the open-source platform for secrets, certificates ..."
[9]: https://docs.k3s.io/storage?utm_source=chatgpt.com "Volumes and Storage"
[10]: https://kubernetes.github.io/ingress-nginx/user-guide/monitoring/?utm_source=chatgpt.com "Prometheus and Grafana installation - Ingress-Nginx Controller"
[11]: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/?utm_source=chatgpt.com "Cloudflare Tunnel · Cloudflare Zero Trust docs"
[12]: https://developer.hashicorp.com/vault/tutorials/day-one-raft/raft-deployment-guide?utm_source=chatgpt.com "Vault with integrated storage deployment guide"
[13]: https://github.com/prometheus/blackbox_exporter?utm_source=chatgpt.com "prometheus/blackbox_exporter: Blackbox prober exporter"
[14]: https://ghost.org/help/commenting/?utm_source=chatgpt.com "Comments - Ghost"
[15]: https://developer.hashicorp.com/vault/tutorials/archive/monitor-telemetry-grafana-prometheus?utm_source=chatgpt.com "Monitor telemetry with Prometheus & Grafana | Vault"
[16]: https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/s3compatibleapi.htm?utm_source=chatgpt.com "Object Storage Amazon S3 Compatibility API"
[17]: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/monitor-tunnels/metrics/?utm_source=chatgpt.com "Tunnel metrics - Cloudflare Zero Trust"
[18]: https://developer.hashicorp.com/vault/api-docs/system/metrics?utm_source=chatgpt.com "sys/metrics - HTTP API | Vault"
[19]: https://grafana.com/docs/grafana/latest/alerting/fundamentals/notifications/contact-points/?utm_source=chatgpt.com "Contact points | Grafana documentation"
[20]: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/create-local-tunnel/?utm_source=chatgpt.com "Create a locally-managed tunnel · Cloudflare Zero Trust docs"
[21]: https://kubernetes.github.io/ingress-nginx/examples/canary/?utm_source=chatgpt.com "Canary Deployments - Ingress-Nginx Controller - Kubernetes"
