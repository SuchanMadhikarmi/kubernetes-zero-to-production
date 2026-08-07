---
title: Revision - Observability
module: 08 Observability
status: Complete
tags: [revision, observability, prometheus, grafana, loki, probes, monitoring]
---

# Revision - Observability

## Core Ideas

- Observability = Metrics (what) + Logs (why) + Traces (where).
- Stack: **Prometheus** (metrics) + **Grafana** (dashboards) + **Loki** (logs, via Promtail).
- **Probes** function: readiness removes from endpoints, liveness restarts, startup gates slow starts.
- Golden Signals: Latency, Traffic, Errors, Saturation.

## Prometheus Flow

```text
Node Exporter (per node) -> scrape -> Prometheus TSDB -> PromQL -> Alertmanager -> alert
App /metrics endpoint                                              Grafana dashboards
```

PromQL examples:

```text
sum(rate(http_requests_total[5m]))
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
```

## Loki

- Promtail (DaemonSet) ships logs to Loki; query with LogQL.
- LogQL: `{namespace="web"} |= "error"`.

## Probes

| Probe | On failure |
|-------|-----------|
| startupProbe | gate before liveness |
| livenessProbe | restart container |
| readinessProbe | remove from Service Endpoints |

## Commands

```bash
kubectl get events -A --sort-by='.lastTimestamp'
kubectl top nodes / pods
kubectl logs -f -l app=web --tail=200
kubectl logs <pod> --previous
kubectl describe pod <name>
```

## Related Lessons

- [Lesson 30 - Monitoring and Metrics](../docs/08-observability/lesson-30-monitoring-and-metrics.md)
- [Lesson 31 - Logging](../docs/08-observability/lesson-31-logging.md)
- [Lesson 32 - Probes and Health Checks](../docs/08-observability/lesson-32-probes-and-health-checks.md)
- [Lesson 43 - Observability Deep Dive (Prometheus and Grafana)](../docs/08-observability/lesson-43-observability-deep-dive-prometheus-and-grafana.md)
- [Lesson 44 - Centralized Logging (Loki and Promtail)](../docs/08-observability/lesson-44-centralized-logging-loki-and-promtail.md)

## Related Material

- [Observability Cheat Sheet](../cheatsheets/observability-cheatsheet.md)
- [Interview - Observability](../interview/observability.md)

[Back to Revision Index](README.md)