---
title: Lesson 24 - Monitoring and Metrics
module: 08 Observability
lesson: 24
status: Complete
tags: [kubernetes, observability, metrics, metrics-server, kubectl-top, hpa, monitoring, kubelet]
---

# Lesson 24 - Monitoring and Metrics

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

- Explain why Kubernetes needs a Metrics Server.
- Describe the difference between the Metrics API and full monitoring stacks (like Prometheus).
- Install the Metrics Server in a kind cluster.
- Use `kubectl top` to observe real-time CPU and Memory usage.
- Explain how the Horizontal Pod Autoscaler (HPA) relies on this data.

## Prerequisites

- Completion of Lessons 1 through 17.
- A running kind cluster.
- kubectl installed and configured.

## Real-world Motivation

### The Blind SRE

In Lesson 8, we set CPU and Memory requests and limits. But how do you know if your app is actually using those resources? Is it sitting idle at 5% CPU (wasting money), or is it sitting at 95% (about to get OOMKilled)? Without a metrics tool, you are flying blind. You cannot right-size your applications, and the Horizontal Pod Autoscaler (HPA) has no data to trigger a scale-up during a traffic spike.

### Why This Exists

The core Kubernetes API was designed to be lightweight. Storing time-series metrics in etcd would destroy the database's performance. To solve this, Kubernetes introduced the Metrics API. The Metrics Server is the standard implementation of this API. It collects real-time data and exposes it in-memory, allowing tools like `kubectl top` and the HPA to function without overloading the control plane.

### Real Company Examples

**Airbnb:** Airbnb uses the Metrics Server strictly to feed data into the Horizontal Pod Autoscaler (HPA). When traffic spikes to their booking service, the HPA checks the Metrics Server, sees CPU is at 90%, and automatically tells the Deployment to scale from 10 Pods to 50 Pods. They use Prometheus for dashboards, but the Metrics Server for fast, real-time scaling decisions.

## Core Concepts

### Explain Like I'm 12

Imagine a car. The engine runs the car, but you can't drive safely without the dashboard. The Metrics Server is the dashboard. It tells you how fast you are going right now (CPU) and how much gas you have left (Memory).

### Explain Like I'm a Junior Engineer

By default, Kubernetes knows how much CPU/RAM you requested, but it doesn't constantly track how much you are actually using at this exact second. The Metrics Server is a lightweight agent that collects real-time CPU and Memory usage from every Node and Pod, and exposes it via the `kubectl top` command.

### Explain Technically

- The Metrics Server is a cluster-wide aggregator.
- It polls the kubelet Summary API on every node every 60 seconds.
- It aggregates the data and exposes it via the `metrics.k8s.io` API.
- `kubectl top` queries this API to display the data.
- Because it uses API Aggregation, `kubectl top` feels like a native Kubernetes command, even though the data is coming from a separate Pod.

### How Kubernetes Implements It Internally

The Kubernetes API Server supports API Aggregation. It can proxy requests to other API servers. When you run `kubectl top`, the request goes to the main API Server, which proxies it to the Metrics Server pod. The Metrics Server queries its in-memory cache (it does not store historical data in etcd) and returns the JSON response.

### Why Kubernetes Was Designed That Way

Kubernetes was designed to keep the core API lightweight. Storing time-series metrics in etcd would destroy performance. By introducing a separate Metrics Server that stores data in-memory, Kubernetes keeps the core API fast while still providing real-time metrics for tools like `kubectl top` and HPA.

## Architecture

```
[ Node 1 (kubelet) ] ---> (Summary API: /metrics/resource/v1beta1)
[ Node 2 (kubelet) ] ---> (Summary API)
      |
      v (Metrics Server scrapes every 60s)
[ Metrics Server Pod ]
      |
      v (Aggregates into metrics.k8s.io API)
[ K8s API Server ] (API Aggregation)
      |
      v
[ kubectl top nodes / pods ] & [ Horizontal Pod Autoscaler ]
```

### Terminology

| Term | Definition |
|------|------------|
| Metrics API | The `metrics.k8s.io` API endpoint that provides resource usage data. |
| Summary API | The kubelet endpoint (`/metrics/resource/v1beta1`) that exposes real-time stats. |
| API Aggregation | A Kubernetes feature allowing the API Server to proxy requests to other services. |
| `kubectl top` | The CLI command used to view real-time CPU and Memory usage. |

### How It Works Internally

1. The Metrics Server Pod starts in the `kube-system` namespace.
2. It authenticates with the API Server using its ServiceAccount.
3. Every 60 seconds, it connects to every kubelet in the cluster.
4. The kubelet reads the container's cgroup stats (CPU accounting, memory pages).
5. The kubelet formats this as JSON and sends it to the Metrics Server.
6. The Metrics Server stores the latest snapshot in its memory.
7. When you run `kubectl top pods`, the API Server forwards the request to the Metrics Server, which returns the JSON from its memory.

### Step-by-Step Workflow

1. Admin installs the Metrics Server.
2. Metrics Server identifies all nodes in the cluster.
3. Metrics Server scrapes node 1, node 2, etc.
4. User runs `kubectl top nodes`.
5. API Server proxies request to Metrics Server.
6. Metrics Server returns current CPU/Memory usage for nodes.

### Lifecycle

| State | Description |
|-------|-------------|
| Scrape | Metrics Server polls Kubelet (every 60s). |
| Cache | Data is stored in memory. |
| Query | `kubectl top` or HPA requests data. |
| Expire | If a Pod is deleted, it disappears from the cache on the next scrape. |

### Feature Comparison

| Feature | Metrics Server | Prometheus |
|---------|---------------|------------|
| Data Storage | In-memory only (no history) | Time-Series Database (months of history) |
| Use Case | `kubectl top`, HPA | Dashboards, Alerting, SLOs |
| Scrape Interval | 60 seconds | Configurable (usually 15s) |
| Complexity | Very low (1 Pod) | High (Server, Alertmanager, Node Exporter) |

### Common Myths

| Myth | Fact |
|------|------|
| "The Metrics Server stores data in etcd." | False. It only keeps the last few minutes of data in its own RAM. Storing time-series metrics in etcd would destroy the database's performance. |
| "You need the Metrics Server to use `kubectl logs`." | False. Logs are handled by the kubelet directly streaming the container stdout/stderr files. |

## ASCII Diagrams

Mental Model: The Metrics Server is a census taker. Every 60 seconds, it knocks on every Node's door, asks how much CPU and RAM the Pods inside are using, writes it on a clipboard (in-memory), and reports it back to the government (`kubectl top`).

```
[ K8s API Server ] <--- (kubectl top) --- [ User ]
      |
      v (Proxies request via API Aggregation)
[ Metrics Server ] (Checks in-memory cache)
      |
      v (How it got the data)
[ Node 1 (Kubelet) ] -> Scrapes cgroup stats -> Returns Pod CPU/Mem
```

## Hands-on

### Objective

Install the Metrics Server in kind, deploy a CPU-hogging application, and use `kubectl top` to identify the culprit.

### Step 1: Install the Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Step 2: Patch it for Kind

Kind's kubelet uses self-signed certificates that the Metrics Server doesn't trust by default. We must tell it to skip TLS verification (NEVER do this in real production).

```bash
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

### Step 3: Wait for it to be Ready

```bash
kubectl get deployment metrics-server -n kube-system
```

Wait until the `READY` column shows `1/1`.

### Step 4: Verify it Works

Wait about 60 seconds for the first scrape to happen, then run:

```bash
kubectl top nodes
```

Expected output: CPU and Memory usage for your control-plane and worker nodes.

### Step 5: Deploy the CPU Hog

Create `hog.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cpu-hog
  labels:
    app: hog
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "while true; do echo 'burning CPU'; done"]
    resources:
      requests:
        cpu: "100m"
      limits:
        cpu: "500m"
```

**Field Explanation:**

- An infinite `while` loop will max out a CPU core.
- We gave it a limit of 500m (half a core), so it will get throttled at 50% CPU usage.

Apply it:

```bash
kubectl apply -f hog.yaml
```

### Step 6: Investigate with kubectl top

Wait about 60 seconds for the metrics to update, then run:

```bash
kubectl top pods
```

**Your Task:**

- What is the CPU usage of the `cpu-hog` pod? (It should be somewhere around 500m, which is 50% of a core, or 500 millicores).
- What command would you run to see the CPU usage of only the `cpu-hog` pod using a label selector?
- Based on the theory, where did the Metrics Server get this real-time data from?

(Answer: 1. ~500m. 2. `kubectl top pod -l app=hog`. 3. The Kubelet's Summary API, which reads the cgroup stats on the node).

### Step 7: Cleanup

```bash
kubectl delete pod cpu-hog
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## Commands

```bash
# Shows real-time CPU/Memory usage of nodes
kubectl top nodes

# Shows real-time CPU/Memory usage of pods in the namespace
kubectl top pods

# Filters metrics by label
kubectl top pod -l app=myapp

# Check if Metrics Server is running
kubectl get pods -n kube-system | grep metrics

# Check Metrics Server logs
kubectl logs -n kube-system <metrics-pod>
```

## YAML Explanation

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cpu-hog
  labels:
    app: hog
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "while true; do echo 'burning CPU'; done"]
    resources:
      requests:
        cpu: "100m"
      limits:
        cpu: "500m"
```

### Field-by-Field Explanation

- `command: ["sh", "-c", "while true; do echo 'burning CPU'; done"]`: Infinite loop to consume CPU.
- `resources.requests.cpu: "100m"`: Minimum CPU guaranteed.
- `resources.limits.cpu: "500m"`: Maximum CPU allowed. The pod will be throttled at this limit.

## Production Notes

- **Enable it in the Cloud:** Managed cloud providers (EKS, GKE, AKS) often have their own native metrics implementations or require a specific installation. Ensure it is running before setting up HPAs.
- **Don't use it for alerting:** If you want to alert when CPU > 90% for 5 minutes, the Metrics Server cannot help you (it has no history). Use Prometheus.
- **Resource Limits:** Give the Metrics Server enough CPU/Memory. In large clusters (100+ nodes), scraping every 60s is CPU-intensive.

### When to Use / When NOT to Use

**Use the Metrics Server when:**

- To enable the Horizontal Pod Autoscaler (HPA).
- For quick, real-time CLI checks (`kubectl top`).
- To right-size Pod requests/limits based on current usage.

**Avoid the Metrics Server when:**

- For long-term historical analysis (use Prometheus).
- For alerting (e.g., "Send a Slack message if CPU > 90%").
- For application-level metrics (e.g., "How many HTTP 200s did Nginx return?").

### Performance and Security Considerations

**Performance:** The Metrics Server is lightweight, but in massive clusters (1,000+ nodes), a single instance cannot scrape all nodes fast enough. You may need to scale it or use a cloud-native alternative (like AWS CloudWatch Container Insights).

**Security:** The Metrics Server requires access to the kubelet API. Ensure the communication is encrypted with proper TLS certificates in production. Never use `--kubelet-insecure-tls` outside of local development.

## Best Practices

- Install Metrics Server before setting up HPAs.
- Use Prometheus for historical data and alerting.
- Don't use `--kubelet-insecure-tls` in production.
- Monitor Metrics Server resource usage in large clusters.
- Use `kubectl top` for quick diagnostics.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Forgetting to install it | Engineers wonder why HPA shows `<unknown>` | Install Metrics Server before setting up HPAs |
| TLS Certificate issues | kubelet uses self-signed certs | Use `--kubelet-insecure-tls` for kind only |
| Expecting history | `kubectl top` only shows current state | Use Prometheus for historical data |
| Not waiting 60 seconds | First scrape takes time | Wait at least 60 seconds after installation |

## Troubleshooting

**Symptom: `error: metrics not available yet`**

Cause: Metrics Server not installed or not ready.

```bash
kubectl get pods -n kube-system | grep metrics
```

Fix: Install Metrics Server and wait for it to be ready.

**Symptom: Metrics Server pod CrashLoopBackOff**

Cause: TLS certificate error.

```bash
kubectl logs -n kube-system <metrics-pod>
```

Fix: For kind, apply the `--kubelet-insecure-tls` patch.

**Symptom: HPA shows `<unknown>`**

Cause: Metrics Server not installed.

```bash
kubectl get hpa
kubectl get pods -n kube-system | grep metrics
```

Fix: Install Metrics Server.

## Interview Questions

**Q: What is the Kubernetes Metrics Server?**

A: A cluster-wide aggregator of resource usage data. It scrapes the kubelet on every node and exposes real-time CPU/Memory metrics via the `metrics.k8s.io` API, which powers `kubectl top`.

**Q: Where does `kubectl top` get its data from?**

A: It queries the `metrics.k8s.io` API, which is served by the Kubernetes Metrics Server. The Metrics Server gets the data by scraping the kubelet Summary API on every node.

**Q: Does the Metrics Server store historical data?**

A: No. It only keeps a few minutes of data in memory. For historical data, you must use a tool like Prometheus.

**Q: What Kubernetes feature relies entirely on the Metrics Server to function?**

A: The Horizontal Pod Autoscaler (HPA). Without the Metrics Server, the HPA cannot calculate CPU utilization percentages and will show `<unknown>`.

**Q: You run `kubectl top pods` and get `error: metrics not available yet`. How do you troubleshoot this?**

A: First, I check if the Metrics Server is installed and running using `kubectl get pods -n kube-system`. If it is running, I check the logs (`kubectl logs <metrics-pod> -n kube-system`). Often, this is caused by TLS certificate errors where the Metrics Server cannot authenticate with the kubelet. I would verify the TLS configuration.

**Q: Can you use the Metrics Server to alert when CPU is high?**

A: No. The Metrics Server has no alerting or historical data capabilities. For alerting, use Prometheus.

## Scenario Questions

**Scenario 1:** Your HPA is not scaling. How do you diagnose?

A: I would check if the Metrics Server is installed and running. Then I would run `kubectl top pods` to verify metrics are available. If metrics are available, I would check the HPA configuration and events.

**Scenario 2:** You need to right-size your Pod resource requests. How do you do this?

A: I would use `kubectl top pods` to see actual CPU/Memory usage over time. Then I would adjust the `requests` and `limits` in the Pod spec to match the observed usage.

**Scenario 3 (Mini Project - The Memory Tracker):**

Deploy a Pod that allocates 200MB of RAM and holds it. Use `kubectl top pod` to verify the Pod is actually using ~200Mi of memory.

## Quiz

1. What is the Metrics Server?
   - A. A monitoring tool like Prometheus
   - B. A cluster-wide aggregator of resource usage data
   - C. A logging tool
   - D. A Dashboard

2. Where does the Metrics Server get its data from?
   - A. etcd
   - B. The kubelet Summary API
   - C. The API Server
   - D. Prometheus

3. How often does the Metrics Server scrape data?
   - A. Every 15 seconds
   - B. Every 60 seconds
   - C. Every 5 minutes
   - D. On-demand

4. What happens if you run `kubectl top` without the Metrics Server?
   - A. It shows cached data
   - B. It returns an error
   - C. It queries Prometheus
   - D. It works fine

5. What is the main difference between Metrics Server and Prometheus?
   - A. Metrics Server stores history, Prometheus doesn't
   - B. Metrics Server is in-memory only, Prometheus stores history
   - C. They are the same
   - D. Prometheus is for CPU, Metrics Server is for Memory

Answers: 1-B, 2-B, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- Metrics Server = Real-time usage (In-memory).
- Scrapes Kubelet every 60s.
- Powers `kubectl top` and HPA.
- No historical data.

Memory trick:

- **Metrics Server:** A census taker. Knocks on every Node's door (kubelet), asks how many resources the Pods are using, writes it on a clipboard (in-memory), and reports it to the government (`kubectl top`).

Key facts:

- Metrics Server = Real-time metrics.
- Scrapes Kubelet every 60s.
- In-memory only.
- Powers `kubectl top` and HPA.
- No history.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl top nodes` | Shows real-time CPU/Memory usage of nodes |
| `kubectl top pods` | Shows real-time CPU/Memory usage of pods in the namespace |
| `kubectl top pod -l app=myapp` | Filters metrics by label |

## References

- [Kubernetes Documentation: Resource Metrics Pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
- [Metrics Server GitHub](https://github.com/kubernetes-sigs/metrics-server)
- [Kubernetes Documentation: HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Kubernetes Documentation: API Aggregation](https://kubernetes.io/docs/concepts/extend-kubernetes/api-aggregation/)

## Related Lessons

- [Lesson 21 - Resource Management and the OOMKiller (Requests vs Limits)](../06-configuration/lesson-21-resource-requests-limits-and-quotas.md) - resource requests and limits.
- [Lesson 36 - Probes and Health Checks](lesson-26-probes-and-health-checks.md) - application health.
- [Lesson 39 - Horizontal Pod Autoscaler](../12-production/lesson-36-horizontal-pod-autoscaler.md) - HPA and VPA.

## Coming Next

Now that you understand how to monitor real-time metrics, the next lesson covers Logging — how to aggregate and query logs in Kubernetes.
