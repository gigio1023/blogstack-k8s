# MySQL Exporter CrashLoop으로 인한 Ghost 장애 (사후 기록)

## 증상

- Ghost Pod: CrashLoopBackOff 또는 500 응답
  - 로그: `connect ECONNREFUSED <mysql service ip>:3306`
- MySQL Service: ready endpoint 없음
  - `kubectl get endpointslice -n blog -l kubernetes.io/service-name=mysql`에서 `ready: false`
- MySQL Pod: `mysql-0`가 NotReady (`1/2`)

## 원인

- Vault/VSO
  - `kv/blog/prod/mysql-exporter` 시크릿이 없거나, Vault policy/role 권한 문제로 VSO가 `mysql-exporter-secret`(Kubernetes Secret)을 생성하지 못함
  - 결과: `mysql-exporter` 컨테이너가 시작 불가(CreateContainerConfigError)
- mysql-exporter 컨테이너 설정
  - `DATA_SOURCE_NAME`을 `$(MYSQL_EXPORTER_USER)` 형태로 조합하도록 설정되어 있었음
  - 실제 런타임에서 mysqld-exporter가 유효한 DSN을 받지 못해 즉시 종료(CrashLoopBackOff)
  - 결과: MySQL Pod Ready가 False로 남아 MySQL Service가 트래픽을 받지 못함

## 영향 범위

- MySQL Pod Ready가 False가 되면, ClusterIP Service가 있어도 Ghost에서 DB 연결이 실패할 수 있음
- Argo CD(autosync/self-heal) 환경에서는 수동 패치가 쉽게 원복될 수 있으므로, 최종 수정은 main 반영(PR 머지)로 해결해야 함

## 조치

### 1) Vault 시크릿/정책 정합성 확보

- Vault policy `mysql`에 아래 경로 read 권한 포함
  - `kv/data/blog/prod/mysql`
  - `kv/data/blog/prod/mysql-exporter`
- Vault에 exporter 시크릿 생성
  - 경로: `kv/blog/prod/mysql-exporter`
  - 키: `user`, `password`
- VSO 동기화로 Kubernetes Secret 생성 확인
  - `blog/mysql-exporter-secret`

### 2) mysql-exporter 컨테이너가 DSN을 안정적으로 설정하도록 수정

- mysqld-exporter 실행 전에 `MYSQL_EXPORTER_USER/PASSWORD`로 `DATA_SOURCE_NAME`을 구성하도록 수정
- 수정 파일: `apps/ghost/base/mysql-statefulset.yaml`

## 검증 절차(조회 명령)

```bash
# 1) Vault/VSO 상태
kubectl get vaultstaticsecret -n blog mysql-exporter-secret
kubectl describe vaultstaticsecret -n blog mysql-exporter-secret | tail -80
kubectl get secret -n blog mysql-exporter-secret

# 2) MySQL Pod/Service endpoint readiness
kubectl get pod -n blog mysql-0
kubectl get endpointslice -n blog -l kubernetes.io/service-name=mysql -o yaml | grep -n \"ready:\"

# 3) exporter 로그
kubectl logs -n blog mysql-0 -c mysql-exporter --tail=200

# 4) Ghost 로그
kubectl logs -n blog deployment/ghost --tail=200
```

## 재발 방지 체크리스트

- Vault 시크릿 경로/키가 문서와 매니페스트(VSO 경로, Secret key)와 일치하는지 확인
- exporter/sidecar 장애가 DB readiness를 막는 구조인지 확인(필요 시 분리 검토)
- `.env` 등 로컬 민감 파일이 Git에 커밋되지 않도록 ignore 처리 확인


