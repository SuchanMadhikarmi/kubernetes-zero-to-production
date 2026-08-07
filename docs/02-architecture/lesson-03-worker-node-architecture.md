---
title: Lesson 3 - Controlling Where Pods Run (Scheduling and Taints)
module: 02 Architecture
lesson: 3
status: Complete
tags: [kubernetes, scheduling, kube-scheduler, node-selector, taints, tolerations, labels, affinity]
---

# Lesson 3 - Controlling Where Pods Run (Scheduling and Taints)

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

- Explain how the kube-scheduler decides where to place a Pod.
- Use Node Selectors and Labels to force Pods onto specific nodes.
- Describe what Taints and Tolerations are and how they work together.
- Debug a Pod stuck in Pending due to scheduling failures.

## Prerequisites

- Completion of Lessons 1 through 6.
- A running Kubernetes cluster with multiple nodes (see setup instructions below).
- kubectl installed and configured.

### Setting Up a Multi-Node kind Cluster

```bash
kind delete cluster

cat <<EOF > kind-multi.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

kind create cluster --config kind-multi.yaml
```

Verify you have 3 nodes:

```bash
kubectl get nodes
```

## Real-world Motivation

### The Expensive Mistake

Imagine you purchase a specialized server with a massive NVIDIA GPU for Machine Learning training. It costs $10,000 a month to run. You deploy your ML training Pod, but you also deploy a simple Nginx web server. The kube-scheduler sees the web server Pod first and places it on the expensive GPU node because it has the most free CPU. You are now wasting $10,000 a month to host a simple web page.

### The Control Plane Crash

If you don't configure scheduling properly, user applications might land on your Control Plane nodes. If a user app consumes 100% of the CPU on a Control Plane, the API Server becomes unresponsive, and the entire cluster goes dark.

### Why This Exists

Kubernetes needed a way to enforce architectural and hardware constraints.

- **Node Selectors/Affinity:** Allow developers to say, "I only want to run on nodes with this specific label" (Pull).
- **Taints:** Allow cluster administrators to say, "Keep all normal Pods away from this node" (Push).
- **Tolerations:** Allow specific Pods to ignore a node's Taint.

### Real Company Examples

**Waymo (Autonomous Vehicles):** Waymo has node pools with massive GPUs for processing ML training models. Those nodes are tainted `nvidia.com/gpu=true:NoSchedule`. Only the ML training Pods have the toleration to run there. This prevents a simple web frontend Pod from accidentally landing on a $10,000/month GPU node and wasting resources.

## Core Concepts

### Explain Like I'm 12

Imagine an airplane. The flight attendant (Scheduler) looks at passengers (Pods) and assigns them seats (Nodes).

- If you have a standard ticket, you can sit anywhere with an empty seat.
- If you have a VIP card (`nodeSelector`), you say, "I will ONLY sit in First Class." If First Class is full, you wait at the gate forever (Pending).
- Some seats have a "Reserved" sign on them (Taint). Normal passengers can't sit there. But if you have a special VIP pass (Toleration), you are allowed to sit in that reserved seat.

### Explain Like I'm a Junior Engineer

By default, the Kubernetes Scheduler spreads Pods across all available nodes that have enough CPU and memory.

- **Node Selectors** are rules written in the Pod YAML that tell the scheduler which nodes are acceptable.
- **Taints** are a mark put on a Node that says "Keep Pods away from me."
- **Tolerations** are rules written in the Pod YAML that say "I can tolerate that specific Taint, so I am allowed to run there."

### Explain Technically

The kube-scheduler runs a two-phase algorithm:

1. **Filtering:** It filters out nodes that don't meet the Pod's requirements (not enough CPU, missing NodeSelector labels, have Taints the Pod doesn't tolerate).
2. **Scoring:** It ranks the remaining nodes based on priorities (e.g., least requested resources, affinity rules). It picks the highest score and binds the Pod to that node.

### How Kubernetes Implements It Internally

When you create a Pod, it starts in the Pending state. The Scheduler watches the API Server for Pods without a `nodeName`. It runs the filter/score algorithm, then sends a POST request to the API Server to update the Pod's `spec.nodeName` field. Once `nodeName` is set, the kubelet on that node notices the Pod and starts the containers.

### Why Kubernetes Was Designed That Way

The two-phase approach (filter then score) allows Kubernetes to be both precise and flexible. Filtering ensures hard constraints are met (e.g., "must have GPU label"). Scoring allows soft preferences (e.g., "prefer the node with the least load"). This separation keeps the scheduler fast and extensible.

## Architecture

```
[ New Pod arrives (Pending) ]
      |
      v
[ kube-scheduler ]
      |
      +---> 1. Filter: Remove nodes that don't fit.
      |       - Not enough CPU/RAM?
      |       - Missing NodeSelector label?
      |       - Has a Taint the Pod doesn't tolerate?
      |
      +---> 2. Score: Rank the remaining nodes.
      |       - Least requested resources?
      |       - Node Affinity preferences?
      |
      v
[ API Server ] -> Updates Pod with spec.nodeName -> [ Kubelet on chosen Node ]
```

### Terminology

| Term | Definition |
|------|------------|
| kube-scheduler | The control plane component responsible for assigning Pods to Nodes. |
| nodeSelector | A simple field in Pod spec requiring a node to have specific labels. |
| Taint | A property applied to a node to repel pods. |
| Toleration | A property applied to a pod allowing it to tolerate a node's taint. |
| Node Affinity | A more expressive version of nodeSelector supporting In, NotIn, Exists operators. |
| Pending | The state of a Pod when it has been created but cannot be scheduled to a node. |
| FailedScheduling | An event written by the scheduler when no suitable node is found. |

### How It Works Internally

1. When you create a Pod, it starts in the Pending state.
2. The Scheduler watches the API Server for Pods without a `nodeName`.
3. It runs the filter/score algorithm.
4. If a valid node is found, it sends a POST request to the API Server to set `spec.nodeName`.
5. The kubelet on that node notices the Pod and starts the containers.
6. If no valid node is found, the Pod stays Pending and the Scheduler writes a `FailedScheduling` event.

### Step-by-Step Workflow

1. User creates a Pod with `nodeSelector: disktype: ssd`.
2. API Server saves the Pod to etcd.
3. kube-scheduler notices the Pending Pod.
4. Scheduler Filter Phase: Looks at Node 1 (no label), Node 2 (label `disktype=hdd`), Node 3 (label `disktype=ssd`).
5. Nodes 1 and 2 are filtered out. Node 3 passes.
6. Scheduler binds the Pod to Node 3.
7. kubelet on Node 3 starts the container.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | Pod is created. Scheduler evaluates constraints. |
| Scheduling | If a valid node is found, Pod is bound. If not, Pod remains Pending. |
| Node Label Change | If a node's label changes, existing Pods are NOT moved. Scheduling is only evaluated at creation time (unless a descheduler is used). |

### Node Selector vs Taints vs Affinity

| Feature | Node Selector | Node Affinity | Taints and Tolerations |
|---------|---------------|---------------|------------------------|
| Mechanism | Pull (Pod wants node) | Pull (Pod wants node) | Push (Node repels Pod) |
| Flexibility | Simple key-value | Supports In, NotIn, Exists | Based on key/value/effect |
| Hard/Soft | Always Hard | Can be Hard (required) or Soft (preferred) | Always Hard (unless NoExecute used) |
| Use Case | Simple targeting | Complex routing rules | Dedicated nodes |

### Common Myths

| Myth | Fact |
|------|------|
| "If I use a NodeSelector and the node dies, Kubernetes will move the Pod to another node." | False. If the Pod strictly requires the label `hardware=highmem`, and no other node has that label, the Pod will stay Pending forever. Kubernetes will not relax the rules to keep your app online. |
| "Taints and Tolerations are the same as Network Policies." | False. Taints are for scheduling, Network Policies are for traffic. |
| "The scheduler considers all nodes every time." | The scheduler filters first, then scores. This keeps it fast even in large clusters. |

## ASCII Diagrams

Mental Model:

- `nodeSelector` is a Magnet: It pulls your Pod toward a specific node.
- Taint is a Repellent: It pushes Pods away from a node.
- Toleration is Bug Spray: It negates the repellent, allowing the Pod to land there.

```
[ Node A (Labels: disk=ssd) ]    [ Node B (Taint: gpu=true:NoSchedule) ]
       |                                    |
       v (Pod has nodeSelector: disk=ssd)   v (Pod has Toleration for gpu=true)
[ Pod 1 Lands Here ]                 [ Pod 2 Lands Here ]

[ Pod 3 (No toleration) ] ---> Scheduler refuses to put Pod 3 on Node B.
```

### Scheduler Flow

```
[ Pod: Pending ]
      |
      v
[ kube-scheduler: Filter Phase ]
      | (Remove nodes with insufficient resources)
      | (Remove nodes missing nodeSelector labels)
      | (Remove nodes with untolerated Taints)
      v
[ kube-scheduler: Score Phase ]
      | (Rank remaining nodes by least requested resources)
      | (Apply affinity preferences)
      v
[ Bind Pod to highest-scored node ]
      |
      v
[ kubelet on chosen node starts containers ]
```

## Hands-on

### Objective

Create a multi-node cluster, label a node, force a Pod to schedule there, and then intentionally fail scheduling.

### Step 1: Create Multi-Node Kind Cluster

```bash
kind delete cluster

cat <<EOF > kind-multi.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

kind create cluster --config kind-multi.yaml
```

```bash
kubectl get nodes
```

### Step 2: Label a Node

```bash
kubectl label nodes kind-worker2 hardware=highmem
kubectl get nodes --show-labels
```

### Step 3: Schedule a Pod Using NodeSelector

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: memory-app
spec:
  nodeSelector:
    hardware: highmem
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "sleep 3600"]
EOF
```

```bash
kubectl get pod memory-app -o wide
```

Expected: The NODE column shows `kind-worker2`.

### Step 4: Test Taints and Tolerations

Taint the GPU node:

```bash
kubectl taint nodes kind-worker2 gpu=true:NoSchedule
```

Deploy a Pod without toleration:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: no-gpu-app
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "sleep 3600"]
EOF
```

```bash
kubectl get pod no-gpu-app -o wide
```

Expected: The Pod lands on `kind-worker` (not `kind-worker2`).

Deploy a Pod with toleration:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-app
spec:
  tolerations:
  - key: "gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "sleep 3600"]
EOF
```

```bash
kubectl get pod gpu-app -o wide
```

Expected: The Pod lands on `kind-worker2` (the tainted node).

### Step 5: Debug a Broken Schedule

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: broken-schedule
spec:
  nodeSelector:
    disktype: nvme
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "sleep 3600"]
EOF
```

```bash
kubectl get pod broken-schedule
kubectl describe pod broken-schedule
```

The Pod stays Pending. The Events section shows why.

### Step 6: Cleanup

```bash
kubectl delete pod memory-app no-gpu-app gpu-app broken-schedule
kubectl label nodes kind-worker2 hardware-
kubectl taint nodes kind-worker2 gpu=true:NoSchedule-
kind delete cluster --name multi 2>/dev/null; kind delete cluster
```

## Commands

```bash
# Add a label to a node
kubectl label nodes <node> <key>=<val>

# Remove a label from a node
kubectl label nodes <node> <key>-

# Show all labels on all nodes
kubectl get nodes --show-labels

# Add a taint to a node
kubectl taint nodes <node> <key>=<val>:NoSchedule

# Remove a taint from a node
kubectl taint nodes <node> <key>=<val>:NoSchedule-

# Check Pod scheduling events
kubectl describe pod <name> | grep -A 5 Events

# Check node taints
kubectl describe node <node> | grep -A 5 Taints
```

## YAML Explanation

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: memory-app
spec:
  nodeSelector:
    hardware: highmem
  tolerations:
  - key: "gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "sleep 3600"]
```

### Field-by-Field Explanation

- `spec.nodeSelector`: A simple key-value pair. The scheduler will only place this Pod on nodes with the matching label.
- `spec.tolerations`: A list of taints this Pod can tolerate. If a node has a matching taint, the Pod is allowed to be scheduled there.
- `tolerations.key`: The taint key to match.
- `tolerations.operator`: `Equal` means the value must match exactly. `Exists` means only the key needs to exist.
- `tolerations.value`: The taint value to match.
- `tolerations.effect`: The taint effect to match (`NoSchedule`, `PreferNoSchedule`, `NoExecute`).

## Production Notes

- **Don't over-constrain.** If you use strict nodeSelector rules and the specific node fails, your Pod will stay Pending forever instead of failing over to another node.
- **Use Taints for dedicated nodes.** Instead of relying on developers to use nodeSelectors to target GPU nodes, Taint the GPU nodes. This prevents developers who forget to add a selector from accidentally landing on the expensive node.
- **Taint the Control Plane.** Control Plane nodes are automatically tainted (`node-role.kubernetes.io/control-plane:NoSchedule`) to prevent user apps from running on them. Never remove this taint in production.
- **Document your Taints.** New engineers deploy a Pod, it stays Pending, and they have no idea why because they didn't know a node was tainted.
- **Use Node Affinity for complex rules.** When nodeSelector is too simple, use Node Affinity with `requiredDuringSchedulingIgnoredDuringExecution` or `preferredDuringSchedulingIgnoredDuringExecution`.

### When to Use / When NOT to Use

**Use Scheduling Rules when:**

- You need to run a Pod on a node with a specific hardware (GPU, SSD).
- You want to dedicate nodes to specific teams or applications.
- You want to keep the Control Plane safe from user workloads.

**Do NOT use strict rules when:**

- Your app is stateless and can run anywhere. Over-constraining makes the cluster fragile. If a node fails, the Pod can't move elsewhere.

### Performance and Security Considerations

**Performance:** Scheduling is a fast operation, but in massive clusters (1,000+ nodes), Node Affinity with complex preferred rules can take CPU time to score all nodes.

**Security:** Do not let developers taint nodes. Taints are an admin-level operation. If a developer could remove a taint, they could run their Pod on the Control Plane and potentially compromise the cluster.

## Best Practices

- Use Taints for dedicated nodes (GPU, monitoring, etc.).
- Document all Taints and Labels in your cluster.
- Don't over-constrain Pods with strict nodeSelectors.
- Keep the Control Plane tainted in production.
- Use Node Affinity for complex scheduling rules.
- Test scheduling rules in a dev cluster before applying to production.
- Monitor for Pending Pods with alerts on `FailedScheduling` events.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Using Taints without documenting them | New engineers don't know about the taint | Document all Taints in cluster runbooks |
| Misspelled Labels | `disktype` vs `disk-type` | Double-check labels with `kubectl get nodes --show-labels` |
| Over-constraining with nodeSelector | Pod can't failover if node dies | Use soft constraints (Node Affinity preferred) for stateless apps |
| Removing Control Plane taint | Trying to run user apps on CP | Never remove the control-plane taint in production |

## Troubleshooting

**Symptom: Pod stuck in Pending**

Cause: No node matches the Pod's scheduling constraints.

```bash
kubectl describe pod <pod-name> | grep -A 10 Events
```

Look for `FailedScheduling` events. They will explain exactly why (insufficient CPU, taints, selector mismatches).

**Symptom: Pod lands on wrong node**

Cause: Labels or Taints are not configured correctly.

```bash
kubectl get nodes --show-labels
kubectl describe node <node> | grep -A 5 Taints
```

Fix: Verify labels and taints match your scheduling rules.

**Symptom: Taint removed unexpectedly**

Cause: Another engineer removed the taint.

```bash
kubectl describe node <node> | grep -A 5 Taints
```

Fix: Re-apply the taint and document the change.

## Interview Questions

**Q: What component decides which node a Pod runs on?**

A: The kube-scheduler.

**Q: What is the difference between a Taint and a NodeSelector?**

A: A Taint repels Pods from a Node (Push). A NodeSelector pulls a Pod to a specific Node (Pull).

**Q: Why are Control Plane nodes tainted by default?**

A: To prevent user applications from consuming resources on the control plane, which could crash the cluster's API server or etcd.

**Q: If a Pod is stuck in Pending, what is the first command you run to debug it?**

A: `kubectl describe pod <name>`. Look at the Events section for `FailedScheduling` messages, which will say if it was due to insufficient CPU, taints, or selector mismatches.

**Q: You have 3 worker nodes. 2 are standard, 1 has GPUs. How do you ensure only ML pods use the GPU node, and normal web pods never do?**

A: I would Taint the GPU node: `kubectl taint nodes gpu-node dedicated=gpu:NoSchedule`. Then, I would add a toleration to the ML Pods for `dedicated=gpu`. Normal web pods won't have the toleration, so the scheduler will repel them from the GPU node.

**Q: If a Pod has a nodeSelector for a label that doesn't exist, what happens?**

A: The Pod stays Pending forever. Kubernetes will not relax the rules to keep your app online.

## Scenario Questions

**Scenario 1:** You have a Deployment with 3 replicas and a nodeSelector for `disk=ssd`. One of the 3 nodes with the SSD label goes down. What happens to the Pods?

A: The Pods on the failed node become Pending. The other 2 Pods remain running. The failed Pods cannot move to other nodes because those nodes don't have the `disk=ssd` label. This is why over-constraining is dangerous.

**Scenario 2:** You need to drain a node for maintenance. How do you prevent new Pods from being scheduled there?

A: Add a taint: `kubectl taint nodes <node> maintenance=true:NoSchedule`. Existing Pods stay running. New Pods without a toleration won't be scheduled there. After maintenance, remove the taint.

**Scenario 3 (Mini Project - The Dedicated Node):**

Taint one of your worker nodes: `kubectl taint nodes kind-worker dedicated=special:NoSchedule`. Deploy a Pod without a toleration. Verify it lands on the other worker node. Deploy a second Pod with a toleration for `dedicated=special`. Verify it lands on the tainted node. Clean up the taint when done.

## Quiz

1. What does `nodeSelector` do?
   - A. Repels Pods from a node
   - B. Pulls a Pod to a node with a matching label
   - C. Limits CPU usage
   - D. Creates a new node

2. What is the effect of a Taint with `NoSchedule`?
   - A. Existing Pods are evicted
   - B. New Pods without toleration are not scheduled
   - C. The node is shut down
   - D. The node is cordoned

3. What happens if a Pod has a nodeSelector for a label that doesn't exist?
   - A. Pod runs on a random node
   - B. Pod stays Pending
   - C. Pod runs on the control plane
   - D. Pod fails with Error

4. How do you remove a taint from a node?
   - A. `kubectl taint nodes <node> <key>-`
   - B. `kubectl untaint nodes <node> <key>`
   - C. `kubectl delete taint <node> <key>`
   - D. `kubectl label nodes <node> <key>-`

5. Why are Control Plane nodes tainted by default?
   - A. To save resources
   - B. To prevent user apps from running on them
   - C. To improve performance
   - D. To enable monitoring

Answers: 1-B, 2-B, 3-B, 4-A, 5-B.

## Revision

One-minute revision:

- The kube-scheduler decides which node a Pod runs on using Filtering and Scoring.
- `nodeSelector` forces a Pod to only run on nodes with specific labels.
- Taints repel Pods from a Node.
- Tolerations allow Pods to ignore Taints.
- If a Pod cannot be scheduled, it stays in Pending and the Scheduler writes a `FailedScheduling` event explaining exactly why.

Memory trick:

- `nodeSelector`: A VIP pass. "I only enter rooms labeled VIP."
- Taint: A "Keep Out" sign on a node's door.
- Toleration: A key that lets you ignore the "Keep Out" sign.

Key facts:

- `nodeSelector` = Pod demands a specific label.
- Taint = Node says "Keep out".
- Toleration = Pod says "I can go in".
- Failed Scheduling = Pod stays Pending.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl label nodes <node> <key>=<val>` | Adds a label to a node |
| `kubectl label nodes <node> <key>-` | Removes a label from a node |
| `kubectl get nodes --show-labels` | Shows all labels on all nodes |
| `kubectl taint nodes <node> <key>=<val>:NoSchedule` | Adds a taint to a node |
| `kubectl taint nodes <node> <key>=<val>:NoSchedule-` | Removes a taint from a node |
| `kubectl describe pod <name>` | Look for FailedScheduling events |

## References

- [Kubernetes Documentation: Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Kubernetes Documentation: Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Kubernetes Documentation: Node Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#node-affinity)
- [Kubernetes Documentation: kube-scheduler](https://kubernetes.io/docs/reference/scheduling/kube-scheduler/)
- [Kubernetes Documentation: Descheduler](https://github.com/kubernetes-sigs/descheduler)

## Related Lessons

- [Lesson 1 - The Anatomy of a Container](../01-fundamentals/lesson-01-anatomy-of-a-container.md) - containers, namespaces, and cgroups.
- [Module 02 Architecture Index](README.md) - overview of control plane and worker node components.
- [Lesson 6 - Pods, ReplicaSets, and Deployments](../03-workloads/lesson-06-pods-replicasets-and-deployments.md) - how Pods work.
- [Lesson 8 - StatefulSets](../03-workloads/lesson-08-statefulsets.md) - for stateful workloads that need stable identity.
- [Module 12 - Production](../12-production/README.md) - production hardening and capacity planning.

## Coming Next

Now that you understand how the scheduler places Pods, the next lesson covers the Kubernetes API and Controllers, explaining how the control plane watches for changes and reconciles desired state.
