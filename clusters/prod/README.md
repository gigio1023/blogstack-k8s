# clusters/prod

프로덕션 클러스터의 **엔트리포인트**입니다. Argo CD Root App이 이 디렉토리를 바라봅니다.

## 구조

```
clusters/prod/
├── kustomization.yaml    # Kustomize 엔트리
├── project.yaml          # Argo CD AppProject (경계 설정)
└── apps.yaml             # 자식 Application 정의 (App-of-Apps)
```

## App-of-Apps 패턴

### Root App

`iac/argocd/root-app.yaml`이 이 디렉토리를 소스로 지정:

```yaml
spec:
  source:
    repoURL: https://github.com/<org>/blogstack-k8s
    path: clusters/prod
    targetRevision: HEAD
```

### 자식 Applications

`apps.yaml`에 정의된 자식 Application들이 **sync-wave 순서**로 배포됩니다:

| Wave | Application | Path | 설명 |
|------|------------|------|------|
| -2 | observers | apps/observers/overlays/prod | Prometheus, Grafana, Loki (CRD 설치) |
| -1 | observers-probes | apps/observers-probes/overlays/prod | Blackbox Exporter Probe |
| -1 | ingress-nginx | apps/ingress-nginx/overlays/prod | Ingress Controller + 메트릭 |
| 0 | cloudflared | apps/cloudflared/overlays/prod | Cloudflare Tunnel |
| 1 | vault | security/vault | HashiCorp Vault (Raft) |
| 2 | vso-operator | security/vso-operator | Vault Secrets Operator (CRD 설치) |
| 3 | vso-resources | security/vso-resources | Vault 연결 및 시크릿 매핑 |
| 4 | ghost | apps/ghost/overlays/prod | Ghost + MySQL |

### Sync 옵션

각 Application에 적용된 공통 옵션:

- `CreateNamespace=true`: 네임스페이스 자동 생성 (대부분 앱)
- `PruneLast=true`: 삭제는 마지막에 수행 (모든 앱)
- `automated.prune`, `automated.selfHeal`: 자동 동기화 및 복구 (모든 앱)

**참고**: `SkipDryRunOnMissingResource`는 제거됨 (Wave 순서로 의존성 해결)

## AppProject

`project.yaml`은 **보안 경계**를 정의합니다:

- 허용 소스 리포지토리
- 허용 대상 네임스페이스/클러스터
- 리소스 화이트리스트

현재는 모든 리소스를 허용(`*`)하지만, 프로덕션에서는 제한 권장.

## 새로운 앱 추가

1. `apps/<new-app>/` 디렉토리 생성
2. `apps.yaml`에 Application 추가:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: new-app
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "4"  # 적절한 순서
spec:
  project: blog
  source:
    repoURL: https://github.com/<org>/blogstack-k8s
    path: apps/new-app/overlays/prod
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: new-app-ns
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
```

3. Git commit → Push → 자동 동기화

## 다중 환경 (선택)

dev/staging 환경 추가:

```
clusters/
├── dev/
│   ├── kustomization.yaml
│   ├── project.yaml
│   └── apps.yaml
└── prod/
    ├── kustomization.yaml
    ├── project.yaml
    └── apps.yaml
```

각 환경마다 별도의 Root App 생성.

## 참고

- [Argo CD App-of-Apps 패턴](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)

