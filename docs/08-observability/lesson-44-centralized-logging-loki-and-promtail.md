---
title: Lesson 44 - Centralized Logging (Loki and Promtail)
module: 08 Observability
lesson: 44
status: Complete
tags: [kubernetes, loki, promtail, logql, logging, grafana, observability, daemonset, helm]
---

# Lesson 44 - Centralized Logging (Loki and Promtail)

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

- Describe the architecture of a modern logging stack: Promtail, Loki, and Grafana.
- Explain the difference between metrics (Prometheus) and logs (Loki).
- Explain how Promtail automatically discovers and ships container logs.
- Install the stack via Helm and query logs using LogQL.

## Prerequisites

- Completion of Lessons 1 through 43.
- A running kind cluster.
- kubectl and helm installed.

## Real-world Motivation

### From Lesson

The 500-node haystack: a user reports a 500 Internal Server Error on the checkout page. Metrics show the backend Pod restarted. You need to see the stack trace. If you use `kubectl logs <pod>`, you are looking at one Pod on one node. But the error might have happened on a different node, or the Pod might have crashed and its logs are gone. You need a single search bar to query "show me all ERROR logs in the checkout namespace from the last 5 minutes".

Why this exists: to centralize logs without overwhelming your storage. Loki was created by Grafana Labs to be the "Prometheus of Logs". Unlike Elasticsearch, which indexes every word in a log line (consuming massive CPU and disk), Loki only indexes the metadata (labels like namespace and pod name). This makes it cheap and fast to run.

### Additional Production Knowledge

Logs and metrics answer complementary questions: metrics tell you *what* changed and *when*, logs tell you *why*. For a complete picture, many teams also add traces (Tempo/Jaeger) to correlate a single failing request across services. When you design the logging story, decide early on whether your apps emit structured logs (JSON), because parsing structured logs in Promtail/LogQL is far more powerful than grepping plain text.

Logs must never be the only copy of critical data you rely on. Shipping logs off-cluster with a retention policy protects you from node disk loss, and encrypting log transport and storage avoids leaking Secrets that appear in stack traces.

## Core Concepts

### From Lesson

- **Promtail**: A DaemonSet that runs on every node. It reads container log files from `/var/log/pods/`, adds Kubernetes metadata (labels), and pushes them to Loki.
- **Loki**: A log aggregation system. It stores logs in compressed chunks and only indexes the metadata (labels), not the full log text.
- **LogQL**: Loki's query language. It resembles PromQL but filters logs, e.g. `{namespace="default"} |= "error"`.
- **Push model**: unlike Prometheus, which pulls, Promtail pushes logs to Loki.

### Additional Production Knowledge

- Promtail is one of many shippers. Fluent Bit, Fluentd, and Vector are popular alternatives. Promtail is deeply integrated with Kubernetes discovery and Loki, while Fluent Bit is written in C and is often chosen for extreme throughput.
- Loki storage backends: the simplest deployments use local disk (Single Binary mode); production uses an external object store (S3, GCS, Azure) with a configurable index backend. The lesson covers the default, but the production note is to move to enterprise-style storage.

## Architecture

### From Lesson

The stack requires the three components: the shipper (Promtail), the database (Loki), and the UI (Grafana).

```text
[ Node 1 ]                          [ Node 2 ]
[ Pod A (stdout) ]                  [ Pod B (stdout) ]
      |                                   |
      v                                   v
[ Promtail (DaemonSet) ]            [ Promtail (DaemonSet) ]
      | (Pushes logs with labels)        |
      +-----------------+-----------------+
                        |
                        v
                 [ Loki (Distributor) ]
                        |
                        v (Stores compressed chunks)
                 [ Loki Storage (Disk/S3) ]
                        |
                        v (Queries)
                 [ Grafana UI ]
```

### Additional Production Knowledge

Loki's internal components are split by role: the Distributor validates and forwards batches, the Ingester builds chunks in memory and flushes them to object storage, and the Querier evaluates LogQL on read. The Helm chart may instantiate these as separate services (`loki`, `loki-gateway`), or in single-binary mode. Understanding this decomposition helps when debugging "logs exist but queries are slow".

## ASCII Diagrams

### From Lesson

```text
[ Promtail ] -> (Push) -> [ Loki ]
                             |
                             v
[ Grafana ] -> (Query LogQL) -> [ Loki ] -> (Returns logs)
```

### Additional Production Knowledge

Flow on a node:

```text
containerd writes stdout/stderr
      |
      v
/var/log/pods/<ns>_<pod>_<uid>/<container>/<n>.log  (JSON)
      |
      v
Promtail (DaemonSet, one per node) tails the file, adds labels
      |
      v (HTTP push)
Loki distributor -> ingester -> compressed chunk in S3/GCS
      |                     |
      |                     v
      |                 index (boltdb-shipper)
      v
Grafana Explore (LogQL)
```

## Hands-on

### From Lesson

Step 1 - Add the Helm repo:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

Step 2 - Install Loki:

```bash
helm install loki grafana/loki --namespace loki --create-namespace --set service.type=ClusterIP
```

Step 3 - Install Promtail (the same namespace so it discovers Loki):

```bash
helm install promtail grafana/promtail --namespace loki
```

Step 4 - Install a Grafana pre-configured with a Loki datasource:

```bash
helm install my-grafana grafana/grafana --namespace loki \
  --set admin.user=admin \
  --set admin.password=admin \
  --set datasources."datasources\.yaml".apiVersion=1 \
  --set datasources."datasources\.yaml".datasources[0].name=Loki \
  --set datasources."datasources\.yaml".datasources[0].type=loki \
  --set datasources."datasources\.yaml".datasources[0].url=http://loki:3100 \
  --set datasources."datasources\.yaml".datasources[0].access=proxy
```

Step 5 - Wait for pods:

```bash
kubectl get pods -n loki
```

Wait until `loki`, `promtail`, and `my-grafana` are `Running`.

Step 6 - Access Grafana:

```bash
kubectl port-forward svc/my-grafana 3000:80 -n loki
```

Open `http://localhost:3000` (user `admin`, password `admin`).

Step 7 - Explore logs: click the Explore (compass) icon, choose the Loki data source, and run `{namespace="loki"}`. You will see logs from the Loki and Promtail pods.

Step 8 - Hunt a specific log. Deploy a Pod that prints an error:

```bash
cat <<EOF > error-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: error-generator
  labels:
    app: error-app
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "while true; do echo 'ERROR: Database connection lost!'; sleep 5; done"]
EOF
kubectl apply -f error-pod.yaml
```

In Grafana change the query to `{namespace="default"} |= "ERROR"` and run it. The `ERROR: Database connection lost!` lines stream in real time.

Cleanup:

```bash
# Ctrl+C in the port-forward terminal
kubectl delete pod error-generator
helm uninstall loki -n loki
helm uninstall promtail -n loki
helm uninstall my-grafana -n loki
kubectl delete namespace loki
```

## Commands

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install loki grafana/loki --namespace loki --create-namespace --set service.type=ClusterIP
helm install promtail grafana/promtail --namespace loki
helm install my-grafana grafana/grafana --namespace loki \
  --set admin.user=admin --set admin.password=admin \
  --set datasources."datasources\.yaml".apiVersion=1 \
  --set datasources."datasources\.yaml".datasources[0].name=Loki \
  --set datasources."datasources\.yaml".datasources[0].type=loki \
  --set datasources."datasources\.yaml".datasources[0].url=http://loki:3100 \
  --set datasources."datasources\.yaml".datasources[0].access=proxy

kubectl get pods -n loki
kubectl port-forward svc/my-grafana 3000:80 -n loki

# Check Promtail targets
kubectl port-forward svc/loki-promtail 9080:9080 -n loki   # http://localhost:9080/targets
```

## YAML Explanation

The two key artifacts are the Promtail DaemonSet and the log source it reads.

```yaml
# excerpts from the promtail DaemonSet
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: promtail
  template:
    spec:
      serviceAccountName: promtail
      containers:
      - name: promtail
        image: grafana/promtail:latest
        args:
        - -config.file=/etc/promtail/promtail.yaml
        volumeMounts:
        - name: config
          mountPath: /etc/promtail
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
```

- A DaemonSet runs exactly one Promtail pod per node, which is why shippers see node-level files like `/var/log/pods/`.
- `volumeMounts` mount the node's log directories, so Promtail has read access to every container's output.
- The `serviceAccountName` is required so Promtail can use the Kubernetes API to discover Pods and attach metadata.

```yaml
scrape_configs:
- job_name: kubernetes-pods
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  - source_labels: [__meta_kubernetes_namespace]
    target_label: namespace
  - source_labels: [__meta_kubernetes_pod_name]
    target_label: pod
```

This is how Promtail discovers Pods and adds the `namespace`/`pod` labels you then filter on in LogQL.

## Production Notes

### From Lesson

- Use object storage: in production point Loki at S3/GCS rather than local disk.
- Set retention (`retention_period` e.g. 30 days) to delete old chunks automatically.
- Use structured logging so Promtail and LogQL can parse fields instead of grepping text.

### Additional Production Knowledge

- Protect the logs pipeline: encrypt transport (TLS) between Promtail and Loki when crossing networks, and apply RBAC to the Grafana datasource.
- Cost plan for the cardinal: naming labels (namespace, pod) is what makes LogQL fast; the cardinality is controlled by the number of distinct streams. Keep label sets small and stable.
- Separate logs retention from metrics retention; they rarely need to be identical.

## Best Practices

### From Lesson

- Run Promtail as a DaemonSet to cover every node.
- Configure Grafana with a Loki datasource early so dashboards are ready when logs land.
- Prefer structured (JSON) logging for parseable fields.
- Direct sensitive data handling: do not write secrets, PII, or card numbers to stdout.

### Additional Production Knowledge

- Use Promtail relabel rules and drop rules to remove high-cardinality or noisy fields before they go to Loki.
- Add tenant/namespace separation if multiple teams share one Loki instance.
- Keep logs flowing to backup/object storage before any retention automation expires them.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| App logs to a file, not stdout | Promtail only tails `/var/log/pods` (stdout/stderr) | Ensure apps write to stdout; check with `kubectl logs`. |
| Forgetting the Grafana datasource | Loki installed but not wired in Grafana | Add Loki as a datasource in Grafana. |
| No retention set | Disk fills, Loki crashes | Configure `retention_period`. |
| Shipping massive per-line payloads | Huge JSON blobs overwhelm Promtail/Loki | Keep logs concise; drop noisy logs in config. |

## Troubleshooting

### From Lesson

Scenario: logs missing in Grafana.

1. Check Promtail pods: `kubectl get pods -n loki -l app.kubernetes.io/name=promtail`. Are they running?
2. Check Promtail targets: port-forward to `/targets`. Are nodes with log targets listed?
3. Verify the app logs to stdout: `kubectl logs <pod>`. If empty, the app writes to a file and Promtail can't see it.

### Additional Knowledge

- If the Query Filter `{namespace="default"}` returns nothing but the Pod logs exist, check the time range in the Grafana navbar; logs may exist but the range excludes them.
- If a Pod was deleted, Loki still holds its historical chunks; query by the label and widen the time window.

## Comparison Tables

| Feature | `kubectl logs` | Centralized Logging (Loki) |
|---------|----------------|---------------------------|
| Scope | Single Pod on a node | Entire cluster |
| History | Only since last restart | Months (retention set) |
| Search | Manual `grep` | LogQL |
| Persistence | Lost when Pod deleted | Stored in object storage |

| Feature | Loki | Elasticsearch (ELK) |
|---------|------|---------------------|
| Indexing | Metadata only | Full-text (inverted index) |
| Cost | Low (S3) | High (SSD) |
| Integration | Grafana native | Kibana |
| Best for | Kubernetes logs | Enterprise log analysis |

## When to Use / When Not to Use

Use Loki when:

- You need to aggregate and search logs across the cluster.
- You already use Prometheus/Grafana and want one observability stack.
- You want cheap object-storage logs without losing query speed.

When NOT to use Loki:

- If you need complex full-text search and out-of-the-box alerting on arbitrary log fields (Elasticsearch wins there).
- If you are not invested in Grafana (Loki is tightly integrated with it).

## Performance & Security Considerations

- Promtail consumes CPU when apps produce many lines/sec. Use `relabel_configs` to drop noisy logs before pushing.
- Do not print sensitive data to stdout; if you do, anyone with Grafana access can read it.

## Real Company Examples

### From Lesson

Robinhood ingests logs at very high volume during a trading spike. Because Loki indexes only metadata (labels) rather than the full text, they could search millions of log lines in milliseconds without the logging infrastructure collapsing under the load.

## Common Myths

- Myth: "Loki replaces Prometheus." False; Loki is for text logs, Prometheus for numeric metrics. They complement each other.
- Myth: "Promtail is the only log shipper." False; Fluent Bit, Fluentd, and Vector are alternatives. Promtail is just tightly integrated with Loki.

## Summary

- Promtail is a DaemonSet that tails `/var/log/pods/` and ships logs to Loki.
- Loki is a log aggregation DB that indexes only labels (metadata), making it light and fast.
- LogQL is the query language, e.g. `{namespace="default"} |= "error"`.
- Logs are viewed in the Grafana Explore tab.

## Revision Notes & Cheat Sheet

One-minute:

- Promtail = shipper (DaemonSet).
- Loki = database (metadata-only indexing).
- LogQL = `{namespace="x"} |= "error"`.
- App must log to stdout.

Memory:

- Promtail: the mail carrier picking letters (logs) from every house (Pod).
- Loki: the post office; files by address (labels), reads content only on request.
- Grafana: you asking "all letters from the default neighborhood containing ERROR".

| Command / Query | Purpose |
|----------------|---------|
| `{namespace="kube-system"}` | All logs in `kube-system` |
| `{namespace="default"} |= "ERROR"` | Filter logs matching text |
| `kubectl logs <pod>` | Old, manual way of reading logs |

## Interview Preparation

### Beginner

Q: Where does Promtail read container logs from on the node?

A: `/var/log/pods/`.

Q: What is the difference between Loki and Elasticsearch?

A: Loki indexes metadata (labels) only, not the full log text, which makes it cheaper to store and faster to query for Kubernetes workloads.

### Intermediate

Q: How do you aggregate and search logs in a Kubernetes cluster?

A: Deploy Promtail as a DaemonSet to tail and ship logs to Loki; configure Grafana Loki datasource; then use the Explore tab and LogQL like `{namespace="prod"} |= "FATAL"`.

Q: LogQL to find logs in the default namespace containing "timeout"?

A: `{namespace="default"} |= "timeout"`.

### Scenario

Q: Find the stack trace of a Pod that crashed 10 minutes ago, where `kubectl logs` shows nothing after recreation.

A: Query Loki from Grafana Explore with the Loki datasource: `{namespace="prod"}` with a time range around then, or `{pod="previous-pod"}`.

### True / False

- "True or False: Loki indexes the full text of logs." False (metadata only).
- "Promtail runs as a Deployment." False (DaemonSet to read node-level `/var/log`).

Q: Why must logs be shipped to Loki rather than left on the node's `/var/log`?

A: Logs only on a node are single-node, lost when the node or Pod is deleted, and unsearchable across a cluster. Centralized log aggregation and durable storage make them searchable for months.

## Quiz

1. Which component ships container logs from each node to Loki?
   - A. exporter
   - B. Promtail (DaemonSet)
   - C. Metrics Server
   - D. CoreDNS

2. Where does Promtail read container log lines?
   - A. `/var/run/docker.sock`
   - B. `/var/log/pods/`
   - C. `/etc/promtail`
   - D. `/tmp/logs`

3. What is the difference between Loki and Elasticsearch?
   - A. Loki indexes only labels; ES full text
   - B. Loki full text; ES labels
   - C. Identical
   - D. Loki is a metrics database

4. Which LogQL filters logs in the default namespace for the substring "timeout"?
   - A. `{namespace="default"} |= "timeout"`
   - B. `{namespace="timeout"} |= "default"`
   - C. `{app="timeout"}`
   - D. `rate(container_cpu[5m])`

5. True or False: Promtail should run as a Deployment to ship logs.
   - A. True
   - B. False

Answers: 1-B, 2-B, 3-A, 4-A, 5-B

## Revision

- Promtail (DaemonSet) reads `/var/log/pods` and pushes logs to Loki; Loki indexes only labels; Grafana Explore queries via LogQL.
- App must write to stdout or Promtail never sees it.
- Production: object storage, retention, structured logging, encrypt.

## Cheat Sheet

```bash
# Install
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install loki grafana/loki --namespace loki --create-namespace --set service.type=ClusterIP
helm install promtail grafana/promtail --namespace loki

# Grafana with Loki datasource
helm install my-grafana grafana/grafana --namespace loki \
  --set admin.user=admin --set admin.password=admin \
  --set datasources."datasources\.yaml".apiVersion=1 \
  --set datasources."datasources\.yaml".datasources[0].name=Loki \
  --set datasources."datasources\.yaml".datasources[0].type=loki \
  --set datasources."datasources\.yaml".datasources[0].url=http://loki:3100 \
  --set datasources."datasources\.yaml".datasources[0].access=proxy

kubectl port-forward svc/my-grafana 3000:80 -n loki

# LogQL
{namespace="default"} |= "ERROR"
{namespace="kube-system"}
{namespace="prod"} | json | level="error"
```

## References

- [Loki Documentation](https://grafana.com/oss/loki/)
- [LogQL Syntax (Loki query language)](https://grafana.com/docs/loki/latest/logql/)
- [Promtail (Grafana docs)](https://grafana.com/docs/loki/latest/send-data/promtail/)

## Related Lessons

- [Lesson 43 - Observability Deep Dive (Prometheus and Grafana)](lesson-43-observability-deep-dive-prometheus-and-grafana.md) - metrics pillar pairing with logs.
- [Lesson 30 - Monitoring and Metrics](lesson-30-monitoring-and-metrics.md) - the Metrics Server and `kubectl top`.
- [Lesson 33 - Helm](../09-packaging/lesson-33-helm.md) - how the stack is installed.
- [Lesson 15 - Jobs and CronJobs](../03-workloads/lesson-15-jobs-and-cronjobs.md) - short-lived workloads that lose logs without centralization.

## Coming Next

Lesson 45 continues the observability theme with tracing (Tempo/Jaeger) and how the three pillars of observability work together to correlate a single request end to end.