# Environments (dev/prod)

Multi-environment support

## Config Files

- `config/prod.env`: Production settings
- `config/dev.env`: Development settings

## Kustomize Overlays

- dev: `apps/*/overlays/dev` (namespace: `*-dev`)
- prod: `apps/*/overlays/prod`

## Argo CD Root (Example)

- prod: `iac/argocd/root-app.yaml` → `clusters/prod`
- dev: Create separate Root App → `clusters/dev`

## Injection

- Domain/URL: `config/<env>.env` → ConfigMap → replacements
- Secrets: Vault (shared), namespaces per environment

## Deployment Order (Same)

observers → ingress-nginx → cloudflared → vault → vso → ghost

