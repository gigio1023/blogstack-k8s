#!/usr/bin/env bash
set -euo pipefail

NS=${NS:-argocd}

echo "[i] Patching argocd-cm to enable kustomize Helm support and relax load restrictor"
kubectl patch configmap argocd-cm -n "$NS" --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm --load-restrictor LoadRestrictionsNone"}}'

echo "[i] Restarting repo-server"
kubectl rollout restart deployment argocd-repo-server -n "$NS"
kubectl rollout status deployment argocd-repo-server -n "$NS"

echo "[ok] Argo CD repo-server configured"


