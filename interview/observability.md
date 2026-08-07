---
title: Interview - Observability
module: 08 Observability
status: Complete
tags: [interview, observability, prometheus, grafana, loki, probes]
---

# Interview - Observability

## Beginner

**Q: What are the three pillars of observability?**

A: Metrics (what happened), logs (why it happened), and traces (where the request went through distributed systems).

**Q: What do readiness and liveness probes do?**

A: Readiness determines if a Pod should receive traffic (failing removes it from Service endpoints). Liveness determines if a container should be restarted.

## Intermediate

**Q: How does Prometheus collect metrics?**

A: It scrapes HTTP `/metrics` endpoints on a schedule. Exporters (node-exporter for host metrics, app client libraries for application metrics) expose them; Prometheus stores them in a time-series DB and evaluates queries and alert rules.

**Q: What is the difference between Prometheus and Loki?**

A: Prometheus stores numeric time-series metrics; Loki stores logs. Promtail ships pod logs to Loki. Grafana visualizes both.

**Q: A container keeps restarting but readiness is green. What now?**

A: Check liveness probe and app logs (`kubectl logs --previous`). Readiness green means the app is ready; liveness failing means the health endpoint reports bad state or the probe is misconfigured.

## Advanced

Q: Give a PromQL example that alerts on high error rate.

A: `sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.05`.

## Scenario

Q: The Metrics Server is not reporting. What breaks?

A: `kubectl top` fails and the HPA shows `<unknown>` targets. Fix by checking the `metrics-server` deployment, its API, and that Pods have resource requests.

## Related

- [Revision - Observability](../revision/observability.md)
- [Lesson 26 - Probes and Health Checks](../docs/08-observability/lesson-26-probes-and-health-checks.md)

[Back to Interview Index](README.md)