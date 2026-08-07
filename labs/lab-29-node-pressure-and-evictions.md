---
title: Lab 29 - Node Pressure and Evictions
lesson: 29
module: 13 Troubleshooting
tags: [kubernetes, node-pressure, evictions, memory, disk, kubelet]
---

# Lab 29 - Node Pressure and Evictions

## Objective

In this lab you will induce real memory pressure on a small, memory-constrained kind node, deploy a memory-hog workload, and watch the kubelet set node conditions and evict Pods to save the node. You will capture the node conditions, the eviction events, and the evicted Pod's terminal state, then clean up everything you created.

## Prerequisites

- A running kind cluster with a small, memory-constrained worker node
- kubectl installed and configured
- Completion of Lessons 1 through 28, especially Lesson 25 (Resource Requests, Limits, and Quotas) and Lesson 27 (SRE Troubleshooting)

## Pre-Lab Checklist

- [ ] `kind` CLI installed
- [ ] `kubectl` installed and configured
- [ ] Docker or your container runtime is running
- [ ] You understand QoS Classes (Guaranteed, Burstable, BestEffort) and the difference between eviction and OOMKilled

---

## Step 1: Create a Memory-Constrained Cluster

A default kind node has too much memory to trigger pressure conveniently. Create a specially configured kind cluster that limits the node's memory so the thresholds are reachable with a small workload.

Create `kind-node-pressure.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraEnv:
  - name: KUBELET_KUBECONFIG_ARGS
    value: "--eviction-hard=memory.available<10Mi"
```

Create the cluster:

```bash
kind create cluster --config kind-node-pressure.yaml
```

Verify the cluster and the single node:

```bash
kubectl get nodes
kubectl get nodes -o wide
```

Expected output (the exact IP and version values vary):

```text
NAME                 STATUS   ROLES           AGE   VERSION
node-pressure-test   Ready    control-plane   41s   v1.30.0
```

## Step 2: Inspect the Healthy Node Conditions

Before inducing pressure, record the node's baseline health.

```bash
kubectl describe node node-pressure-test
```

Look at the `Conditions:` and `Allocatable:` sections. In a healthy state the conditions look like this:

```text
Conditions:
  Type             Status  LastHeartbeatTime
  ----             ------  -----------------
  MemoryPressure   False   ...
  DiskPressure     False   ...
  PIDPressure      False   ...
  Ready            True    ...
```

Also record how much memory the node reports as allocatable:

```bash
kubectl describe node node-pressure-test | grep -A 8 Allocatable
```

Note the value under `memory`. This is the budget the scheduler can offer to Pods, and it is the baseline against which pressure thresholds are measured.

## Step 3: Create a Low-Risk Baseline Pod

Deploy a stable, low-priority Pod to observe how the node reacts when pressure arrives. Create `baseline.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: baseline
spec:
  replicas: 1
  selector:
    matchLabels:
      app: baseline
  template:
    metadata:
      labels:
        app: baseline
    spec:
      containers:
      - name: sleeper
        image: busybox:latest
        command: ["sh", "-c", "sleep 3600"]
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            memory: 32Mi
```

Apply it and confirm it runs:

```bash
kubectl apply -f baseline.yaml
kubectl get pods -l app=baseline -w
```

Expected output shows the Pod go from `ContainerCreating` to `Running`:

```text
NAME                       READY   STATUS    RESTARTS   AGE
baseline-                     0/1     ContainerCreating   0     2s
baseline-                     1/1     Running             0     6s
```

Check its QoS class:

```bash
kubectl get pod -l app=baseline -o jsonpath='{.items[0].status.qosClass}'
```

Because request and limit are set, this Pod is `Burstable`.

## Step 4: Deploy the Memory Hog

Now create a memory hog. The kubelet is configured with a hard eviction threshold of `memory.available < 10Mi`, so this workload will push the node over the line.

Create `memory-hog.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-hog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: memory-hog
  template:
    metadata:
      labels:
        app: memory-hog
    spec:
      containers:
      - name: hogger
        image: polinux/stress
        command:
        - stress
        - --vm
        - "2"
        - --vm-bytes
        - "1G"
        - --vm-hang
        - "60"
```

Apply it:

```bash
kubectl apply -f memory-hog.yaml
```

Wait a few seconds for the stress tool to start consuming RAM:

```bash
sleep 15
kubectl get pods
```

You should see the `memory-hog` Pod running, and shortly after you may see it flip to `Evicted` or `OOMKilled` as the node runs out of memory.

## Step 5: Observe the Node Condition Flip to MemoryPressure

While the hog is active, check the node conditions again.

```bash
kubectl describe node node-pressure-test
```

In the `Conditions:` section you should now see `MemoryPressure` set to `True`:

```text
Conditions:
  Type             Status  LastHeartbeatTime
  ----             ------  -----------------
  MemoryPressure   True    ...
  DiskPressure     False   ...
  PIDPressure      False   ...
```

While a node is under pressure, the scheduler also stops placing new Pods on it. This is the kubelet flagging that this node cannot safely accept more workloads.

## Step 6: Find the Eviction Events

The kubelet records an event each time it evicts a Pod. Find those events cluster-wide.

```bash
kubectl get events --all-namespaces
```

Or filter only for evictions:

```bash
kubectl get events -A | grep -i evict
```

Expected output includes lines similar to:

```text
LOWEST    2m10s   Normal    Evicted    pod/memory-hog-...    The node was low on resource: memory. Container hogger was evicted...
```

## Step 7: Inspect the Evicted Pod's Terminal Status

Look at the evicted Pod directly to see its reason and QoS class.

```bash
kubectl get pods -l app=memory-hog
kubectl describe pod -l app=memory-hog
```

In `kubectl describe`, the Pod's status shows `Reason: Evicted` in the `Status` section, and the `Events` section shows that the kubelet evicted it because the node was out of memory.

## Step 8: Let the Node Recover and Confirm the Condition Clears

The ReplicaSet controller notices the evicted Pod and tries to place a replacement. If it keeps landing on the same pressured node, it can be evicted again; if the hog continues, the pressure may persist. To let the node recover, remove the hog, then re-check conditions.

```bash
kubectl delete deployment memory-hog
sleep 15
kubectl describe node node-pressure-test
```

In the `Conditions:` section, `MemoryPressure` should have returned to `False` now that the hog is gone.

## Step 9: Cleanup

Remove every resource created in this lab.

```bash
kubectl delete -f baseline.yaml
kubectl delete -f memory-hog.yaml
kind delete cluster --name node-pressure-test
```

Confirm the last command output:

```text
Deleting cluster "node-pressure-test" ...
```

---

## Lab Questions

1. Which QoS class is evicted first when a node hits memory pressure, and why?
2. What is the difference between a Pod being `Evicted` and a container being `OOMKilled`?
3. What does the scheduler do when a node reports `MemoryPressure=True`?
4. Why might an evicted Pod be recreated and immediately evicted again?

---

## Expected Results

After completing this lab:

- You can create a memory-constrained kind node for safe testing
- You can induce memory pressure and observe the node condition flip to `True`
- You can read eviction events and inspect an evicted Pod's status
- You understand the difference between eviction and OOMKilled

---

## Key Commands Reference

| Command | Purpose |
|---------|---------|
| `kubectl describe node <name>` | Read node conditions and allocatable resources |
| `kubectl get events -A \| grep -i evict` | Find Pods the kubelet evicted |
| `kubectl get pod <name> -o jsonpath='{.status.qosClass}'` | Show a Pod's QoS class |
| `kubectl describe pod <name>` | Inspect an evicted Pod's reason and events |
| `kind delete cluster --name <name>` | Tear down the test cluster |

---

## Next

- Return to the [Lesson 29 file](../docs/13-troubleshooting/lesson-29-node-pressure-and-evictions.md) to review the concepts
- Try the Mini Project: deploy a Guaranteed QoS Pod alongside the hog and confirm it survives while the BestEffort Pod is evicted first
- Proceed to the next lesson to learn about troubleshooting networking and cluster-level issues