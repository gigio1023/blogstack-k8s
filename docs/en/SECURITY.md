# Security Guide

Least-privilege configuration summary

## Argo CD AppProject

`clusters/prod/project.yaml` explicitly limits allowed source/destination namespaces

Set accurate repo URL in production

## Pod Security Standards (PSS)

Each overlay includes `Namespace` resource with labels:
- `pod-security.kubernetes.io/enforce: baseline`
- `pod-security.kubernetes.io/warn: restricted`

## NetworkPolicy

- `blog` namespace: Default ingress deny, `ghost` allows ingress-controller only, `mysql` allows `ghost` only
- `cloudflared`: Default ingress deny, allows metrics from `observers` only
- `vault`: Default ingress deny, allows 8200 from `vso`/`observers` only

## Vault + VSO

- Dedicated `ServiceAccount` (vault-reader) and `VaultAuth` per namespace
- Vault Kubernetes Auth Roles separated by namespace/SA
  - Example: `blog` role binds to `ns=blog, sa=vault-reader`, `cloudflared` role to `ns=cloudflared, sa=vault-reader`
- TLS starts disabled (HTTP), consider mTLS or Ingress TLS termination later

## Ingress Controller Hardening

Applied settings:
- `use-forwarded-headers`, `real-ip`, Cloudflare CIDR
- Upload/large request support:
  - `proxy-body-size: 50m`
  - `proxy-read-timeout: 600`, `proxy-send-timeout: 600`

## Secret Storage

- Public values: `config/prod.env`
- Sensitive values: Vault (synced to app namespaces via VSO)

