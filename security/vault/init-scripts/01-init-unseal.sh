#!/usr/bin/env bash
set -euo pipefail

# NOTE: This script is a guide. Do NOT hardcode sensitive values.
# 1) Port-forward Vault service, or run from within cluster context.
# 2) Initialize Vault (Shamir keys), unseal, enable audit & Kubernetes auth.

VAULT_ADDR=${VAULT_ADDR:-http://127.0.0.1:8200}

echo "[i] Initializing Vault..."
INIT_JSON=$(curl -s -X POST "$VAULT_ADDR/v1/sys/init" \
  -H 'Content-Type: application/json' \
  -d '{"secret_shares": 5, "secret_threshold": 3}')

echo "$INIT_JSON" | jq . > init-output.json
echo "[i] Init output saved to init-output.json (store unseal keys & root token offline)"

ROOT_TOKEN=$(jq -r .root_token init-output.json)
UNSEAL_KEYS=$(jq -r '.keys_base64[]' init-output.json)

echo "[i] Unsealing..."
for k in $UNSEAL_KEYS; do
  curl -s -X POST "$VAULT_ADDR/v1/sys/unseal" -H 'Content-Type: application/json' -d "{\"key\":\"$k\"}" >/dev/null
done

echo "[i] Enabling audit (file)..."
curl -s -X PUT "$VAULT_ADDR/v1/sys/audit/file" \
  -H "X-Vault-Token: $ROOT_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"type":"file","options":{"path":"/vault/logs/audit.log"}}' >/dev/null || true

echo "[i] Enabling Kubernetes auth..."
curl -s -X POST "$VAULT_ADDR/v1/sys/auth/kubernetes" \
  -H "X-Vault-Token: $ROOT_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"type":"kubernetes"}' >/dev/null || true

echo "[i] Done. Now configure roles/policies and KV v2 at mount \"kv\"."

