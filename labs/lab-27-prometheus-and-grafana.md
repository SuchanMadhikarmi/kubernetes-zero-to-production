# Lab 27 - Observability Deep Dive (Prometheus and Grafana)

## Prerequisite

- Completion of [Lesson 27 - Observability Deep Dive (Prometheus and Grafana)](../docs/08-observability/lesson-27-observability-deep-dive-prometheus-and-grafana.md).
- A running kind cluster.
- kubectl and helm installed.

## Objective

Install the kube-prometheus-stack, explore the dashboards, run PromQL queries, and finish with a custom Flask app that exposes a `/metrics` endpoint consumed by Prometheus via a ServiceMonitor.

## Estimated Time

25 minutes.

---

## Step 1: Add the Helm repo and install the stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
kubectl get pods -n monitoring -w
```

Expected: after one to two minutes all pods in `monitoring` are `Running`, including `prometheus-*`, `grafana-*`, `alertmanager-*`, and the node-exporter DaemonSet.

## Step 2: Access Grafana

```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
```

Open `http://localhost:3000`. Login: `admin` / `prom-operator`. Open Dashboards -> Browse -> "Kubernetes / Compute Resources / Cluster".

Expected: live CPU/memory graphs of the cluster.

## Step 3: Access Prometheus and run PromQL

In a second terminal:

```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
```

Open `http://localhost:9090` and run:

```promql
container_cpu_usage_seconds_total
rate(container_cpu_usage_seconds_total[5m])
up
```

Expected: raw counters, a per-second rate, and target up/down series. In Status -> Targets you should see many green `Up` targets.

## Step 4: Deploy an app that exports metrics

Create a small Flask app exposing `/metrics`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: metrics-app
  template:
    metadata:
      labels:
        app: metrics-app
    spec:
      containers:
      - name: app
        image: prom/client_golang-example  # any exporter image works
        ports:
        - name: metrics
          containerPort: 8080
        readinessProbe:
          httpGet:
            path: /metrics
            port: metrics
---
apiVersion: v1
kind: Service
metadata:
  name: metrics-app
  labels:
    app: metrics-app
spec:
  selector:
    app: metrics-app
  ports:
  - name: metrics
    port: 8080
    targetPort: metrics
```

Apply and start the app:

```bash
kubectl apply -f app.yaml
kubectl get pods -l app=metrics-app
```

## Step 5: Create the ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: metrics-app
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: metrics-app
  endpoints:
  - port: metrics
    path: /metrics
    interval: 15s
```

```bash
kubectl apply -f servicemonitor.yaml
```

Prompt check in Prometheus: open Status -> Targets and look for the new `metrics-app` target; its state should be `Up`.

## Step 6: Verify custom metrics

In Prometheus, run:

```promql
up{service="metrics-app"}
```

Expected: a series with value `1` for the new target, proving Prometheus is scraping your custom Service.

## Cleanup

```bash
# Ctrl+C in the two port-forward terminals
kubectl delete -f servicemonitor.yaml -f app.yaml
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring
```

## Summary

You installed the full monitoring stack, drove both Grafana dashboards and PromQL queries, instrumented a Service with a ServiceMonitor, and confirmed Prometheus scrapes your custom target.