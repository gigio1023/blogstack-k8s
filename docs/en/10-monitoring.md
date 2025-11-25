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

## Prerequisites

Before starting the monitoring configuration, ensure the following conditions are met.

### 1. Verify Monitoring Stack Deployment via ArgoCD

The `observers` application must be successfully deployed for Prometheus, Grafana, and Loki to be installed.

```bash
# Check ArgoCD Application Status
kubectl get application observers -n argocd

# Expected output: observers   Synced   Healthy
```

> [!WARNING]
> If the `observers` application is missing or in a `Degraded` state, complete [02-argocd-setup.md](./02-argocd-setup.md) first.

### 2. Verify Prometheus Operator CRDs

Check for the CRDs created during the Prometheus Operator installation.

```bash
# Check Prometheus CRD
kubectl get crd prometheuses.monitoring.coreos.com

# Check ServiceMonitor CRD
kubectl get crd servicemonitors.monitoring.coreos.com

# Check Probe CRD (for Blackbox Exporter)
kubectl get crd probes.monitoring.coreos.com
```

If CRDs are missing, ArgoCD has not yet deployed `observers` or the deployment failed.

### 3. Verify Monitoring Pod Status

```bash
# Check Prometheus, Grafana, Loki Pods
kubectl get pods -n observers

# Expected output:
# prometheus-kube-prometheus-stack-prometheus-0   2/2   Running
# kube-prometheus-stack-grafana-xxx               3/3   Running
# kube-prometheus-stack-operator-xxx              1/1   Running
# loki-0                                          1/1   Running
# promtail-xxx                                    1/1   Running
```

### Verification Script (Optional)

To automatically verify the prerequisites:

```bash
# Run from project root
bash scripts/check-monitoring-prerequisites.sh
```

## Configuration Steps

### 1. Verify Monitoring Stack Configuration

The `apps/observers` application is based on the `kube-prometheus-stack` Helm chart.

Related file:
- [apps/observers/base/kustomization.yaml](../../apps/observers/base/kustomization.yaml)

Key settings:
- `serviceMonitorSelector: {}`: Scrape all ServiceMonitors
- `serviceMonitorNamespaceSelector: {}`: Scrape all Namespaces

```bash
# Verify Prometheus configuration (Check if it scrapes all ServiceMonitors)
kubectl get prometheus -n observers -o yaml | grep -A 2 serviceMonitorSelector
# Confirm serviceMonitorSelector: {}
```

### 2. MySQL Monitoring

Add a sidecar container and ServiceMonitor to collect Ghost database metrics.

#### Prepare Exporter Credentials

Create a dedicated MySQL user with minimal privileges and store it in Vault for VSO sync.

```bash
# Check Vault policy and secret
vault policy read mysql
kubectl get secret -n blog mysql-exporter-secret
```

#### Add Exporter Sidecar

Verify that the `mysql-exporter` container has been added to the `mysql` StatefulSet.

```bash
kubectl get statefulset mysql -n blog -o jsonpath='{.spec.template.spec.containers[*].name}'
# Output: mysql mysql-exporter
```

#### Create ServiceMonitor and Service

Create resources to allow Prometheus to access the Exporter.

```bash
# Verify Service (Port 9104)
kubectl get svc -n blog mysql-exporter

# Verify ServiceMonitor
kubectl get servicemonitor -n blog mysql-exporter
```

### 3. Ingress and Availability Monitoring

#### Ingress NGINX Metrics

Verify if metric collection is enabled for the Ingress Controller.

```bash
# Verify metric enablement (metrics.enabled=true)
kubectl get deployment -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.template.spec.containers[0].args}' | grep metrics

# Verify ServiceMonitor
kubectl get servicemonitor -n ingress-nginx ingress-nginx-controller
```

#### Blackbox Probing

Verify the Probe resource for external URL health checks.

```bash
# Verify Probe resource
kubectl get probe -n observers blog-external
```

## Verification and Check

### 1. Check Pod Status

Verify that the key components of the monitoring stack are running correctly.

```bash
kubectl get pods -n observers
# prometheus-kube-prometheus-stack-prometheus-0 (Running)
# kube-prometheus-stack-grafana-xxx (Running)
# kube-prometheus-stack-operator-xxx (Running)
# loki-0 (Running)
# promtail-xxx (Running)
```

### 2. Verify Prometheus Targets

Verify that Prometheus is successfully scraping each Exporter.

```bash
# Port forwarding
kubectl port-forward -n observers svc/kube-prometheus-stack-prometheus 9090:9090 &
```

1. Access browser: `http://localhost:9090/targets`
2. Check for `UP` state for key Targets:
   - `serviceMonitor/blog/mysql-exporter/0`: MySQL Exporter
   - `serviceMonitor/ingress-nginx/ingress-nginx-controller/0`: Ingress Controller
   - `serviceMonitor/observers/kube-prometheus-stack-node-exporter/0`: Node Exporter

### 3. Verify Grafana Dashboards

Verify that collected metrics are being visualized.

```bash
# Port forwarding
kubectl port-forward -n observers svc/kube-prometheus-stack-grafana 3000:80 &
```

1. Access browser: `http://localhost:3000`
   - Credentials: `admin` / `admin` (Initial default)
2. Check essential dashboards:
   - **MySQL Overview** (ID: 7362): Check 'MySQL Connections', 'Questions' graph data
   - **NGINX Ingress Controller** (ID: 9614): Check 'Controller Request Volume', 'Success Rate'
   - **Kubernetes / Compute Resources / Namespace (Pods)**: Select `blog` namespace and check Ghost Pod resources

### 4. Verify Log Collection (Loki)

Verify that logs are searchable in the Grafana Explore tab.

1. Go to Grafana → Explore menu
2. Select Data Source: `Loki`
3. Enter and run LogQL:
   ```logql
   {namespace="blog", app="ghost"}
   ```

## Troubleshooting

### Target is Down

1. **MySQL Exporter Down**:
   - Check Exporter logs:
     ```bash
     kubectl logs -n blog mysql-0 -c mysql-exporter
     ```
   - Check Credentials (Secret): Verify `mysql-exporter-secret` is mounted correctly

2. **Ingress NGINX Down**:
   - Check ServiceMonitor label matching:
     ```bash
     kubectl get servicemonitor -n ingress-nginx ingress-nginx-controller -o yaml
     # matchLabels must match the Service's labels
     ```

### No Data in Grafana

1. Check Time Range: Ensure the Time Range in the top right is set to a recent time.
2. Check Prometheus Data Source Connection: Configuration → Data Sources → Prometheus → 'Save & Test'
