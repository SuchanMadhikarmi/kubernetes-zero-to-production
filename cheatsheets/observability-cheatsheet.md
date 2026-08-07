---
title: Observability Cheat Sheet
topic: observability
status: Complete
tags: [cheatsheet, observability, prometheus, grafana, loki, logs, metrics, tracing]
---

# Observability Cheat Sheet

Observability = Metrics (what) + Logs (why) + Traces (where). Kubernetes ships probes, events, and resource metrics; Prometheus + Grafana + Loki are the common stack.

## The Three Pillars

| Pillar | Tool in stack | Answers |
|--------|---------------|---------|
| Metrics | Prometheus | What is happening (rates, saturation, errors) |
| Logs | Loki / Elasticsearch (Promtail / Fluent Bit) | Why it happened (events, stack traces) |
| Traces | Jaeger / Tempo / OpenTelemetry | Where the request went (distributed spans) |
| Events/critical state | Kubernetes Events | Scheduling / resource failures |

## kubectl as a first glance

```bash
kubectl get events -A --sort-by='.lastTimestamp'
kubectl get events --field-selector type=Warning
kubectl top nodes
kubectl top pods
kubectl describe node <node>        # machine capacity + allocated resources
kubectl describe pod <name>         # status, conditions, events
kubectl logs -f -l app=web --tail=200
kubectl logs <pod> --previous
kubectl debug node/<node> -it --image=busybox   # debug node
```

## Probes (health checks)

| Probe | Command in spec | Meaning of failure |
|-------|-----------------|--------------------|
| liveness | `livenessProbe` | container restarted |
| readiness | `readinessProbe` | removed from Service Endpoints |
| startup | `startupProbe` | gate before liveness for slow start |

```yaml
livenessProbe:
  httpGet: {path: /healthz, port: 8080}
  initialDelaySeconds: 3
  periodSeconds: 5
```

## Prometheus flow

```text
Node Exporter (per node)          -> /metrics on 9100
App (Prometheus client)           -> /metrics endpoint
prometheus scrape rules -> TSDB -> PromQL queries -> Alertmanager -> alert
Grafana datasource -> dashboards / alerts
```

```bash
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090   # UI
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090   # Prometheus UI (kube-prometheus-stack)
```

Query examples (PromQL):

```text
# Requests per second
sum by (service) (rate(http_requests_total[5m]))

# Error ratio
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))

# CPU by node
topk(5, sum(rate(node_cpu_seconds_total{mode!="idle"}[5m])) by (instance))

# Memory
sum(container_memory_usage_bytes{namespace="default"}) / 1e9
```

## Loki (logs)

Loki is a log aggregation backend; Promtail (DaemonSet) ships pod logs to it. Query with LogQL.

```bash
# Add sample
kubectl port-forward svc/loki-gateway 3100:80 -n monitoring
kubectl logs -l app=web --previous | tail -20
```

LogQL rules:

```
{namespace="web"}                                          # all logs in ns
{app="web"} |= "error"                                     # contains "error"
{app="web"} |~ "(?i)timeout|refused"                      # regex
sum(count_over_time({app="web"}[5m])) by (level)
```

## Grafana

- Data sources: Prometheus (metrics) + Loki (logs) + Tempo (traces), linking.
- Use **dashboards-as-code** via provisioning (JSON) for GitOps.
- Alert rules reference metric queries; alerting to Slack/PagerDuty.

```bash
kubectl port-forward svc/grafana 3000:80 -n monitoring   # default Grafana UI
# default logins are admin / admin; change them immediately
```

## Golden Signals

- Golden Signals: **Latency, Traffic, Errors, Saturation** (Google SRE).
- Set alerts on error rate and saturation; watch latency and rate.

## Scaling note

- Prometheus-based autoscaling relies on custom metrics APIs served by an adapter (for example `prometheus-adapter`), not the default `kubelet` resource metrics.

## useful command summary

```bash
kubectl get events -A -w
kubectl top pods -A
kubectl logs --prefix -l app=web --tail=50
kubectl auth can-i get pods --as=system:serviceaccount:demo:sa
```