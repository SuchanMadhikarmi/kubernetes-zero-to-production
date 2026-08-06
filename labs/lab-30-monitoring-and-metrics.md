# Lab 30 - Monitoring and Metrics

## Prerequisite

- Completion of [Lesson 30 - Monitoring and Metrics](../docs/08-observability/lesson-30-monitoring-and-metrics.md).
- A running kind cluster.
- kubectl installed and configured.

## Objective

Install the Metrics Server in kind, deploy a CPU-hogging application, and use `kubectl top` to identify the culprit.

## Estimated Time

15 minutes.

---

## Step 1: Install the Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## Step 2: Patch it for Kind

Kind's kubelet uses self-signed certificates that the Metrics Server doesn't trust by default. We must tell it to skip TLS verification (NEVER do this in real production).

```bash
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

## Step 3: Wait for it to be Ready

```bash
kubectl get deployment metrics-server -n kube-system
```

Wait until the `READY` column shows `1/1`.

## Step 4: Verify it Works

Wait about 60 seconds for the first scrape to happen, then run:

```bash
kubectl top nodes
```

Expected output: CPU and Memory usage for your control-plane and worker nodes.

## Step 5: Deploy the CPU Hog

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

Apply it:

```bash
kubectl apply -f hog.yaml
```

## Step 6: Investigate with kubectl top

Wait about 60 seconds for the metrics to update, then run:

```bash
kubectl top pods
```

**Your Task:**

- What is the CPU usage of the `cpu-hog` pod? (It should be somewhere around 500m, which is 50% of a core, or 500 millicores).
- What command would you run to see the CPU usage of only the `cpu-hog` pod using a label selector?
- Based on the theory, where did the Metrics Server get this real-time data from?

(Answer: 1. ~500m. 2. `kubectl top pod -l app=hog`. 3. The Kubelet's Summary API, which reads the cgroup stats on the node).

## Step 7: Cleanup

```bash
kubectl delete pod cpu-hog
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## What You Learned

- The Metrics Server is a cluster-wide aggregator of resource usage data.
- It scrapes the kubelet on every node and exposes real-time CPU/Memory metrics.
- It powers `kubectl top` and the Horizontal Pod Autoscaler (HPA).
- It stores data in-memory only (no historical data).

## Next Steps

Proceed to [Lesson 31 - Logging](../docs/08-observability/lesson-31-logging.md) to learn about aggregating logs in Kubernetes.

---

[Back to Labs](README.md)
