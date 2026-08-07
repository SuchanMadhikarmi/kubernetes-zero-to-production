---
title: Lesson 27 - Observability Deep Dive (Prometheus and Grafana)
module: 08 Observability
lesson: 27
status: Complete
tags: [kubernetes, prometheus, grafana, promql, alertmanager, servicemonitor, monitoring, observability, helm]
---

# Lesson 27 - Observability Deep Dive (Prometheus and Grafana)

## Table of Contents

- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Real-world Motivation](#real-world-motivation)
- [Core Concepts](#core-concepts)
- [Architecture](#architecture)
- [ASCII Diagrams](#ascii-diagrams)
- [Hands-on](#hands-on)
- [Commands](#commands)
- [YAML Explanation](#yaml-explanation)
- [Production Notes](#production-notes)
- [Best Practices](#best-practices)
- [Common Mistakes](#common-mistakes)
- [Troubleshooting](#troubleshooting)
- [Interview Questions](#interview-questions)
- [Scenario Questions](#scenario-questions)
- [Quiz](#quiz)
- [Revision](#revision)
- [Cheat Sheet](#cheat-sheet)
- [References](#references)
- [Related Lessons](#related-lessons)
- [Coming Next](#coming-next)

---

## Learning Objectives

By the end of this lesson you will be able to:

- Describe the architecture of a modern Kubernetes monitoring stack: Prometheus, Grafana, and Alertmanager.
- Explain the difference between the Metrics Server and Prometheus.
- Explain how Prometheus uses a pull model to scrape metrics from `/metrics` endpoints.
- Install the kube-prometheus-stack via Helm.
- Run a PromQL query to find CPU usage.

## Prerequisites

- Completion of Lessons 1 through 42.
- A running kind cluster.
- kubectl and helm installed.
- Clean up leftover resources from previous lessons (`kubectl delete deploy --all`, `kubectl delete svc --all`) before starting.

## Real-world Motivation

### From Lesson

The blind SRE: the Kubernetes Metrics Server is like a snapshot camera. It tells you how much CPU is being used right now, but it does not save history. At 3 AM a user reports the API was slow. You check `kubectl top pods`, but CPU is normal now. You have no idea what happened at 3 AM because the snapshot is gone. You are flying blind.

Why this exists: to record everything 24/7. Prometheus is a time-series database. It scrapes metrics from your Pods every 15 seconds and saves the data for months. Grafana is the TV screen you use to watch the historical recordings and build graphs. If the API was slow at 3 AM, you can open a Grafana dashboard and see exactly which Pod spiked in CPU at 3:05 AM.

### Additional Production Knowledge

Monitoring is the beginning, not the end, of observability. Metrics answer "what" and "how much" but not "why" or "how". A production observability practice combines the Prometheus metrics you build here with structured logs (Loki) and traces (Tempo/Jaeger) in the classic three pillars. Also, dashboards are a liability if nobody reviews them: page-worthy alerts tied to clear SLOs, consumed by a small on-call rotation, keep the stack from becoming an expensive petting zoo that nobody watches.

## Core Concepts

### From Lesson

- **Prometheus**: A time-series database that scrapes (pulls) metrics from applications every 15 seconds and stores them with a timestamp.
- **Grafana**: A visualization tool. It queries Prometheus and draws beautiful graphs.
- **Pull model**: Prometheus makes an HTTP GET request to a Pod's `/metrics` endpoint. If the Pod does not expose `/metrics`, Prometheus cannot scrape it.
- **PromQL**: Prometheus Query Language, used to ask Prometheus for data (e.g. "give me the average CPU usage over the last 5 minutes").
- **ServiceMonitor**: A Custom Resource Definition (CRD) used to tell Prometheus which Kubernetes Services to scrape.

### Additional Production Knowledge

- **Node Exporter**: an agent that runs on every node (via DaemonSet) and exposes host-level metrics (`node_cpu_seconds_total`, `node_memory_MemTotal_bytes`). Without it you see container CPU but not the node's actual memory pressure.
- **kube-state-metrics**: the exporter that turns Kubernetes object count and state into metrics (`kube_pod_status_ready`, `kube_deployment_status_replicas`). Combined with node-exporter, kube-prometheus can answer "how many ready replicas does my app have" as a time-series.
- **Pushgateway + push model**: Prometheus is pull-first, but batch jobs that exit before a scrape still must keep you working via the Pushgateway. That's an exception, not the rule.

## Architecture

### From Lesson

Prometheus does not wait for apps to push data to it. It actively pulls (scrapes) data from the applications.

```text
[ Pod (app) ] <--- (GET /metrics) --- [ Prometheus ]
      |                                    |
      | (Exports metrics)                  | (Stores TSDB)
      v                                    v
[ /metrics endpoint ]                  [ Grafana ] (Queries Prometheus to draw graphs)
                                        [ Alertmanager ] (Fires notifications if metrics cross thresholds)
```

### Additional Production Knowledge

The kube-prometheus-stack chart actually deploys not one but several related components: Prometheus (operator + statefulset), Alertmanager, Grafana, and node-exporter and kube-state-metrics DaemonSets/Deployments, plus the Prometheus CRDs (ServiceMonitor, PodMonitor, PrometheusRule). The Prometheus Operator watches these CRDs and reconciles the running Prometheus configuration automatically, which is why adding a ServiceMonitor is enough to change what gets scraped.

## ASCII Diagrams

### From Lesson

```text
[ Pod (app) ] <--- (GET /metrics) --- [ Prometheus ]
      |                                     |
      | (Exports metrics)                   | (Stores TSDB)
      v                                     v
[ /metrics endpoint ]                  [ Grafana ] (Queries Prometheus to draw graphs)
                                       [ Alertmanager ]
```

### Additional Production Knowledge

```text
kube-prometheus-stack (Helm)               Pod discovery
 - prometheus-operator  -> watches -------->  ServiceMonitor
 - prometheus (StatefulSet)                --------> Service -> Pod (app)
 - alertmanager (notification)
 - grafana (UI)
 - node-exporter (DaemonSet, host metrics)
 - kube-state-metrics (object metrics)
```

## Hands-on

### From Lesson

Goal: install the kube-prometheus-stack, access Grafana, and run a PromQL query.

Step 1 - Add the Helm repo:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

Step 2 - Install the stack into a `monitoring` namespace:

```bash
helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
```

This installs Prometheus, Grafana, Alertmanager, node-exporter, and kube-state-metrics.

Step 3 - Wait roughly a minute for the many container images, then verify:

```bash
kubectl get pods -n monitoring
```

Wait until all pods are `Running`.

Step 4 - Access Grafana UI:

```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
```

Open `http://localhost:3000`. Username `admin`, password `prom-operator`.

Step 5 - Explore dashboards (Dashboards -> Browse -> "Kubernetes / Compute Resources / Cluster"). You are looking at live CPU/Memory of the kind cluster.

Step 6 - Access Prometheus UI (third terminal):

```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
```

Go to `http://localhost:9090`. Enter `container_cpu_usage_seconds_total`, click Execute, switch to the Graph tab to see raw per-container CPU counters.

Cleanup:

```bash
# Ctrl+C in the two port-forward terminals
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring
```

## Commands

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

kubectl get pods -n monitoring
kubectl get crd | grep mon-   # list the operator CRDs

kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring

# Example PromQL
container_cpu_usage_seconds_total
rate(container_cpu_usage_seconds_total[5m])
up

helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring
```

## YAML Explanation

Below are the two building blocks you will encounter when instrumenting your own app: the Service that Prometheus discovers, and the ServiceMonitor telling Prometheus what to pull.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  selector:
    app: myapp
  ports:
  - port: 8080
    targetPort: metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: myapp
  endpoints:
  - port: metrics
    path: /metrics
    interval: 15s
```

- The `ServiceMonitor` `selector.matchLabels.app: myapp` must match the Service's labels. If they don't, Prometheus with the discovered service and scraping nothing.
- The `endpoints[].port` must reference a named port in the Service, not a number. It resolves to ServicePort `port: 8080`; Prometheus scrapes `http://<pod-ip>:<port>/metrics` every 15s.
- The ServiceMonitor is created in namespace `monitoring` and Prometheus is configured (by default) to watch ServiceMonitors across all namespaces, or only in its own namespace depending on `spec.serviceMonitorNamespaceSelector`.

## Production Notes

### From Lesson

- Set retention: Prometheus stores data locally. If you do not set a limit (`--storage.tsdb.retention.time=15d`), the disk fills up and the node crashes/filesystem fills.
- Use Persistent Volumes so historical data survives Pod restarts.
- Use Alertmanager: don't just view dashboards; fire Slack/PagerDuty when CPU > 90% or a Pod is CrashLooping.

### Additional Production Knowledge

- Add the Alertmanager UI/Ingress behind SSO; the default chart creates an Alertmanager but no exposed auth. In production, put the monitoring UIs behind a VPN or OIDC proxy.
- Configure Prometheus itself with resource requests and limits; as a monitoring system it must never be restarted by the scheduler due to an OOM kill.
- Plan for retention + capacity: Prometheus disk consumption grows with scrape count and label cardinality (metrics have dimensions). Watch cardinality explosion from high-cardinality labels (HTTP status, per-URL).
- Consider remote-write only if you truly need centralized long-term storage; for a single cluster the local TSDB is fine.

## Best Practices

### From Lesson

- Add a `/metrics` endpoint to every app and instrument it.
- Create a ServiceMonitor with labels that match the Service.
- Configure retention and Persistent on Prometheus.
- Wire Alertmanager to a real channel; don't declare success on dashboards alone.

### Additional Production Knowledge

- Monitor the monitor: watch Prometheus pod OOM and target health (`up == 0` alert) early.
- Name exporters and dashboards consistently; use kube-prometheus default dashboards as a base and extend rather than starting from scratch.
- Use `rate()`/`irate()` in PromQL for counters instead of the raw counter value, and `histogram_quantile` for latency percentiles.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| App without a `/metrics` endpoint | Prometheus can't scrape something that doesn't expose /metrics | Instrument the app (prometheus_client, etc.) and expose the endpoint. |
| Forgetting the ServiceMonitor | Prometheus won't scrape without it | Create a ServiceMonitor matching the Service's labels. |
| Prometheus without a PV | Data lost on restart | Attach a PVC; set retention. |
| Wrong sync on label | ServiceMonitor selector must match Service labels | Confirm labels match exactly. |

## Troubleshooting

### From Lesson

Scenario: Grafana shows no data.

- Drag the time range in the top right to "Last 5 minutes" or the correct window.
- Go to Prometheus -> Status -> Targets; are the targets `Up` (green)?
- Run `up` in Prometheus. A value of 1 means the target is being scraped; 0 means a target down.

### Additional Knowledge

- If a ServiceMonitor you created is not listed under Status -> Targets, verify the chart's `serviceMonitorNamespaceSelector` doesn't restrict to its own namespace.
- If Grafana queries work but dashboards are empty, check the Prometheus data source URL and that the dashboard's variables resolve.

## Comparison Tables

| Feature | Metrics Server (Lesson 24) | Prometheus |
|---------|---------------------------|------------|
| Data Storage | In-memory (no history) | TSDB (months of history) |
| Use Case | HPA and `kubectl top` | Dashboards, alerting |
| Scrape Interval | 60 seconds | 15 seconds (configurable) |
| Query Language | None | PromQL |

## When to Use / When Not to Use

### Use Prometheus and Grafana when:

- You need to track cluster health and application performance over time.
- You want alerts (e.g. "Send to Slack if memory > 90%").
- You want visual dashboards for the SRE team.

### When not to use Prometheus:

- If you only need a quick CPU snapshot; use the Metrics Server.
- If you need to search text logs; use Loki.

## Performance & Security Considerations

- Prometheus scrapes every 15s. With ~1000 Pods that is ~1000 HTTP requests per scrape. Tune the interval carefully; scraping adds load even to apps that do not export metrics, because Prometheus still hits `/metrics`.
- Secure Grafana and Alertmanager. Dashboards and pages expose sensitive infrastructure. Use SSO (OAuth) and restrict access.

## Real Company Examples

### From Lesson

Discord handles many concurrent users on a large Prometheus cluster for request latency. If the p99 latency spikes above ~100ms, Alertmanager pages the on-call engineer and dashboards show which microservice is the bottleneck in real time.

The behavior pattern applies broadly: pick an SLO (e.g. p99 latency, error rate), alert on its burn over a window, and link the dashboard back to the affected service and the incident runbook.

## Common Myths

- Myth: "Prometheus replaces the Kubernetes Metrics Server." False. The Metrics Server feeds the HPA; Prometheus is for humans' dashboards and alerting.
- Myth: "Prometheus can search text logs." False. Prometheus handles numeric metrics; for logs use Loki or Elasticsearch/OpenSearch.

## Summary

- Prometheus is a time-series DB that scrapes metrics using a Pull model.
- Grafana queries Prometheus for dashboards.
- Apps must expose a plaintext `/metrics` for Prometheus to scrape.
- ServiceMonitors (CRDs) tell Prometheus which Services/Pods to scrape.
- The kube-prometheus-stack Helm chart installs the whole stack in one command.

## Revision Notes & Cheat Sheet

One-minute:

- Prometheus = Pull metrics (TSDB).
- Grafana = Visualize metrics.
- Alertmanager = Alert on metrics.
- App must expose `/metrics`.
- ServiceMonitor = tell Prometheus what to scrape.

Memory:

- Prometheus = health inspector demanding the `/metrics` report.
- Grafana = TV screen showing the report.
- ServiceMonitor = the inspector's address list.

| Command | What it does |
|---------|--------------|
| `helm install monitoring prometheus-community/kube-prometheus-stack` | Install the monitoring stack. |
| `kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring` | Access Grafana. |
| `container_cpu_usage_seconds_total` | Common PromQL query for CPU usage. |

## Interview Preparation

### Beginner

Q: Does Prometheus use a Push or Pull model?

A: Pull. Prometheus fetches metrics from the app's `/metrics` endpoint.

Q: Difference between Metrics Server and Prometheus?

A: The Metrics Server is an in-memory cache that feeds the HPA and `kubectl top`; it has no history. Prometheus is a TSDB storing months of history for dashboards and alerting.

### Intermediate

Q: How does Prometheus know which Pods to scrape?

A: ServiceMonitors (CRDs). You create one that selects a Service by labels; Prometheus watches ServiceMonitors and adds the matching Pod IPs.

Q: What is PromQL?

A: Prometheus Query Language, e.g. `rate(container_cpu_usage_seconds_total[5m])` to compute CPU rate over 5 minutes.

### Scenario

Q: You deployed a new app but Prometheus is not scraping it.

A: (1) Confirm the app exposes a `/metrics`: `kubectl exec <pod> -- curl localhost:8080/metrics` returns text. (2) Check the ServiceMonitor exists and its `matchLabels` match the app's Service. (3) In Prometheus -> Status -> Targets, see if the target is listed and shows an error (e.g. 404).

### True / False

- "Prometheus can search text logs" → False (use Loki).
- "Prometheus stores cluster state in etcd" → False (it uses its own local TSDB).

## Interview Questions

- How does Prometheus decide which targets to scrape, and what is a scrape interval?
- What is the difference between metrics Prometheus scrapes directly and those from kube-state-metrics or node-exporter?
- How do labels shape PromQL queries, and why should you keep label cardinality low?
- How does Grafana consume Prometheus as a data source?

## Scenario Questions

1. A new workload is not appearing in Prometheus. List where you would look in the scrape config, service discovery, and target health.
2. A high-cardinality label makes your queries slow. How would you identify and fix the problem?

## Quiz

1. Which model does Prometheus use to collect metrics from applications?
   - A. Push
   - B. Pull
   - C. Stream
   - D. Event

2. What CRD tells Prometheus which Services to scrape?
   - A. Ingress
   - B. ServiceMonitor
   - C. ConfigMap
   - D. NetworkPolicy

3. Which endpoint must an application expose for Prometheus to scrape it?
   - A. `/healthz`
   - B. `/metrics`
   - C. `/status`
   - D. `/api/v1`

4. Which of the following is a PromQL `rate` function used for?
   - A. List nodes
   - B. Compute a per-second rate over a window (counter)
   - C. Restart a Deployment
   - D. Show pod logs

5. True or False: Prometheus stores the cluster state in etcd.
   - A. True
   - B. False

Answers: 1-B, 2-B, 3-B, 4-B, 5-B

## Revision

- Prometheus: TSDB, Pull model, `/metrics`, retention + PV in production.
- Grafana: query + visualize.
- Alertmanager: threshold fire.
- ServiceMonitor: CRD → dynamic scrape targets.

## Cheat Sheet

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
kubectl get pods -n monitoring

kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring

# PromQL examples
container_cpu_usage_seconds_total
rate(container_cpu_usage_seconds_total[5m])
up

helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring
```

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Prometheus Query Language (PromQL)](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [kube-prometheus-stack Helm chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Grafana Documentation](https://grafana.com/docs/)

## Related Lessons

- [Lesson 35 - Monitoring and Metrics](lesson-24-monitoring-and-metrics.md) - the Metrics Server and `kubectl top`.
- [Lesson 25 - Logging](lesson-25-logging.md) - the text-log pillar that pairs with metrics.
- [Lesson 42 - Helm](../09-packaging/lesson-29-helm.md) - how the stack is installed.
- [Lesson 39 - Horizontal Pod Autoscaler](../12-production/lesson-36-horizontal-pod-autoscaler.md) - HPA, powered by the Metrics Server, versus Prometheus.

## Coming Next

Lesson 28 continues the observability theme with centralized logging: Loki, LogQL, and how logs complete the metrics pillar for a full troubleshooting toolkit.