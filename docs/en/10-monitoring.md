# 10. Monitoring Setup

Unified monitoring infrastructure based on Prometheus, Grafana, and Loki.

## Overview

- **Metrics**: Prometheus (Pull-based)
- **Visualization**: Grafana
- **Logs**: Loki + Promtail
- **Availability**: Blackbox Exporter (HTTP Probing)
- **Components**:
  - Node Exporter: Infrastructure resources
  - MySQL Exporter: DB performance metrics (Sidecar)
  - Ingress NGINX: Web traffic and error rates

## Configuration Steps

### 1. Verify Monitoring Stack

The `apps/observers` application is based on the `kube-prometheus-stack` Helm chart.

Related file:
- [apps/observers/base/kustomization.yaml](../../apps/observers/base/kustomization.yaml)

Key settings:
- `serviceMonitorSelector: {}`: Scrape all ServiceMonitors
- `serviceMonitorNamespaceSelector: {}`: Scrape all Namespaces

### 2. MySQL Monitoring

Add a sidecar container and ServiceMonitor to collect Ghost database metrics.

#### Add Exporter Sidecar

Add the `prom/mysqld-exporter` container to the `mysql` StatefulSet.

Related file:
- [apps/ghost/base/mysql-statefulset.yaml](../../apps/ghost/base/mysql-statefulset.yaml)

#### Create ServiceMonitor and Service

Create resources to allow Prometheus to access the Exporter.

Related files:
- [apps/ghost/base/mysql-exporter-service.yaml](../../apps/ghost/base/mysql-exporter-service.yaml)
- [apps/ghost/base/mysql-servicemonitor.yaml](../../apps/ghost/base/mysql-servicemonitor.yaml)
- [apps/ghost/base/kustomization.yaml](../../apps/ghost/base/kustomization.yaml)

### 3. Ingress and Availability Monitoring

#### Ingress NGINX Metrics

Enable metric collection for the Ingress Controller.

Related file:
- [apps/ingress-nginx/base/kustomization.yaml](../../apps/ingress-nginx/base/kustomization.yaml)

Configuration:
- `controller.metrics.enabled: true`
- `controller.metrics.serviceMonitor.enabled: true`

#### Blackbox Probing

Perform health checks on external URLs.

Related file:
- [apps/observers-probes/base/probe.yaml](../../apps/observers-probes/base/probe.yaml)

## Verification

### Access Grafana

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n observers 3000:80
```
- URL: `http://localhost:3000`
- Credentials: `admin` / `admin`

### Key Dashboards

1. **Kubernetes / Compute Resources / Namespace (Pods)**: Ghost resource usage
2. **MySQL Overview**: DB connections, query performance (ID: 7362)
3. **NGINX Ingress Controller**: Traffic, response times (ID: 9614)
