---
title: Lesson 5 - Node Affinity and Pod Anti-Affinity
module: 02 Architecture
lesson: 5
status: Complete
tags: [kubernetes, scheduling, affinity, anti-affinity, high-availability, node-selector]
---

# Lesson 25 - Node Affinity and Pod Anti-Affinity

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

- Explain why Node Selectors are not enough for production.
- Define Node Affinity and its two modes: Required and Preferred.
- Define Pod Anti-Affinity and why it is the secret to High Availability.
- Apply topology keys to spread Pods across nodes or zones.
- Intentionally create an impossible scheduling rule and watch the Scheduler freeze.

## Prerequisites

- Completion of Lessons 1 through 24.
- A running kind cluster (ideally multi-node: 1 control-plane, 2 workers).
- kubectl installed and configured.

## Real-world Motivation

### The Single Point of Failure

Imagine you deploy a web application with 3 replicas. The kube-scheduler looks for nodes with enough CPU and RAM. It happens to place all 3 Pods onto Node A because it had the most free capacity at that exact second. Later, Node A suffers a motherboard failure and goes completely offline. Because all 3 of your web Pods were on Node A, your application is now 100% down. Users see 502 Bad Gateway errors.

### Why This Exists

Kubernetes needed a way to enforce physical diversity. Pod Anti-Affinity allows you to tell the Scheduler: "Never put two of these identical Pods on the same physical node." This ensures that if a node dies, you only lose a fraction of your capacity, not the whole application. Node Affinity also upgrades the simple nodeSelector to allow "soft" preferences (e.g., "I prefer nodes in the east zone, but anywhere is fine").

### Real Company Examples

**Slack:** Slack runs large Redis clusters for caching. They use Pod Anti-Affinity with the `topology.kubernetes.io/zone` key. This ensures that if AWS's us-east-1a datacenter loses power, only 1/3rd of their Redis cache capacity is lost, not all of it. The application keeps running, just with slightly degraded cache performance.

## Core Concepts

### Explain Like I'm 12

Don't put all your eggs in one basket. If you drop the basket, all the eggs break. Pod Anti-Affinity is the rule that says: "Put one egg in the red basket, one in the blue basket, and one in the green basket."

### Explain Like I'm a Junior Engineer

Node Affinity is the upgraded nodeSelector. It allows you to say "I strictly require nodes with SSDs" (Required), or "I prefer nodes in the east zone, but anywhere is fine" (Preferred).

Pod Anti-Affinity lets your Pods decide where they want to live based on where other Pods are already living. You can say, "Do not schedule me on a node that already has a Pod with the label app=web."

### Explain Technically

- **Node Affinity** matches against Node labels.
- **Pod Anti-Affinity** matches against Pod labels running on the nodes.
- Both have two modes:
  - `requiredDuringSchedulingIgnoredDuringExecution`: A hard rule. If it can't be met, the Pod stays Pending.
  - `preferredDuringSchedulingIgnoredDuringExecution`: A soft rule. The Scheduler tries to meet it, but if it can't, it schedules the Pod anyway.
- **topologyKey**: The node label used to define the "domain" (e.g., `kubernetes.io/hostname` means "different nodes", `topology.kubernetes.io/zone` means "different cloud availability zones").

### How Kubernetes Implements It Internally

The kube-scheduler runs its Filtering phase. For Pod Anti-Affinity, it looks at the incoming Pod's rules. It scans the cluster for existing Pods matching the anti-affinity label. If it finds them, it notes which nodes they are on (using the topologyKey). It then filters out those nodes from the available list for the new Pod.

### Why Kubernetes Was Designed That Way

Kubernetes was designed for microservice architectures. To ensure high availability, it needs a way to enforce physical diversity without requiring manual intervention. Node Affinity and Pod Anti-Affinity give operators fine-grained control over Pod placement while still allowing the scheduler to make intelligent decisions.

## Architecture

```
[ Deployment: web-app (replicas: 3) ]
Rule: PodAntiAffinity (Hard Requirement: topologyKey=hostname)

1. Pod 1 scheduled -> lands on Node A.
2. Pod 2 scheduled -> Node A is rejected (Pod 1 is there). Lands on Node B.
3. Pod 3 scheduled -> Node A rejected, Node B rejected. Node C is tainted.
   -> RESULT: Pod 3 stays PENDING.
```

### Terminology

| Term | Definition |
|------|------------|
| Node Affinity | A scheduling rule that matches a Pod to a Node based on Node labels. |
| Pod Anti-Affinity | A scheduling rule that keeps a Pod away from other Pods matching a specific label. |
| topologyKey | The node label used to define the boundary for anti-affinity (e.g., hostname, zone). |
| required | A hard scheduling rule. Must be met or the Pod stays Pending. |
| preferred | A soft scheduling rule. The scheduler attempts to meet it, but will ignore it if impossible. |

### How It Works Internally

1. You create a Deployment with 3 replicas and a strict Pod Anti-Affinity rule using the `kubernetes.io/hostname` topology key.
2. The Scheduler places Pod 1 on Node A.
3. Pod 2 arrives. The Scheduler sees the anti-affinity rule. It checks Node A. Node A has a Pod with the label `app=web`. The Scheduler filters out Node A. It places Pod 2 on Node B.
4. Pod 3 arrives. The Scheduler filters out Node A (has Pod 1) and Node B (has Pod 2). Node C is the control plane (tainted).
5. Pod 3 has nowhere to go. It stays Pending forever.

### Step-by-Step Workflow

1. Developer creates a Deployment with a `podAntiAffinity` rule.
2. API Server saves it to etcd.
3. Scheduler notices the first Pod. It evaluates the anti-affinity rule. Since no other Pods exist yet, it schedules it normally.
4. Scheduler notices the second Pod. It sees the anti-affinity rule. It filters out the node where the first Pod is running. It schedules it on a different node.
5. This continues for all replicas.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | Pods are created and spread across nodes based on the rules. |
| Node Failure | If a node fails, the Pods on it are rescheduled. If the anti-affinity rule is strict (required), they may stay Pending if no other valid nodes exist. If it is soft (preferred), they will be scheduled on the remaining nodes, violating the preference but keeping the app online. |
| Deletion | Standard Pod deletion. |

### Communication Patterns

| Communication | Mechanism | Example |
|---------------|-----------|---------|
| Pod -> Node | Affinity pulls Pod to Node | `requiredDuringScheduling` with `disktype=ssd` |
| Pod <- Pod | Anti-Affinity pushes Pod away from Pod | `requiredDuringScheduling` with `app=web` and `topologyKey=hostname` |

### Common Myths

| Myth | Fact |
|------|------|
| "If I use a NodeSelector and the node dies, Kubernetes will move the Pod to another node." | False. If the Pod strictly requires the label `hardware=highmem`, and no other node has that label, the Pod will stay Pending forever. Kubernetes will not relax the rules to keep your app online. |

## ASCII Diagrams

Mental Model: Pod Anti-Affinity is a "No Roommates" rule. The Pod says, "I refuse to live in a house (Node) where another one of me is already living."

```
[ Cluster Topology ]

[ Node A (worker) ]  [ Node B (worker2) ]  [ Node C (control-plane) ]

[ Deployment: web-app (replicas: 3) ]
Rule: PodAntiAffinity (Hard Requirement: topologyKey=hostname)

1. Pod 1 scheduled -> lands on Node A.
2. Pod 2 scheduled -> Node A is rejected (Pod 1 is there). Lands on Node B.
3. Pod 3 scheduled -> Node A rejected, Node B rejected. Node C is tainted.
   -> RESULT: Pod 3 stays PENDING.
```

## Hands-on

### Objective

Create a Deployment with 3 replicas and a strict Pod Anti-Affinity rule. Watch it spread across the 2 worker nodes, and watch the 3rd replica freeze.

### Step 1: Create the HA Deployment

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

### Step 2: Observe the Spread

Wait about 15 seconds, then run:

```bash
kubectl get pods -l app=web -o wide
```

Notice where the Pods landed. One should be on `kind-worker`, and one should be on `kind-worker2`. They were forced to spread out.

### Step 3: Investigate the Failure

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

(Answer: 1. 2 Running, 1 Pending. 2. `0/3 nodes are available: 1 node(s) had untolerated taints, 2 node(s) didn't match pod anti-affinity rules`. 3. Pod 1 went to worker. Pod 2 went to worker2. Pod 3 arrived. Worker and worker2 were rejected because they already have an `app=web` pod. Control-plane was rejected because it has a `NoSchedule` taint. Pod 3 has nowhere to go).

### Step 4: Try Preferred Anti-Affinity

Now replace the Deployment with a preferred version:

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

### Step 5: Test Node Affinity

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

Label a node:

```bash
kubectl label nodes kind-worker disktype=ssd
```

Check the pods again:

```bash
kubectl get pods -l app=ssd -o wide
```

Now they should be Running on `kind-worker`.

### Step 6: Cleanup

```bash
kubectl delete deployment ha-web
kubectl delete deployment ssd-app
kubectl label nodes kind-worker disktype-
```

## Commands

```bash
# Check pods with node assignment
kubectl get pods -l app=web -o wide

# Describe pod to see scheduling events
kubectl describe pod -l app=web | grep -A 5 Events

# Label a node
kubectl label nodes <node> <key>=<val>

# Remove a label from a node
kubectl label nodes <node> <key>-

# Show all labels on all nodes
kubectl get nodes --show-labels

# Add a taint to a node
kubectl taint nodes <node> <key>=<val>:Effect

# Remove a taint from a node
kubectl taint nodes <node> <key>=<val>:Effect-
```

## YAML Explanation

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

### Field-by-Field Explanation

- `affinity.podAntiAffinity`: We are setting a rule about other Pods.
- `requiredDuringScheduling...`: This is a HARD rule. It must be met, or the Pod stays Pending.
- `labelSelector`: We are looking for other Pods with the label `app: web` (which is the label this deployment uses).
- `topologyKey: kubernetes.io/hostname`: The rule applies per node. "Do not put two `app=web` pods on the same hostname (node)."

## Production Notes

- **Use `topology.kubernetes.io/zone` for true HA:** Spreading Pods across different nodes in the same AWS Availability Zone protects against node failure. Spreading them across different AZs protects against entire datacenter outages.
- **Don't over-constrain:** If you use strict required anti-affinity rules and your cluster only has 2 worker nodes, you can never scale your Deployment beyond 2 replicas. The 3rd replica will stay Pending.
- **Use preferred for safety:** Unless you have strict licensing or data residency rules, preferred anti-affinity is often safer than required. It tries to spread the Pods, but if a node fails, it still allows the Pod to be scheduled on an existing node rather than leaving the app capacity-reduced.

### When to Use / When NOT to Use

**Use Node Affinity when:**

- You need to run a Pod on a node with a specific hardware (GPU, SSD).
- You want to dedicate nodes to specific teams or applications.
- You want to keep the Control Plane safe from user workloads.

**Avoid strict rules when:**

- Your app is stateless and can run anywhere. Over-constraining makes the cluster fragile. If a node fails, the Pod can't move elsewhere.

### Performance and Security Considerations

**Performance:** In massive clusters (1,000+ nodes), Node Affinity with complex preferred rules can take CPU time to score all nodes. Pod Anti-Affinity is even more expensive because the Scheduler must evaluate all running Pods against the new Pod's rules.

**Security:** Do not let developers taint nodes. Taints are an admin-level operation. If a developer could remove a taint, they could run their Pod on the Control Plane and potentially compromise the cluster.

## Best Practices

- Use `topology.kubernetes.io/zone` for multi-AZ HA.
- Don't over-constrain with required rules.
- Use preferred anti-affinity for safety.
- Label nodes consistently for affinity rules.
- Test scheduling rules in a staging environment first.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Using required rules without enough nodes | Requesting 5 replicas with unique node anti-affinity, but only having 3 worker nodes | Calculate: replicas <= worker nodes |
| Misspelling topologyKey | Using `kubernetes.io/hostname` vs `kubernetes.io/hostname` | Double-check the exact label name |
| Confusing Affinity and Anti-Affinity | Affinity pulls Pods together, Anti-Affinity pushes them apart | Remember: Affinity = attraction, Anti-Affinity = repulsion |
| Over-constraining | Too many required rules | Use preferred rules when possible |

## Troubleshooting

**Symptom: Pods stuck in Pending**

Cause: Scheduling rules cannot be satisfied.

```bash
kubectl describe pod <pod-name> | grep -A 5 Events
```

Look for `FailedScheduling` events. They will say if it was due to taints, anti-affinity, or insufficient resources.

Fix: Relax the rules (use preferred instead of required) or add more nodes.

**Symptom: Pods not spreading as expected**

Cause: topologyKey doesn't match node labels.

```bash
kubectl get nodes --show-labels | grep <topology-key>
```

Fix: Verify the topologyKey exists on your nodes.

**Symptom: Node Affinity pulling Pods to wrong nodes**

Cause: Node labels don't match the affinity rule.

```bash
kubectl get nodes --show-labels
```

Fix: Add or correct the node labels.

## Interview Questions

**Q: What is the difference between Node Affinity and Pod Anti-Affinity?**

A: Node Affinity pulls a Pod to a specific Node based on Node labels. Pod Anti-Affinity pushes a Pod away from other Pods based on Pod labels.

**Q: What is the difference between required and preferred scheduling rules?**

A: Required is a hard rule - if it can't be met, the Pod stays Pending. Preferred is a soft rule - the scheduler tries to meet it, but schedules the Pod anyway if it can't.

**Q: You have 3 worker nodes. 2 are standard, 1 has GPUs. How do you ensure only ML pods use the GPU node?**

A: I would taint the GPU node: `kubectl taint nodes gpu-node dedicated=gpu:NoSchedule`. Then, I would add a toleration to the ML Pods for `dedicated=gpu`. Normal web pods won't have the toleration, so the scheduler will repel them from the GPU node.

**Q: If a Pod is stuck in Pending, what is the first command you run?**

A: `kubectl describe pod <name>`. Look at the Events section for `FailedScheduling` messages.

**Q: True or False: If a Pod has a nodeSelector for a label that doesn't exist, it will run on a random node.**

A: False. It stays Pending.

**Q: True or False: Taints and Tolerations are the same as Network Policies.**

A: False. Taints are for scheduling, Network Policies are for traffic.

## Scenario Questions

**Scenario 1:** You deploy a Deployment with 3 replicas and a strict Pod Anti-Affinity rule. Only 2 Pods are Running. The 3rd is Pending. What do you do?

A: The cluster only has 2 worker nodes. The anti-affinity rule prevents 2 Pods from being on the same node, but the 3rd Pod has nowhere to go. Solutions: 1) Add a 3rd worker node, 2) Switch to preferred anti-affinity, 3) Reduce replicas to 2.

**Scenario 2:** You need to ensure all database Pods run on nodes with SSDs, and no two database Pods run on the same node. How do you combine these rules?

A: Use Node Affinity with `requiredDuringScheduling` to pull database Pods to SSD nodes, AND Pod Anti-Affinity with `requiredDuringScheduling` to spread them across nodes.

**Scenario 3 (Mini Project - The Dedicated Node):**

Taint one of your worker nodes: `kubectl taint nodes kind-worker dedicated=special:NoSchedule`. Deploy a Pod without a toleration. Verify it lands on the other worker node. Deploy a second Pod with a toleration for `dedicated=special`. Verify it lands on the tainted node. Clean up the taint when done: `kubectl taint nodes kind-worker dedicated=special:NoSchedule-`.

## Quiz

1. What is the upgraded version of nodeSelector?
   - A. Taint
   - B. Toleration
   - C. Node Affinity
   - D. Pod Anti-Affinity

2. What does `requiredDuringSchedulingIgnoredDuringExecution` mean?
   - A. A soft rule that can be ignored
   - B. A hard rule that must be met or the Pod stays Pending
   - C. A rule that applies only during creation
   - D. A rule that applies only during deletion

3. Which topologyKey would spread Pods across different availability zones?
   - A. `kubernetes.io/hostname`
   - B. `topology.kubernetes.io/zone`
   - C. `kubernetes.io/os`
   - D. `kubernetes.io/arch`

4. What happens if you request 5 replicas with unique node anti-affinity but only have 3 worker nodes?
   - A. All 5 run on 3 nodes
   - B. 3 run, 2 stay Pending
   - C. All 5 stay Pending
   - D. The scheduler ignores the rule

5. What command shows why a Pod is stuck in Pending?
   - A. `kubectl get pod <name>`
   - B. `kubectl logs <name>`
   - C. `kubectl describe pod <name>`
   - D. `kubectl exec <name>`

Answers: 1-C, 2-B, 3-B, 4-B, 5-C.

## Revision

One-minute revision:

- Node Affinity = Pod wants specific nodes (Pull).
- Pod Anti-Affinity = Pod refuses nodes with other Pods (Push).
- Required = Hard rule, Pod stays Pending if not met.
- Preferred = Soft rule, Scheduler tries but will ignore.
- topologyKey = The domain boundary (hostname = node, zone = AZ).

Memory trick:

- **Node Affinity:** A VIP pass. "I only enter rooms labeled VIP."
- **Pod Anti-Affinity:** A "No Roommates" rule. "I refuse to live where another me lives."
- **Taint:** A "Keep Out" sign on a node's door.
- **Toleration:** A key that lets you ignore the "Keep Out" sign.

Key facts:

- Node Affinity pulls Pods to nodes.
- Pod Anti-Affinity pushes Pods away from other Pods.
- Required rules can cause Pending.
- Preferred rules are best-effort.
- topologyKey defines the boundary.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl label nodes <node> <key>=<val>` | Adds a label to a node |
| `kubectl label nodes <node> <key>-` | Removes a label from a node |
| `kubectl get nodes --show-labels` | Shows all labels on all nodes |
| `kubectl taint nodes <node> <key>=<val>:Effect` | Adds a taint to a node |
| `kubectl describe pod <name>` | Look for FailedScheduling events |

## References

- [Kubernetes Documentation: Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Kubernetes Documentation: Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Kubernetes Documentation: Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)

## Related Lessons

- [Lesson 3 - Controlling Where Pods Run (Scheduling and Taints)](lesson-03-worker-node-architecture.md) - basic scheduling and taints.
- [Lesson 4 - Pod Priority and Preemption](lesson-04-pod-priority-and-preemption.md) - advanced scheduling concepts.
- [Lesson 35 - Building a 3-Tier Web Application](../12-production/lesson-35-building-a-3-tier-web-application.md) - applying HA to real applications.

## Coming Next

Now that you understand how to spread Pods across nodes for high availability, the next lesson covers the Kubernetes API and Controllers — the brain behind all automation in the cluster.
