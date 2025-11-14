# 07. SMTP 이메일 설정

Ghost 비밀번호 재설정, 초대, 알림 기능을 위한 SMTP 설정

## 전제 조건

- 03-vault-setup.md 완료
- Ghost Pod Running
- Mailgun 계정 준비 (00-prerequisites.md)

## 필수 이유

Ghost는 staff device verification 및 비밀번호 재설정 시 이메일 발송 필수:
- 비밀번호 재설정 불가
- 관리자 초대 불가
- 로그인 시 "Failed to send email" 오류

## Mailgun SMTP 정보 확인

### 1. Mailgun Dashboard

https://app.mailgun.com/ 로그인

### 2. SMTP 자격증명

Sending → Domains → `mg.yourdomain.com` → SMTP Credentials

| 항목 | 예시 | 설명 |
|------|------|------|
| Host | `smtp.mailgun.org` | 미국 (유럽: `smtp.eu.mailgun.org`) |
| Port | `587` | TLS |
| Username | `postmaster@mg.yourdomain.com` | SMTP 사용자명 |
| Password | `abc123xyz...` | SMTP 비밀번호 |

### 3. 발신 이메일

- `noreply@yourdomain.com` (권장)
- `hello@yourdomain.com`
- `admin@yourdomain.com`

발신 주소는 Mailgun 인증 도메인이어야 함

## Vault에 SMTP 설정 추가

### 1. Vault port-forward

```bash
kubectl port-forward -n vault svc/vault 8200:8200 > /dev/null 2>&1 &
sleep 2
```

### 2. 환경변수

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r .root_token security/vault/init-scripts/init-output.json)
```

### 3. SMTP 설정 추가

대문자 부분을 실제 정보로 교체:

```bash
vault kv patch kv/blog/prod/ghost \
  mail__transport="SMTP" \
  mail__options__service="Mailgun" \
  mail__options__host="smtp.mailgun.org" \
  mail__options__port="587" \
  mail__options__secure="false" \
  mail__options__auth__user="postmaster@mg.yourdomain.com" \
  mail__options__auth__pass="YOUR_MAILGUN_PASSWORD" \
  mail__from="'Your Blog Name' <noreply@yourdomain.com>"
```

예시 (유럽 리전):
```bash
vault kv patch kv/blog/prod/ghost \
  mail__transport="SMTP" \
  mail__options__service="Mailgun" \
  mail__options__host="smtp.eu.mailgun.org" \
  mail__options__port="587" \
  mail__options__secure="false" \
  mail__options__auth__user="postmaster@mg.yourdomain.com" \
  mail__options__auth__pass="your-password-here" \
  mail__from="'My Blog' <noreply@yourdomain.com>"
```

### 4. 설정 확인

```bash
vault kv get -format=json kv/blog/prod/ghost | jq -r '.data.data' | grep mail__
```

## VSO 및 Ghost 재시작

### 1. VSO Pod 재시작

```bash
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator

# Pod 재생성 대기 (10초)
kubectl get pods -n vso -w
# Ctrl+C로 종료

# Secret 동기화 확인 (30초 대기)
kubectl get secret ghost-env -n blog -o jsonpath='{.data.mail__options__auth__pass}' | base64 -d
# Mailgun 비밀번호 출력 확인
```

### 2. Ghost Pod 재시작

```bash
kubectl rollout restart deployment ghost -n blog
kubectl rollout status deployment ghost -n blog

# 상태 확인
kubectl get pods -n blog
# ghost-xxx: 1/1 Running
```

## 이메일 기능 테스트

### 1. Ghost Admin 접속

`https://yourdomain.com/ghost/` 접속

### 2. 테스트 이메일 발송

Ghost Admin → Settings → Labs → Send test email

받는 사람: 본인 이메일 입력 → Send

### 3. 이메일 수신 확인

- 받은편지함에서 Ghost 테스트 이메일 확인
- 발신자: `mail__from`에 설정한 주소
- 스팸함도 확인

### 4. 비밀번호 재설정 테스트

로그아웃 → Forgot password → 이메일 입력 → 링크 수신 확인

## 트러블슈팅

### "Failed to send email"

```bash
# Ghost 로그 확인
kubectl logs -n blog deployment/ghost --tail=50 | grep -i mail

# 일반 원인:
# - mail__options__auth__pass 오타
# - mail__options__host 오타 (smtp.mailgun.org / smtp.eu.mailgun.org)
# - Mailgun domain verification 미완료
```

### Secret 동기화 안됨

```bash
# VaultStaticSecret 상태
kubectl describe vaultstaticsecret ghost -n vso

# VSO 재시작
kubectl delete pod -n vso -l app.kubernetes.io/name=vault-secrets-operator
kubectl get pods -n vso -w
```

### Ghost Pod CrashLoopBackOff

```bash
kubectl logs -n blog deployment/ghost --tail=100

# MySQL 연결 확인
kubectl exec -n blog mysql-0 -- mysql -u ghost -p$(kubectl get secret -n blog mysql-secret -o jsonpath='{.data.password}' | base64 -d) ghost -e "SELECT 1;"
```

### Mailgun 인증 실패

Mailgun Dashboard:
- Domain verification: Verified 확인
- SMTP credentials: Username, Password 재확인
- Sending limits: 월 한도 초과 확인

Cloudflare DNS:
- SPF, DKIM, MX 레코드 확인
- Proxy Status: DNS only (회색)

## 다음 단계

→ [08-operations.md](./08-operations.md) - 운영 및 유지보수
