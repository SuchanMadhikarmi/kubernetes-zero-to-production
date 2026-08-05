---
title: Lesson 14 - DaemonSets
module: 03 Workloads
lesson: 14
status: Complete
tags: [kubernetes, daemonsets, node-local, logging, monitoring, infrastructure]
---

# Lesson 14 - DaemonSets

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

- Explain what a DaemonSet is and how it differs from a Deployment.
- Describe how the DaemonSetController automatically reacts to node changes.
- Explain why DaemonSets bypass the standard kube-scheduler.
- Deploy a logging agent across all worker nodes.

## Prerequisites

- Completion of Lessons 1 through 10.
- A running Kubernetes cluster with multiple nodes (see [Lesson 07](../02-architecture/lesson-07-worker-node-architecture.md) for multi-node kind setup).
- kubectl installed and configured.

## Real-world Motivation

### The Blind Node

Imagine you have a 10-node cluster. You deploy a log collector (like Fluent Bit) using a standard Deployment with 3 replicas. The Scheduler places those 3 Pods on Node 1, Node 2, and Node 3. Suddenly, Node 4 crashes. Because there is no log collector on Node 4, the critical error logs that caused the crash are lost forever. You are flying blind.

### Why This Exists

Kubernetes needed a way to guarantee that a copy of a Pod runs on every single node (or a subset of nodes based on labels/taints). Whether you have 3 nodes or 1,000 nodes, a DaemonSet ensures exactly one Pod per node. When you scale your cluster by adding a new node, the DaemonSet instantly deploys a Pod to it without human intervention. This is essential for node-level infrastructure: logging, monitoring, and networking.

### Real Company Examples

**Datadog:** Datadog provides a monitoring agent that is deployed to customer clusters as a DaemonSet. When a customer adds a new AWS EC2 node to their EKS cluster, the Datadog DaemonSet instantly deploys an agent to that node, ensuring there is never a gap in metric collection or log forwarding.

## Core Concepts

### Explain Like I'm 12

Imagine a school with several classrooms (Nodes). The principal (DaemonSet) wants every classroom to have exactly one security camera (Pod). If a new classroom is built tomorrow, the principal automatically installs a camera in that new room too.

### Explain Like I'm a Junior Engineer

A DaemonSet is a controller that ensures a Pod runs on every node in the cluster. You don't say "I want 3 replicas." You just create the DaemonSet, and Kubernetes figures out how many nodes exist and puts one Pod on each. If a node is deleted, the Pod is garbage collected.

### Explain Technically

- The `DaemonSetController` runs in the `kube-controller-manager`. It continuously lists all Nodes in the cluster.
- For every Node that matches the DaemonSet's `nodeSelector` (and whose taints are tolerated by the DaemonSet), it checks if a Pod already exists. If not, it creates a Pod.
- Crucially, it bypasses the kube-scheduler by directly setting the `spec.nodeName` field on the Pod manifest. This guarantees placement and prevents the Scheduler from rejecting it due to "insufficient resources."

### How Kubernetes Implements It Internally

Because the DaemonSetController directly sets `spec.nodeName`, the Pod skips the scheduling queue. The kubelet on the target node immediately sees the Pod assigned to it and starts the container. This is a critical design choice: you always want your logging agent to run on a node, even if the node is 99% full. If it went through the Scheduler, the Scheduler might say "Node is full, reject Pod," leaving you with no logs.

### Why Kubernetes Was Designed That Way

DaemonSets bypass the Scheduler intentionally. Infrastructure pods (logging, monitoring, networking) must run on every node regardless of resource availability. The Scheduler's job is to find the "best" node, but for DaemonSets, there is only one option: every node.

## Architecture

```
[ DaemonSet: logging-agent ]
      |
      +---> [ Node 1 ] ---> [ Pod: logging-agent-xyz (Running) ]
      |
      +---> [ Node 2 ] ---> [ Pod: logging-agent-abc (Running) ]

      (A new node is added to the cluster!)

      |
      +---> [ Node 3 ] ---> [ Pod: logging-agent-999 (Auto-created) ]
```

### Terminology

| Term | Definition |
|------|------------|
| DaemonSet | A workload controller that ensures a copy of a Pod runs on all (or some) nodes. |
| Node-Local | Software that operates on a specific physical server rather than globally across the cluster. |
| spec.nodeName | A field in the Pod spec that forces the Pod to run on a specific node. |

### How It Works Internally

1. You create a DaemonSet YAML.
2. The API Server saves it to etcd.
3. The DaemonSetController notices the new object.
4. It queries the API Server for a list of all Nodes.
5. It filters out nodes that don't match the `nodeSelector` or whose taints are not tolerated.
6. For the remaining nodes, it checks if a Pod with the DaemonSet's label already exists.
7. If a node is missing a Pod, it creates a Pod manifest and hardcodes `spec.nodeName: <node-name>`.
8. The kubelet on that node sees the Pod and starts the container.

### Step-by-Step Workflow

1. Developer creates a DaemonSet for a log collector.
2. Controller iterates through nodes.
3. Creates 1 Pod per node.
4. Developer adds a new worker node to the cluster.
5. Controller detects the new node on its next loop.
6. Automatically creates a new Pod on the new node.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | Pods are created on all matching nodes. |
| Node Addition | A new node is added. A Pod is instantly created on it. |
| Node Deletion | A node is removed. The Pod running on it is garbage collected (deleted). |
| Update | If the Pod template is changed, it performs a rolling update, updating Pods on each node one by one. |

### Deployment vs DaemonSet

| Feature | Deployment | DaemonSet |
|---------|------------|-----------|
| Replica Count | Explicitly defined (`replicas: 3`) | Implicitly defined by Node count |
| Placement | Decided by kube-scheduler | Decided by DaemonSetController (bypasses scheduler) |
| Node Scale-Up | No effect (replicas stay 3) | Automatically adds a new Pod |
| Use Case | Web servers, APIs | Logging, Monitoring, Networking |

### Common Myths

| Myth | Fact |
|------|------|
| "DaemonSets use the kube-scheduler." | False. The DaemonSetController directly sets the `spec.nodeName` field. It bypasses the Scheduler entirely. This is critical because you want infrastructure pods to land on a node even if the Scheduler thinks the node is "full." |
| "DaemonSets run on every node including control plane." | False. Control plane nodes are tainted by default. DaemonSets skip them unless you add a toleration. |

## ASCII Diagrams

Mental Model: A DaemonSet is a Roomba robot vacuum. You don't tell it how many rooms to clean. It automatically goes into every single room in the house. If you build a new room, it finds it and cleans it.

```
[ Cluster Nodes ]
[ Node 1 (worker) ]      [ Node 2 (worker2) ]    [ Node 3 (control-plane, tainted) ]
       |                         |                         |
       v                         v                         v
[ Pod: log-agent ]       [ Pod: log-agent ]       [ X No Pod (Taint not tolerated) ]

(DaemonSet Controller loop)
"Node 1 has 1 Pod. Good."
"Node 2 has 1 Pod. Good."
"Node 3 is tainted. DaemonSet does not tolerate it. Skip."
```

### Auto-Scaling Flow

```
[ DaemonSet: monitoring-agent ]
      |
      v (Controller watches nodes)
[ Node 1: Pod exists ]     [ Node 2: Pod exists ]
      |
      v (New node added!)
[ Node 3: No Pod ]
      |
      v (Controller detects mismatch)
[ Controller creates Pod on Node 3 ]
      |
      v
[ Node 3: Pod exists ]
```

## Hands-on

### Objective

Deploy a DaemonSet to your kind cluster and verify that exactly one Pod lands on each worker node.

### Step 1: Create Multi-Node Cluster

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

### Step 2: Deploy the DaemonSet

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
  labels:
    app: log-agent
spec:
  selector:
    matchLabels:
      app: log-agent
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      containers:
      - name: agent
        image: busybox:latest
        command: ["sh", "-c", "echo 'Collecting logs...' && sleep 3600"]
EOF
```

### Step 3: Observe the Placement

```bash
kubectl get pods -o wide -l app=log-agent
```

Expected: 2 Pods running (one on each worker node). No Pod on the control-plane node.

### Step 4: Verify DaemonSet Status

```bash
kubectl get daemonset log-agent
```

Expected: `DESIRED 2`, `CURRENT 2`, `READY 2`.

### Step 5: Add a Toleration for Control Plane

```bash
kubectl delete daemonset log-agent

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
  labels:
    app: log-agent
spec:
  selector:
    matchLabels:
      app: log-agent
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      tolerations:
      - key: "node-role.kubernetes.io/control-plane"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: agent
        image: busybox:latest
        command: ["sh", "-c", "echo 'Collecting logs...' && sleep 3600"]
EOF
```

```bash
kubectl get pods -o wide -l app=log-agent
```

Expected: 3 Pods running (one on each node, including control-plane).

### Step 6: Cleanup

```bash
kubectl delete daemonset log-agent
kind delete cluster
```

## Commands

```bash
# List DaemonSets
kubectl get daemonset

# Describe a DaemonSet
kubectl describe daemonset <name>

# Check which nodes have DaemonSet Pods
kubectl get pods -o wide -l app=<label>

# Update DaemonSet image
kubectl set image daemonset/<name> <container>=<new-image>

# Roll back a DaemonSet
kubectl rollout undo daemonset/<name>

# Delete a DaemonSet
kubectl delete daemonset <name>
```

## YAML Explanation

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
  labels:
    app: log-agent
spec:
  selector:
    matchLabels:
      app: log-agent
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      tolerations:
      - key: "node-role.kubernetes.io/control-plane"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: agent
        image: busybox:latest
        command: ["sh", "-c", "echo 'Collecting logs...' && sleep 3600"]
```

### Field-by-Field Explanation

- `kind: DaemonSet`: Tells Kubernetes this is a node-level workload.
- No `replicas` field: The node count dictates the replicas.
- `spec.template.spec.tolerations`: Allows the DaemonSet to run on tainted nodes (like the control plane).
- `selector` and `template`: Just like a Deployment, the controller uses labels to track the Pods it creates.

## Production Notes

- **Use for Infrastructure Only.** DaemonSets are for logging (Fluent Bit, Promtail), monitoring (Datadog Agent, Node Exporter), and networking (CNI plugins like Calico or Cilium).
- **Set Resource Limits.** Even infrastructure Pods need CPU/Memory limits. A buggy logging agent can consume 100% of a node's CPU, starving your actual applications.
- **Tolerate Control Plane Taints (If needed).** If you genuinely need logs from the control plane (e.g., API server audit logs), you must add a toleration for `node-role.kubernetes.io/control-plane` in your DaemonSet YAML.
- **Use `updateStrategy: RollingUpdate`** for zero-downtime updates of infrastructure agents.
- **Monitor DaemonSet Pod resource usage.** They run on every node, so resource waste multiplies across the cluster.

### When to Use / When NOT to Use

**Use a DaemonSet when:**

- Log collection (Fluent Bit, Promtail).
- Node monitoring (Datadog Agent, Node Exporter).
- Cluster networking (CNI plugins, Istio CNI).

**Do NOT use a DaemonSet when:**

- User-facing web applications.
- APIs that scale based on traffic, not node count.
- Databases (use StatefulSet).

### Performance and Security Considerations

**Performance:** DaemonSets bypass the Scheduler, meaning they can be placed on nodes that are already at 100% CPU. Be careful: if your DaemonSet Pod is resource-heavy, it can cause OOMKilled crashes on already full nodes.

**Security:** DaemonSets often mount host paths (e.g., `/var/log/pods` from the node into the Pod). This is a privileged operation. Ensure the container image is trusted and the ServiceAccount is locked down, or an attacker could read sensitive node files.

## Best Practices

- Use DaemonSets only for node-level infrastructure.
- Set CPU and Memory requests and limits on DaemonSet Pods.
- Add tolerations for control-plane nodes if needed.
- Use `updateStrategy: RollingUpdate` for zero-downtime updates.
- Monitor DaemonSet Pod resource usage across the cluster.
- Use `priorityClassName: system-node-critical` for essential infrastructure agents.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Using DaemonSets for Web Apps | Misunderstanding the use case | Use Deployments for user-facing workloads |
| Forgetting Tolerations | Not understanding node taints | Add tolerations for control-plane if needed |
| No resource limits | Assuming infrastructure is lightweight | Always set CPU/Memory limits |
| Not monitoring DaemonSet pods | Assuming they're invisible | Monitor resource usage across all nodes |

## Troubleshooting

**Symptom: DaemonSet has fewer Pods than nodes**

Cause: Node has a taint that the DaemonSet doesn't tolerate, or `nodeSelector` doesn't match.

```bash
kubectl get nodes --show-labels
kubectl describe node <node> | grep Taints
kubectl describe daemonset <name>
```

Fix: Add tolerations or adjust `nodeSelector` to match the node.

**Symptom: DaemonSet Pod in CrashLoopBackOff**

Cause: Application error or misconfiguration.

```bash
kubectl logs -l app=<label> --previous
kubectl describe pod <pod-name>
```

Fix: Debug the application logs and fix the issue.

## Interview Questions

**Q: What is a DaemonSet?**

A: A Kubernetes controller that ensures a copy of a Pod runs on all (or some) nodes in the cluster. It is primarily used for node-level infrastructure like logging or monitoring agents.

**Q: How is the number of replicas determined for a DaemonSet?**

A: It is dynamically calculated. The DaemonSet controller counts the number of nodes in the cluster that match its selectors and tolerations, and ensures one Pod runs on each.

**Q: Does a DaemonSet use the standard kube-scheduler?**

A: No. The DaemonSetController bypasses the scheduler by directly setting the `spec.nodeName` field on the Pod manifest. This ensures infrastructure pods are placed even if the scheduler would normally reject the node due to resource constraints.

**Q: You deployed a logging DaemonSet, but you notice it is not running on your control-plane node. Why?**

A: Control-plane nodes are tainted by default (`node-role.kubernetes.io/control-plane:NoSchedule`) to prevent user workloads from interfering with the cluster brain. The DaemonSet respects this taint. To fix it, I need to add a toleration for that specific taint in the DaemonSet's Pod template.

**Q: What happens when you add a new node to the cluster?**

A: The DaemonSetController detects the new node on its next loop and automatically creates a new Pod on it.

**Q: Should you use a DaemonSet for a web server?**

A: No. DaemonSets run one Pod per node. If you scale your cluster, you get more web servers than you need. Use a Deployment for user-facing workloads.

## Scenario Questions

**Scenario 1:** You deploy a DaemonSet for a monitoring agent. After a node is drained for maintenance, the DaemonSet Pod is not recreated on the node when it comes back. Why?

A: The node might still have a taint from the drain operation (`node.kubernetes.io/unschedulable:NoSchedule`). Wait for the taint to be removed automatically, or manually remove it with `kubectl taint nodes <node> node.kubernetes.io/unschedulable-`.

**Scenario 2:** You need to run a DaemonSet on only nodes with a specific label (e.g., `disk=ssd`). How do you do this?

A: Add a `nodeSelector` to the DaemonSet Pod template: `nodeSelector: disk: ssd`. The DaemonSet will only create Pods on nodes with that label.

**Scenario 3 (Mini Project - The Tolerant Agent):**

Edit the DaemonSet from the lab. Add a tolerations block to the Pod template to tolerate the `node-role.kubernetes.io/control-plane` taint. Apply it and verify that a Pod now appears on the control-plane node as well.

## Quiz

1. What does a DaemonSet ensure?
   - A. Exactly 3 Pods run at all times
   - B. One Pod runs on every matching node
   - C. Pods run only on the control plane
   - D. Pods run on random nodes

2. Does a DaemonSet use the kube-scheduler?
   - A. Yes
   - B. No, it bypasses the scheduler
   - C. Only for control-plane nodes
   - D. Only for tainted nodes

3. What happens when a new node is added to the cluster?
   - A. Nothing
   - B. DaemonSet automatically creates a Pod on it
   - C. You must manually add a Pod
   - D. The DaemonSet deletes an old Pod

4. Why might a DaemonSet not run on a specific node?
   - A. The node is too fast
   - B. The node has a taint that isn't tolerated
   - C. The DaemonSet is full
   - D. The node is new

5. What is the primary use case for DaemonSets?
   - A. Web servers
   - B. Databases
   - C. Node-level infrastructure (logging, monitoring)
   - D. Batch processing

Answers: 1-B, 2-B, 3-B, 4-B, 5-C.

## Revision

One-minute revision:

- DaemonSets ensure a copy of a Pod runs on every node (or a subset of matching nodes).
- You do not specify a replica count. The DESIRED count is dynamically calculated based on the number of matching nodes.
- They are primarily used for cluster infrastructure: logging agents, monitoring agents, and networking.
- They bypass the standard kube-scheduler and directly bind the Pod to the node's name.
- They will not run on tainted nodes (like the control plane) unless you explicitly add a toleration.

Memory trick:

- Deployment: A flock of birds. You decide how many birds are in the flock.
- DaemonSet: A security guard at a mall. You don't hire 5 guards and hope they spread out. You explicitly assign one guard to every single exit/door.

Key facts:

- DaemonSet = 1 Pod per Node.
- No replicas field.
- Bypasses Scheduler (sets `nodeName` directly).
- Used for logs/metrics/networking.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl get daemonset` | Lists DaemonSets. Check DESIRED vs CURRENT columns. |
| `kubectl describe daemonset <name>` | Shows how many nodes are scheduled and any mismatches. |
| `kubectl get pods -o wide` | Verify which nodes the DaemonSet Pods landed on. |
| `kubectl set image daemonset/<name> <c>=<img>` | Updates DaemonSet image. |
| `kubectl rollout undo daemonset/<name>` | Rolls back a DaemonSet. |

## References

- [Kubernetes Documentation: DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
- [Kubernetes Documentation: Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Kubernetes Documentation: Node-pressure Eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/)
- [Fluent Bit Documentation](https://docs.fluentbit.io/)
- [Prometheus Node Exporter](https://github.com/prometheus/node_exporter)

## Related Lessons

- [Lesson 07 - Scheduling and Taints](../02-architecture/lesson-07-worker-node-architecture.md) - how the scheduler places Pods.
- [Lesson 10 - Pods, ReplicaSets, and Deployments](lesson-10-pods-replicasets-and-deployments.md) - for user-facing workloads.
- [Lesson 13 - StatefulSets](lesson-13-statefulsets.md) - for stateful workloads.
- [Lesson 15 - Jobs and CronJobs](lesson-15-jobs-and-cronjobs.md) - for batch workloads.
- [Module 08 - Observability](../08-observability/README.md) - monitoring and logging.

## Coming Next

Now that you understand DaemonSets for node-level infrastructure, the next lesson covers Jobs and CronJobs, which run finite tasks to completion on a schedule.
