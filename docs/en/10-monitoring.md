# 10. Monitoring Setup

Unified monitoring infrastructure based on VictoriaMetrics, Grafana, and Loki.

## Overview

- **Metrics**: VictoriaMetrics (vmagent → vmsingle)
- **Visualization**: Grafana
- **Logs**: Loki + Promtail
- **Availability**: Blackbox Exporter (HTTP Probing)
- **Components**:
  - MySQL Exporter: DB performance metrics (Sidecar)
  - Ingress NGINX: Web traffic and error rates
  - Cloudflared: Tunnel health and connections
  - Vault: Internal metrics API

## Prerequisites

### 1. Verify Monitoring Stack Deployment via ArgoCD

The `observers` application must be deployed.

```bash
kubectl get application observers -n argocd
# Expected: observers   Synced   Healthy
```

> [!WARNING]
> If the `observers` application is missing or in a `Degraded` state, complete [02-argocd-setup.md](./02-argocd-setup.md) first.

### 2. Check Monitoring Pods

```bash
kubectl get pods -n observers

# Expected:
# vmsingle-0                           1/1   Running
# vmagent-xxx                          1/1   Running
# grafana-xxx                          1/1   Running
# loki-0                               1/1   Running
# promtail-xxx                         1/1   Running
# blackbox-exporter-xxx                1/1   Running
```

### Validation Script (Optional)

```bash
# Run from repo root
bash scripts/check-monitoring-prerequisites.sh
```

## Configuration

### 1. Stack Composition

`apps/observers` uses these Helm charts:

- `victoria-metrics-single`
- `victoria-metrics-agent`
- `grafana`
- `loki`, `promtail`
- `prometheus-blackbox-exporter`

Related file:
- `apps/observers/base/kustomization.yaml`

### 2. vmagent Scrape Config

vmagent reads the `scrape.yml` from the `vmagent-scrape` ConfigMap.

- Base config: `apps/observers/base/vmagent-scrape.yml`
- prod values: replaced by `apps/observers/overlays/prod/vmagent-scrape.yml`

Targets managed in the scrape config:
- MySQL Exporter
- Ingress NGINX
- Cloudflared
- Vault
- Blackbox Exporter (external URLs)

### 3. MySQL Monitoring

```bash
kubectl get statefulset mysql -n blog -o jsonpath='{.spec.template.spec.containers[*].name}'
# Output: mysql mysql-exporter

kubectl get svc -n blog mysql-exporter
```

### 4. Ingress / Vault / Cloudflared

```bash
# Ingress NGINX metrics enabled
kubectl get deployment -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.template.spec.containers[0].args}' | grep metrics

# Cloudflared metrics service
kubectl get svc -n cloudflared cloudflared

# Vault metrics API
kubectl get svc -n vault vault
```

### 5. Blackbox Probing

```bash
kubectl get configmap -n observers vmagent-scrape -o yaml
```

## Validation

### 1. vmagent Targets

```bash
kubectl port-forward -n observers svc/vmagent 8429:8429 &
# http://localhost:8429/targets
```

Check `UP` status for:
- `mysql-exporter`
- `ingress-nginx`
- `cloudflared`
- `vault`
- `blackbox`

### 2. vmsingle UI

```bash
kubectl port-forward -n observers svc/vmsingle 8428:8428 &
# http://localhost:8428/vmui
```

Example queries:
- `up`
- `probe_success{job="blackbox"}`

### 3. Grafana Dashboards

```bash
kubectl port-forward -n observers svc/grafana 3000:80 &
# http://localhost:3000
# admin / admin (default)
```

Required dashboards:
- **MySQL Overview** (ID: 7362)
- **NGINX Ingress Controller** (ID: 9614)
- **Kubernetes / Compute Resources / Namespace (Pods)**

### 4. Log Verification (Loki)

```logql
{namespace="blog", app="ghost"}
```

## Troubleshooting

See [09-troubleshooting.md](./09-troubleshooting.md).
