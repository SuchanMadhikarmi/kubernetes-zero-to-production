---
title: Lab 25 - Node Affinity and Pod Anti-Affinity
lesson: 25
module: 02 Architecture
tags: [kubernetes, scheduling, affinity, anti-affinity, high-availability]
---

# Lab 25 - Node Affinity and Pod Anti-Affinity

## Objective

In this lab you will create a Deployment with a strict Pod Anti-Affinity rule and observe how Kubernetes spreads Pods across nodes. You will then watch what happens when the scheduler runs out of valid nodes. Finally, you will test Node Affinity to pull Pods to labeled nodes.

## Prerequisites

- A running kind cluster (ideally multi-node: 1 control-plane, 2 workers)
- kubectl installed and configured
- Completion of Lessons 1 through 24

## Pre-Lab Checklist

- [ ] kind cluster running with multiple nodes
- [ ] `kubectl get nodes` shows 2+ workers
- [ ] Understand Pod Anti-Affinity and Node Affinity

---

## Step 1: Check Your Cluster

Verify you have multiple nodes:

```bash
kubectl get nodes
```

You should see at least 1 control-plane and 2 workers. If you only have 1 node, the anti-affinity demo won't work as expected.

## Step 2: Create HA Deployment with Required Anti-Affinity

Create `ha-deploy.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ha-web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - web
            topologyKey: kubernetes.io/hostname
      containers:
      - name: app
        image: nginx:alpine
```

Apply it:

```bash
kubectl apply -f ha-deploy.yaml
```

## Step 3: Observe the Spread

Wait about 15 seconds, then run:

```bash
kubectl get pods -l app=web -o wide
```

Notice where the Pods landed. One should be on `kind-worker`, and one should be on `kind-worker2`. They were forced to spread out.

## Step 4: Investigate the Failure

Run this command:

```bash
kubectl get pods -l app=web
```

Notice that the 3rd replica is likely NOT running. It is stuck in Pending.

Run this to see why:

```bash
kubectl describe pod -l app=web | grep -A 5 Events
```

**Your Task:**

- How many Pods are Running vs Pending?
- What is the exact warning/error message in the Events for the Pending Pod? (It should mention anti-affinity).
- Based on the cluster setup (1 control-plane + 2 workers), explain exactly why the 3rd Pod cannot be scheduled.

## Step 5: Switch to Preferred Anti-Affinity

Delete the current deployment:

```bash
kubectl delete deployment ha-web
```

Create `ha-preferred.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ha-web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - web
              topologyKey: kubernetes.io/hostname
      containers:
      - name: app
        image: nginx:alpine
```

Apply it:

```bash
kubectl apply -f ha-preferred.yaml
```

Wait 15 seconds, then check:

```bash
kubectl get pods -l app=web -o wide
```

Now all 3 Pods should be Running. The scheduler tried to spread them, but since there were only 2 workers, it placed 2 on one node and 1 on the other.

## Step 6: Test Node Affinity

Create `node-affinity.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ssd-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ssd
  template:
    metadata:
      labels:
        app: ssd
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: disktype
                operator: In
                values:
                - ssd
      containers:
      - name: app
        image: nginx:alpine
```

Apply it:

```bash
kubectl apply -f node-affinity.yaml
```

Check the pods:

```bash
kubectl get pods -l app=ssd
```

They should be Pending because no nodes have the label `disktype=ssd`.

## Step 7: Label a Node and Watch Pods Schedule

Label a worker node:

```bash
kubectl label nodes kind-worker disktype=ssd
```

Check the pods again:

```bash
kubectl get pods -l app=ssd -o wide
```

Now they should be Running on `kind-worker`.

## Step 8: Verify the Label

```bash
kubectl get nodes --show-labels | grep disktype
```

## Step 9: Cleanup

```bash
kubectl delete deployment ha-web
kubectl delete deployment ssd-app
kubectl label nodes kind-worker disktype-
```

---

## Lab Questions

1. Why did the 3rd Pod stay Pending with required anti-affinity?
2. What is the difference between required and preferred anti-affinity in practice?
3. How could you use topologyKey `topology.kubernetes.io/zone` for multi-AZ high availability?
4. What would happen if you had only 1 worker node and used required anti-affinity with 2 replicas?

---

## Expected Results

After completing this lab:
- You understand how Pod Anti-Affinity spreads Pods across nodes
- You know the difference between required and preferred scheduling rules
- You can apply Node Affinity to pull Pods to labeled nodes
- You can debug FailedScheduling events

---

## Key Commands Reference

| Command | Purpose |
|---------|---------|
| `kubectl get pods -o wide` | Show pods with node assignment |
| `kubectl describe pod <name>` | See scheduling events |
| `kubectl label nodes <node> <key>=<val>` | Add label to node |
| `kubectl label nodes <node> <key>-` | Remove label from node |
| `kubectl get nodes --show-labels` | Show all node labels |

---

## Next

- Return to the [Lesson 25 file](../02-architecture/lesson-25-node-affinity-and-anti-affinity.md) to review the concepts
- Try the advanced task: Use Pod Affinity (not Anti-Affinity) to co-locate related Pods
- Proceed to the next lesson to learn about the Kubernetes API and Controllers
