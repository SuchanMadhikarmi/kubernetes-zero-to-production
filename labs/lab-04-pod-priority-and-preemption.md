# Lab 4 - Pod Priority and Preemption

## Prerequisite

- Completion of [Lesson 4 - Pod Priority and Preemption](../docs/02-architecture/lesson-04-pod-priority-and-preemption.md).
- A running kind cluster (ideally multi-node).
- kubectl installed and configured.

## Objective

Create a low-priority app that fills up the cluster, and then deploy a high-priority app that kicks the low-priority app out.

## Estimated Time

15 minutes.

---

## Step 1: Create Priority Classes

Create `priority.yaml`:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
description: "Critical apps that must schedule."
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority
value: 100
globalDefault: false
description: "Background batch jobs."
```

Apply it:

```bash
kubectl apply -f priority.yaml
```

Expected output:

```
priorityclass.scheduling.k8s.io/high-priority created
priorityclass.scheduling.k8s.io/low-priority created
```

## Step 2: Fill the Cluster with Low-Priority Pods

Create `low-app.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: low-priority-app
spec:
  replicas: 4
  selector:
    matchLabels:
      app: low
  template:
    metadata:
      labels:
        app: low
    spec:
      priorityClassName: low-priority
      containers:
      - name: app
        image: busybox:latest
        command: ["sleep", "3600"]
        resources:
          requests:
            cpu: "1000m"
```

Apply it and wait for the pods to run:

```bash
kubectl apply -f low-app.yaml
kubectl get pods -l app=low -o wide
```

Expected output: 4 pods running, spread across the worker nodes.

## Step 3: Deploy the High-Priority VIP Pod

Create `high-app.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: high-priority-vip
  labels:
    app: high
spec:
  priorityClassName: high-priority
  containers:
  - name: app
    image: busybox:latest
    command: ["sleep", "3600"]
    resources:
      requests:
        cpu: "1000m"
```

Apply it:

```bash
kubectl apply -f high-app.yaml
```

## Step 4: Investigate the Preemption

Wait about 5-10 seconds, then run:

```bash
kubectl get pods -l app=high
kubectl get pods -l app=low
```

**Your Task:**

- Did the `high-priority-vip` pod successfully start running?
- What happened to the `low-priority-app` pods? Did the replica count drop, or did one of the pods get deleted/replaced?
- Run `kubectl describe pod high-priority-vip` and look at the Events section. What does the message say about preemption and the victims?

(Answer: 1. Yes. 2. One low-priority pod was deleted. The ReplicaSet tries to recreate it to maintain 4 replicas, but the new pod stays Pending because the VIP took the CPU. 3. The events show `Preempted` and list the victim pod name).

## Step 5: Cleanup

```bash
kubectl delete pod high-priority-vip
kubectl delete deployment low-priority-app
kubectl delete priorityclass high-priority low-priority
```

---

## What You Learned

- PriorityClass assigns an integer priority value to a Pod.
- Preemption is the process of terminating lower-priority Pods to free up node resources.
- This allows cluster overcommitment: packing nodes full of low-priority workloads that act as "sacrificial lambs" for critical services.
- Victim Pods are deleted and given a graceful termination period.

## Next Steps

Proceed to [Lesson 15 - Ingress and Ingress Controllers](../docs/04-networking/lesson-15-ingress-and-ingress-controllers.md) to learn about exposing applications externally.

---

[Back to Labs](README.md)
