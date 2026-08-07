---
title: Lesson 4 - Pod Priority and Preemption
module: 02 Architecture
lesson: 4
status: Complete
tags: [kubernetes, scheduling, priority, preemption, priorityclass, victim, graceful-termination]
---

# Lesson 17 - Pod Priority and Preemption

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

- Explain how Kubernetes decides which Pods to evict when a node is full.
- Describe what a PriorityClass is and how to assign it to a Pod.
- Explain the mechanics of Preemption: killing lower-priority Pods to make room for higher-priority ones.
- Intentionally exhaust cluster resources and watch a high-priority Pod kill a low-priority Pod.

## Prerequisites

- Completion of Lessons 1 through 16.
- A running kind cluster (ideally the multi-node cluster from Lesson 3).
- kubectl installed and configured.

## Real-world Motivation

### The Blocked VIP

Imagine you have a cluster running at 95% capacity. 5% of the resources are consumed by a low-priority background data analytics job. Suddenly, a traffic spike hits your production API. The Horizontal Pod Autoscaler (HPA) tries to scale up the API by adding a new Pod. Because the cluster is technically full, the kube-scheduler leaves the critical API Pod in Pending. The API cannot handle the traffic, and users experience timeouts. Meanwhile, the low-priority analytics job continues running happily, oblivious to the production outage.

### Why This Exists

Kubernetes needed a way to prioritize workloads. By using PriorityClasses, you can tell the scheduler: "If the cluster is full, it is acceptable to kill the low-priority analytics job to make room for the critical production API." This allows companies to run clusters at 100% capacity by filling the "gaps" with sacrificial batch jobs, maximizing cloud cost efficiency.

### Real Company Examples

**Yelp:** Yelp runs massive data processing pipelines. The pipeline pods have a very low PriorityClass. During the day, when user traffic increases and the core web services need to scale up, Kubernetes automatically preempts the data pipelines. The web services scale up instantly, and the pipelines just resume at night when traffic drops.

## Core Concepts

### Explain Like I'm 12

Imagine a lifeboat on a sinking ship. There is only room for 5 people. If a VIP (like the captain) arrives and the boat is full, a regular passenger is forced to get out of the boat so the VIP can sit down. The VIP has a higher priority.

### Explain Like I'm a Junior Engineer

A PriorityClass is a Kubernetes object that assigns a numeric priority to a Pod (e.g., 1000000). When the Scheduler tries to place a Pod and no nodes have enough resources, the Scheduler looks at the Pending Pod's priority. If it is higher than running Pods, the Scheduler will evict (kill) the lower-priority running Pods to free up space. This is called Preemption.

### Explain Technically

- **PriorityClass:** A cluster-scoped object mapping a name to an integer priority.
- **Preemption:** The kube-scheduler's two-phase process for high-priority Pending Pods:
  1. It finds nodes where low-priority Pods can be victims.
  2. It triggers the API Server to send DELETE requests for those victim Pods.
- **preemptionPolicy:** `PreemptLowerPriority` (default) or `Never`.

### How Kubernetes Implements It Internally

The kube-scheduler scores all nodes. If a node doesn't have enough capacity for the incoming Pod, the scheduler checks if evicting one or more lower-priority Pods on that node would free up enough resources. If so, it nominates the node for the high-priority pod and sends DELETE requests to the API Server for the victim Pods. The victims are given a `gracePeriodSeconds` to terminate.

### Why Kubernetes Was Designed That Way

Kubernetes was designed to allow cluster overcommitment. By filling nodes with low-priority "sacrificial" workloads, you maximize resource utilization. When critical workloads need space, the scheduler automatically makes room by evicting the low-priority workloads.

## Architecture

```
[ New Pod: High Priority (VIP) ] -> Scheduler: "No nodes have enough CPU!"
      |
      v
[ Preemption Phase ]
      |
      +---> Looks at Node A: Has 3 low-priority pods. If I kill 1, the VIP fits!
      |
      v
[ API Server ] -> Deletes the 1 low-priority Pod (Victim)
      |
      v
[ Scheduler ] -> Binds the High Priority VIP Pod to Node A
```

### Terminology

| Term | Definition |
|------|------------|
| PriorityClass | A cluster-scoped object that assigns an integer priority value to a Pod. |
| Preemption | The act of terminating lower-priority Pods to free up resources for a higher-priority Pod. |
| Victim | The Pod that is killed during the preemption process. |
| globalDefault | A boolean field on a PriorityClass. If true, any Pod without a specified priority uses this class. |

### How It Works Internally

1. You create a PriorityClass named `high-priority` with `value: 1000000`.
2. You create a PriorityClass named `low-priority` with `value: 100`.
3. You deploy a Pod with `priorityClassName: low-priority`. It schedules successfully.
4. The cluster fills up to 100% capacity.
5. You deploy a Pod with `priorityClassName: high-priority`.
6. The Scheduler tries to find a node. All nodes are full.
7. The Scheduler enters the Preemption phase. It looks for nodes where the sum of lower-priority Pod requests is greater than or equal to the high-priority Pod's request.
8. It finds a node with a low-priority Pod. It nominates this node.
9. The Scheduler sends a DELETE request to the API Server for the low-priority Pod.
10. The API Server deletes the victim Pod. The ReplicaSet (if any) will try to recreate it, but it will stay Pending because the high-priority Pod took the resources.
11. The high-priority Pod is bound to the node and starts.

### Step-by-Step Workflow

1. Admin creates PriorityClasses for the cluster.
2. Developer deploys an app, specifying `priorityClassName: high-priority`.
3. If the cluster has space, the Pod schedules normally.
4. If the cluster is full, the Scheduler finds victims.
5. Victims are deleted.
6. High-priority Pod is scheduled.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | PriorityClass is created. Pods reference it. |
| Scheduling | Normal scheduling if resources are available. |
| Preemption | Triggered when a higher-priority Pod is Pending and lower-priority Pods can be sacrificed. |
| Deletion | PriorityClass is deleted. Existing Pods keep their priority, but new Pods cannot use the class. |

### QoS vs PriorityClass

| Feature | QoS Class | PriorityClass |
|---------|-----------|---------------|
| What it controls | Which Pod dies when a Node runs out of memory (Eviction). | Which Pod gets killed by the Scheduler to make room for a better Pod. |
| Trigger | Node Memory/Disk Pressure. | Cluster is full, new Pod is Pending. |
| Mechanism | Kubelet kills BestEffort first. | Scheduler deletes lowest priority victims. |
| Scope | Pod resource requests/limits. | Integer value in PriorityClass. |

### Common Myths

| Myth | Fact |
|------|------|
| "Preemption is the same as OOMKilling." | False. OOMKilling is a kernel-level action triggered by a container exceeding its memory limit. Preemption is a scheduler-level action triggered by a high-priority Pod needing space in the cluster. |
| "If I give my Pod a high priority, it will run faster." | False. Priority only affects scheduling order and victim selection. Once running, the CPU/Memory limits dictate performance, not the PriorityClass. |

## ASCII Diagrams

Mental Model: A VIP line at a club. The club (Node) is full. A VIP arrives (High Priority Pod). The bouncer (Scheduler) kicks out a regular guest (Low Priority Pod) to let the VIP in.

```
[ Node (CPU Capacity: 2 cores) ]
   - Pod A (Low Priority, Request: 1 core)
   - Pod B (Low Priority, Request: 1 core)
   (Node is 100% full)

[ New Pod C (High Priority, Request: 1 core) arrives ]
      |
      v
[ Scheduler: "Node is full. Can I evict victims?" ]
      |
      v (Kills Pod B)
[ Pod C is scheduled and starts running ]
```

## Hands-on

### Objective

Create a low-priority app that fills up the cluster, and then deploy a high-priority app that kicks the low-priority app out.

**Note:** This lab assumes a 2-worker-node Kind cluster. Each worker node typically has ~2 CPU cores available. We will request 1 core per pod to fill them up.

### Step 1: Create Priority Classes

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

**Field Explanation:**

- `value`: The integer priority. 1000000 > 100.
- `globalDefault: false`: We don't want this applied to every pod in the cluster automatically.

Apply it:

```bash
kubectl apply -f priority.yaml
```

### Step 2: Fill the Cluster with Low-Priority Pods

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

**Field Explanation:**

- `priorityClassName`: Links the Pod to the PriorityClass.
- `requests.cpu: "1000m"`: We request a large chunk of CPU so the cluster fills up quickly.

Apply it and wait for the pods to run:

```bash
kubectl apply -f low-app.yaml
kubectl get pods -l app=low -o wide
```

(You should see 4 pods running, spread across the 2 worker nodes).

### Step 3: Deploy the High-Priority VIP Pod

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

### Step 4: Investigate the Preemption

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

### Step 5: Cleanup

```bash
kubectl delete pod high-priority-vip
kubectl delete deployment low-priority-app
kubectl delete priorityclass high-priority low-priority
```

## Commands

```bash
# Lists all PriorityClasses in the cluster
kubectl get priorityclasses

# Look for Preempted events to see if a pod was a victim or an aggressor
kubectl describe pod <name>

# Check which PriorityClass a Pod uses
kubectl get pod <name> -o yaml | grep priorityClassName

# Check PriorityClass details
kubectl get priorityclass <name> -o yaml
```

## YAML Explanation

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
description: "Critical apps that must schedule."
---
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

### Field-by-Field Explanation

- `PriorityClass.value`: The integer priority. Higher = more important.
- `PriorityClass.globalDefault`: If true, any Pod without a priority uses this class.
- `Deployment.spec.template.spec.priorityClassName`: Links the Pod to the PriorityClass.
- `resources.requests.cpu`: The CPU request that determines how much space the Pod needs.

## Production Notes

- **Don't make everything high priority:** If every app is high priority, preemption stops working, and you just end up with Pods stuck in Pending. Reserve high priority for critical services (payment gateways, core APIs).
- **Use `preemptionPolicy: Never` cautiously:** If you want a Pod to jump to the front of the scheduling queue but NOT kill other Pods, use this policy. It will still prioritize the Pod when a node frees up naturally.
- **Set Grace Periods:** If your low-priority batch jobs need time to save state before dying, ensure their `terminationGracePeriodSeconds` is high enough. However, the scheduler might force-kill them if the high-priority Pod waits too long.

### When to Use / When NOT to Use

**Use PriorityClasses when:**

- Separating critical system components from user applications.
- Running background batch jobs on the same nodes as production apps (the batch jobs get preempted during traffic spikes).
- Prioritizing development environments (e.g., Prod > Staging > Dev on a shared cluster).

**Avoid strict preemption when:**

- Batch jobs cannot be interrupted. If losing progress on a 4-hour job is unacceptable, do not run it as a preemptible low-priority pod.

### Performance and Security Considerations

**Performance:** Preemption is a relatively expensive calculation for the Scheduler. In massive clusters (1,000+ nodes), complex priority rules can slow down scheduling.

**Security:** If a developer can create a PriorityClass with a value higher than the system Pods, they could preempt CoreDNS or the API Server. Restrict PriorityClass creation to cluster admins using RBAC.

## Best Practices

- Reserve high priority for critical services only.
- Use `preemptionPolicy: Never` for non-critical but time-sensitive workloads.
- Set appropriate `terminationGracePeriodSeconds` for batch jobs.
- Restrict PriorityClass creation to cluster admins.
- Monitor preemption events with `kubectl describe pod`.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Giving high priority to batch jobs | Not understanding preemption | Reserve high priority for critical services |
| Forgetting `globalDefault` | Assuming all Pods need explicit priority | Set a reasonable globalDefault for most workloads |
| PDBs blocking preemption | Confusing voluntary vs involuntary disruptions | PDBs protect against voluntary disruptions; preemption can bypass them |
| All apps high priority | Trying to make everything important | Reserve high priority for truly critical services |

## Troubleshooting

**Symptom: High-priority Pod stays Pending despite low-priority Pods running**

Cause: The low-priority Pods have the same or higher priority.

```bash
kubectl get pod <name> -o yaml | grep priorityClassName
kubectl get priorityclass <name> -o yaml | grep value
```

Fix: Ensure the low-priority Pods actually have a lower priority value.

**Symptom: Preemption not happening**

Cause: `preemptionPolicy: Never` is set.

```bash
kubectl get priorityclass <name> -o yaml | grep preemptionPolicy
```

Fix: Change `preemptionPolicy` to `PreemptLowerPriority` if you want preemption.

**Symptom: Victim Pod not being recreated**

Cause: The ReplicaSet is trying to recreate it, but it stays Pending.

```bash
kubectl get pods -l app=<low-priority-label>
```

Fix: This is expected behavior. The new low-priority Pod will stay Pending until resources are freed.

## Interview Questions

**Q: What is a PriorityClass in Kubernetes?**

A: A cluster-scoped object that maps a name to an integer priority value. It allows you to define the relative importance of a Pod.

**Q: What is Preemption?**

A: The process of terminating lower-priority Pods to free up node resources so a higher-priority Pending Pod can be scheduled.

**Q: What is the difference between QoS and PriorityClass?**

A: QoS dictates which Pods the Kubelet kills when a node runs out of memory. PriorityClass dictates which Pods the Scheduler kills to make room for a more important Pending Pod.

**Q: If a low-priority Pod is preempted, does its ReplicaSet try to recreate it?**

A: Yes. The ReplicaSet notices the Pod is gone and creates a new one. However, because the high-priority Pod took the freed resources, the new low-priority Pod will likely stay in Pending.

**Q: You have a cluster running at 100% capacity with background jobs. A critical API needs to scale up, but the new Pods are stuck in Pending. How do you fix this without adding more nodes?**

A: I would implement PriorityClasses. I would assign a high PriorityClass to the critical API Pods, and a low PriorityClass to the background jobs. When the API tries to scale, the Scheduler will preempt (kill) the low-priority jobs, allowing the API Pods to schedule immediately.

**Q: Is preemption triggered when a node runs out of memory?**

A: No. That's Eviction/OOMKill. Preemption is triggered by the Scheduler when a high-priority Pod needs space.

## Scenario Questions

**Scenario 1:** You have a cluster with production APIs and batch data processing jobs. How do you ensure the APIs always have resources?

A: I would create a `high-priority` PriorityClass for the APIs and a `low-priority` PriorityClass for the batch jobs. When the cluster is full and the APIs need to scale, the Scheduler will preempt the batch jobs.

**Scenario 2:** A developer wants their non-critical pod to have priority 1000000. How do you prevent this?

A: I would restrict PriorityClass creation to cluster admins using RBAC. Developers should not be able to create PriorityClasses.

**Scenario 3 (Mini Project - The Non-Preempting Queue):**

Create a PriorityClass named `queue-only` with `preemptionPolicy: Never` and a high value. Fill your cluster with default-priority pods. Deploy a pod using the `queue-only` class. Observe that it stays Pending (it jumps to the front of the scheduling queue) but does NOT kill the existing pods. Delete a default-priority pod manually. The `queue-only` pod should instantly schedule in the freed space.

## Quiz

1. What is a PriorityClass?
   - A. A Pod resource limit
   - B. A cluster-scoped object that assigns priority to Pods
   - C. A node label
   - D. A NetworkPolicy

2. What happens during preemption?
   - A. The kubelet kills Pods
   - B. The scheduler kills lower-priority Pods
   - C. The API server deletes Pods
   - D. The controller manager restarts Pods

3. What is the difference between QoS and PriorityClass?
   - A. They are the same
   - B. QoS is for memory eviction, PriorityClass is for scheduling
   - C. QoS is for scheduling, PriorityClass is for memory eviction
   - D. Neither affects Pod lifecycle

4. What is `preemptionPolicy: Never`?
   - A. Disables preemption entirely
   - B. The Pod won't kill other Pods but will be scheduled first when space opens
   - C. The Pod will always be preempted
   - D. The Pod cannot be deleted

5. Who should create PriorityClasses?
   - A. Developers
   - B. Cluster admins
   - C. The kubelet
   - D. The scheduler

Answers: 1-B, 2-B, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- PriorityClass = Integer value.
- Preemption = High priority kills low priority.
- Victim = The pod that gets killed.
- Don't make everything high priority.

Memory trick:

- **PriorityClass:** A VIP wristband at a concert.
- **Preemption:** The bouncer kicking a general-admission fan out of the front row so the VIP can sit down.

Key facts:

- PriorityClass = Priority value.
- Preemption = Scheduler kills low priority.
- Victim = Killed pod.
- QoS = Memory eviction.
- PriorityClass = Scheduling priority.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl get priorityclasses` | Lists all PriorityClasses in the cluster |
| `kubectl describe pod <name>` | Look for Preempted events to see if a pod was a victim or an aggressor |

## References

- [Kubernetes Documentation: Pod Priority and Preemption](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)
- [Kubernetes Documentation: PriorityClass](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#priorityclass-v1-scheduling-k8s-io)
- [Kubernetes Documentation: Pod Disruption Budgets](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)

## Related Lessons

- [Lesson 3 - Controlling Where Pods Run (Scheduling and Taints)](lesson-03-worker-node-architecture.md) - how the scheduler works.
- [Lesson 21 - Resource Management and the OOMKiller (Requests vs Limits)](../06-configuration/lesson-21-resource-requests-limits-and-quotas.md) - resource requests and limits.
- [Lesson 36 - Probes and Health Checks](../08-observability/lesson-26-probes-and-health-checks.md) - application health.

## Coming Next

Now that you understand how to prioritize workloads, the next lesson covers Storage — how to persist data in Kubernetes using Volumes, Persistent Volumes, and Storage Classes.
