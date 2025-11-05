#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

KUSTOMIZE=${KUSTOMIZE:-kustomize}
KUBECONFORM=${KUBECONFORM:-kubeconform}

if ! command -v "$KUSTOMIZE" >/dev/null 2>&1; then
  echo "[!] kustomize not found in PATH. Install kustomize to run this script." >&2
  exit 1
fi

validate_overlay() {
  local path="$1"
  echo "\n=== VALIDATE: ${path} ==="
  "$KUSTOMIZE" build "$path" >/tmp/manifest.yaml
  echo "[ok] kustomize build"
  if command -v "$KUBECONFORM" >/dev/null 2>&1; then
    "$KUBECONFORM" -strict -summary </tmp/manifest.yaml
  else
    echo "[i] kubeconform not installed; skipping schema validation"
  fi
}

# app overlays (prod)
validate_overlay "$ROOT_DIR/apps/observers/overlays/prod"
validate_overlay "$ROOT_DIR/apps/observers-probes/overlays/prod"
validate_overlay "$ROOT_DIR/apps/ingress-nginx/overlays/prod"
validate_overlay "$ROOT_DIR/apps/cloudflared/overlays/prod"
validate_overlay "$ROOT_DIR/apps/ghost/overlays/prod"

# security stacks
validate_overlay "$ROOT_DIR/security/vault"
validate_overlay "$ROOT_DIR/security/vso-operator"
validate_overlay "$ROOT_DIR/security/vso-resources"

echo "\nAll validations completed."


