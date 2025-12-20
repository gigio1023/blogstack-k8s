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
  local kubeconform_opts="${2:-}"
  echo "\n=== VALIDATE: ${path} ==="
  "$KUSTOMIZE" build --enable-helm --load-restrictor=LoadRestrictionsNone "$path" >/tmp/manifest.yaml
  echo "[ok] kustomize build"
  if command -v "$KUBECONFORM" >/dev/null 2>&1; then
    if [[ "$kubeconform_opts" == "SKIP" ]]; then
      echo "[i] kubeconform skipped for this overlay"
    else
      "$KUBECONFORM" -strict -summary $kubeconform_opts </tmp/manifest.yaml
    fi
  else
    echo "[i] kubeconform not installed; skipping schema validation"
  fi
}

# app overlays (prod)
validate_overlay "$ROOT_DIR/apps/observers/overlays/prod"
validate_overlay "$ROOT_DIR/apps/ingress-nginx/overlays/prod"
validate_overlay "$ROOT_DIR/apps/cloudflared/overlays/prod"
validate_overlay "$ROOT_DIR/apps/ghost/overlays/prod"

# security stacks
validate_overlay "$ROOT_DIR/security/vault"
validate_overlay "$ROOT_DIR/security/vso-operator" "-skip CustomResourceDefinition"
validate_overlay "$ROOT_DIR/security/vso-resources" "SKIP"

echo "\nAll validations completed."
