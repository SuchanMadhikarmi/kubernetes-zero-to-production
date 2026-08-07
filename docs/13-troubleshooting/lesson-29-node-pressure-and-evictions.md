---
title: Lesson 29 - Node Pressure and Evictions (Saving the Ship)
module: 13 Troubleshooting
lesson: 29
status: Complete
tags: [kubernetes, node-pressure, eviction, memory-pressure, disk-pressure, qos, oomkilled, troubleshooting]
---

# Lesson 29 - Node Pressure and Evictions (Saving the Ship)

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

- Explain what happens when a Kubernetes node runs out of memory or disk space.
- Describe the Node Conditions `MemoryPressure`, `DiskPressure`, and `PIDPressure`.
- Explain how the Kubelet's Eviction Manager decides which Pods to kill.
- Connect node evictions to QoS Classes (Guaranteed, Burstable, BestEffort) from Lesson 25.
- Distinguish an eviction (Kubelet) from an OOMKill (Linux Kernel).

## Prerequisites

- Completion of Lessons 1 through 28.
- A running kind cluster.
- `kubectl` installed and configured.
- A solid understanding of QoS Classes from [Lesson 25 - Resource Requests, Limits, and Quotas](../06-configuration/lesson-25-resource-requests-limits-and-quotas.md), including how `request` and `limit` map to Guaranteed, Burstable, and BestEffort.

## Real-world Motivation

### The Sinking Ship

Imagine a node has 16 GB of RAM. A developer forgets to set memory limits on their new data-processing Pod. The Pod starts consuming 15 GB of RAM and keeps growing. If nothing is done, the Linux kernel will panic, or the kubelet itself will crash. If the kubelet crashes, the node goes dark, and every single Pod on that node dies, causing a massive outage.

### Why This Exists

To protect the node. A crashed node takes down everything on it, making recovery very difficult. By proactively killing a few lower-priority Pods, Kubernetes ensures the node survives and can continue hosting the remaining healthy Pods. This is a calculated sacrifice to save the cluster.

### Real Company Examples

**Gaming Company:** A gaming company runs game servers on Kubernetes. They overcommit their nodes, putting 5 game servers on a node meant for 3. They rely on the Eviction Manager. If a sudden spike in players causes memory to hit the threshold, the Kubelet instantly evicts the game server with the fewest players (lowest priority) to protect the other 4 games. The evicted players get reconnected to a new server on another node.

## Core Concepts

### Explain Like I'm 12

Imagine a ship is sinking because it is too heavy. The captain (Kubelet) says, "We need to throw cargo overboard to save the ship!"

- First, they throw over the cheap, unimportant cargo (BestEffort Pods).
- If the ship is still sinking, they throw over the medium cargo (Burstable Pods).
- They will never throw over the VIP passengers (Guaranteed Pods) unless the ship is literally seconds away from sinking.

### Explain Like I'm a Junior Engineer

If a node's memory or disk gets too full, the kubelet triggers an Eviction. The kubelet ranks all the Pods on the node based on their QoS class (Lesson 25) and their priority. It starts killing the lowest-ranking Pods until the node's resources return to a safe level.

### Explain Technically

The kubelet dedicates the node's resources to the Eviction Manager and the scheduler. The kubelet reserves a chunk for itself (System Reserved and Kube Reserved). The rest is `NodeAllocatable`, which is what the scheduler can offer to Pods.

The kubelet periodically polls cgroup stats and filesystem stats. If available memory drops below the hard eviction threshold (default `memory.available < 100Mi`), it sets the `MemoryPressure` condition to `True`. The Eviction Manager ranks Pods by:

1. How far they exceed their resource requests.
2. Their QoS class (BestEffort dies first).
3. Their PriorityClass (lower priority dies first).

The kubelet sends `SIGTERM` to the chosen Pod. If the node is in a critical state, it may skip `SIGTERM` and immediately send `SIGKILL`.

### How Kubernetes Implements It Internally

When `MemoryPressure=True`, the kube-scheduler notices this condition and stops scheduling new Pods on the node. The kubelet takes over, terminating existing Pods locally. The API Server is notified of the Pod terminations, and the ReplicaSet controller (running in the control plane) then schedules replacements on healthier nodes.

### Why Kubernetes Was Designed That Way

Kubernetes separates node-level survival (the Kubelet) from cluster-level reconciliation (the controllers). The kubelet can act fast and locally to protect the node, while the ReplicaSet controller guarantees the desired replica count is restored elsewhere. This division of responsibility keeps a single sick node from cascading into a cluster-wide outage.

## Architecture

```
[ Node Memory: 4GB Total ]
[ Threshold: 500MB must remain free ]
      |  App 1 (Guaranteed, 1GB)
      |  App 2 (Burstable, 500MB)
      |  App 3 (BestEffort, 3GB)  <--- Uses all the memory!
Node Memory drops to 100MB free
      |
      v
[ Kubelet: "MemoryPressure=True! Evict someone!" ]
      |
      v
[ Kubelet ranks pods: App 3 is BestEffort. ]
      |
      v
[ App 3 receives SIGTERM and is Evicted. ]
      |
      v
Node memory recovers. MemoryPressure=False.
```

### Terminology

| Term | Definition |
|------|------------|
| Node Condition | A status flag on the Node object (for example, `MemoryPressure`). |
| MemoryPressure | Node memory is low. |
| DiskPressure | Node disk space is low. |
| PIDPressure | The node is running out of process IDs. |
| Eviction | The Kubelet terminating Pods to free resources and save the node. |
| Hard Eviction Threshold | A critical resource line (for example, `memory.available < 100Mi`). When crossed, the Kubelet immediately evicts Pods. |
| Soft Eviction Threshold | A warning line set before the hard threshold, giving a grace period before eviction. |
| OOMKilled | A container state meaning the Linux kernel killed the process for exceeding its cgroup limit. |
| Ranking | The Kubelet ordering all Pods by QoS class and PriorityClass to decide which to evict. |

### How It Works Internally

1. The kubelet polls cgroup and PodDisruptionBudget stats every 10 seconds.
2. It calculates: `NodeAllocatable - MemoryUsed = MemoryAvailable`.
3. If `MemoryAvailable < 100Mi`, `MemoryPressure` is set to `True`.
4. The Eviction Manager sorts all active Pods.
5. It picks the lowest-ranked Pod and sends a DELETE request to the API Server (and `SIGTERM` to the process).
6. It repeats until `MemoryAvailable > 100Mi`.
7. The condition is cleared.

### Step-by-Step Workflow

1. Node runs out of memory.
2. `MemoryPressure=True`.
3. Scheduler stops placing new Pods on the node.
4. Kubelet ranks running Pods by QoS and priority.
5. Kubelet evicts (kills) the lowest-ranked Pods.
6. Node memory recovers.
7. `MemoryPressure=False`.
8. Scheduler resumes placing Pods on the node.

### Lifecycle

| State | Description |
|-------|-------------|
| Pressure Detected | Resource drops below the threshold. |
| Condition Set | Node status updated (for example, `MemoryPressure=True`). |
| Eviction | Pods are terminated sequentially until pressure clears. |
| Recovery | Resource returns to safe levels; condition cleared. |

### Communication Patterns

| Communication | Mechanism | Example |
|---------------|-----------|---------|
| Kubelet -> API Server | Report node condition | `PATCH /api/v1/nodes/<node>/status` |
| kube-scheduler -> API Server | Read node conditions | Skips nodes with `MemoryPressure=True` |
| Kubelet -> Container | Terminate process | Sends `SIGTERM`, then `SIGKILL` if needed |
| ReplicaSet controller | Recreate evicted Pod | Creates a new Pod on a healthy node |

### Common Myths

| Myth | Fact |
|------|------|
| "If my Pod gets OOMKilled, Kubernetes moves it to a node with more RAM." | False. Kubernetes restarts the container on the same node. It does not reschedule the Pod unless the node dies or evicts the Pod entirely. |
| "Eviction means my container hit its memory limit." | False. If the container hit its own limit, it gets OOMKilled. An eviction means the whole node ran out of memory and the Kubelet chose your Pod as a victim to save the host. |

## ASCII Diagrams

Mental Model: The Kubelet is a lifeboat captain. When the boat takes on water (MemoryPressure), it throws people overboard. It throws the stowaways (BestEffort) first, then the economy class (Burstable), to save the first-class passengers (Guaranteed).

```text
[ Node Memory Drops ]
      |
      v
[ Kubelet checks thresholds ]
      |
      +---> Memory > threshold free  -> Do nothing.
      |
      +---> Memory < threshold free  -> Trigger Eviction!
                |
                v
            [ Rank Pods ]
                |
                +---> 1. BestEffort  (No limits) -> KILL
                +---> 2. Burstable   (Over limits) -> KILL
                +---> 3. Burstable   (Under limits) -> KILL
                +---> 4. Guaranteed  -> KILL (Last resort)
```

## Hands-on

### Objective

Inspect the node's current health conditions, understand the eviction thresholds, and simulate the ranking logic.

### Step 1: Inspect Node Health

```bash
kubectl describe node kind-control-plane
```

Scroll down to the `Conditions:` section. You will see something like this:

```text
Conditions:
  Type             Status  LastHeartbeatTime
  ----             ------  -----------------
  MemoryPressure   False   ...
  DiskPressure     False   ...
  PIDPressure      False   ...
  Ready            True    ...
```

### Step 2: Inspect the Eviction Thresholds

Scroll down to the `Allocatable:` section. The kubelet reserves a chunk of the node's resources for itself (System Reserved) and for Kubernetes components (Kube Reserved). The default hard eviction threshold for memory is `100Mi`. If the node's available memory drops below `100Mi`, the kubelet starts evicting Pods.

### Step 3: Simulate the Ranking (Mental Exercise)

Imagine your control-plane node is experiencing MemoryPressure. On that node you have these Pods:

- `critical-database` (QoS: Guaranteed, Priority: 1,000,000)
- `background-worker` (QoS: Burstable, Priority: 100)
- `random-script` (QoS: BestEffort, Priority: 0)

**Your Task:**

1. Which Pod will the Kubelet evict first to save the node?
2. Which Pod will the Kubelet evict last (or never evicts)?
3. What is the difference between an Eviction (Kubelet) and an OOMKilled (Linux Kernel)?

(Answer: 1. `random-script` (BestEffort). 2. `critical-database` (Guaranteed). 3. OOMKilled happens when a single container hits its own limit; the kernel kills it locally. Eviction happens when the whole node is low on memory; the Kubelet deletes entire Pods to save the node.)

## Commands

```bash
# Read node conditions (MemoryPressure, DiskPressure, PIDPressure)
kubectl describe node <name>

# Read the allocated and allocatable resources on a node
kubectl describe node <name> | grep -A 8 Allocatable

# Find Pods the Kubelet evicted
kubectl get events -A | grep -i evicted

# Check a Pod's QoS class
kubectl get pod <name> -o jsonpath='{.status.qosClass}'

# Check why a container died
kubectl describe pod <name>
```

## YAML Explanation

A healthy cluster rarely needs to define eviction policies in YAML. What matters is defining memory limits so your Pods are not BestEffort. A Guaranteed Pod looks like this:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: critical-database
spec:
  containers:
  - name: db
    image: postgres:16
    resources:
      requests:
        cpu: 2
        memory: 4Gi
      limits:
        cpu: 2
        memory: 4Gi
```

### Field-by-Field Explanation

- `resources.requests`: The minimum the scheduler guarantees the container.
- `resources.limits`: The maximum the container may use.
- Setting `requests == limits` makes the Pod QoS `Guaranteed`, so it is the last class to be evicted.
- Leaving both empty makes the Pod QoS `BestEffort`, meaning it is the first to be evicted during pressure.

For node-level behavior you usually do not write YAML. Instead you configure the kubelet Eviction Manager thresholds (for example, `--eviction-hard=memory.available<100Mi`). Eviction policies are a system/cluster concern, not an application manifest.

## Production Notes

- Always set **memory limits**: If a container leaks memory, it drains the whole node, triggering evictions of healthy apps. Memory limits ensure the Linux kernel kills only the leaky container (OOMKilled) before the node gets sick.
- Set limits on **logging agents**: Logging agents (like Fluent Bit) often cause DiskPressure by writing too many logs to the node's disk.
- Use **Guaranteed QoS** for critical apps: If your database is Guaranteed (`Requests == Limits`), it is protected from eviction until the absolute last resort.
- Set aside CPU and memory for the host OS and container runtime (`system-reserved` and `kube-reserved`) so the kubelet and node agents never starve during pressure.
- Reserve memory and monitor the reserving process itself: a leaked reservation that consumes the node is still a DoS vector.

### When to Use / When NOT to Use

**Use Evictions when:**

- They are a safety mechanism, not a tool. Rely on them to prevent catastrophic node crashes.
- Overcommitting nodes is intentional — packing many BestEffort batch jobs that can be safely evicted if the node gets busy.

**Avoid relying on Evictions when:**

- You might be tempted to treat them as a scaling mechanism. Evictions cause application instability and thrashing (Pods being killed and recreated endlessly). Proper autoscaling (HPA) should prevent resource exhaustion before pressure occurs.

### Performance and Security Considerations

**Performance:** Eviction thrashing is a severe issue. If a node evicts a Pod, the ReplicaSet recreates it. If it lands on the same node, it gets evicted again. This loop consumes huge CPU and network bandwidth.

**Security:** If a malicious user creates a Pod that consumes infinite RAM, they can cause DoS on the node, evicting all other tenants. ResourceQuotas (`ResourceQuota`) and LimitRanges (`LimitRange`) are required to prevent this.

## Best Practices

- Always set memory limits, especially on user-facing and batch workloads.
- Monitor `kubectl describe node` for `MemoryPressure` and `DiskPressure`.
- Give critical-stateful apps Guaranteed QoS and a high PriorityClass.
- Use `ResourceQuota` and `LimitRange` in shared/medium clusters to stop one team from starving the node.
- Capture `kubelet evicted` events into your alerting system.
- Tune eviction thresholds for your node sizes and workload burst profiles.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Running Pods without limits | Creates BestEffort Pods evicted first during any minor pressure | Always set `limits`, or set `requests == limits` for critical work |
| Ignoring DiskPressure | Logs and emptyDir data fill the node disk and evict others | Set log limits and monitor emptyDir usage |
| Confusing Eviction with OOMKilled | Both end in a death flag | OOMKilled is container-local; Eviction is node-level survival |
| Not reserving node resources | Kubelet and OS may starve, worsening pressure | Configure `system-reserved` and `kube-reserved` |
| Applying QoS unevenly | Only monitoring capacity, not setting request==limit on important apps | Give guaranteed QoS to the workloads you cannot afford to lose |

## Troubleshooting

**Symptom: The Disappearing Pods**

Users complain that Pods keep disappearing and reappearing on different node.

Check the Node Conditions:

```bash
kubectl describe node <name> | grep -A 5 Conditions
```

Is `MemoryPressure` or `DiskPressure` showing `True`?

Check events for evictions:

```bash
kubectl get events --all-namespaces | grep -i evicted
```

If you see `Evicted` messages, the Kubelet is actively killing Pods. Find the app causing the memory leak or disk spam. Reduce its requests/limits, fix the leak, or move it to a larger node.

**Symptom: Pod says `OOMKilled` but no node pressure**

The container's own limit is too low. Increase the container's memory limit or fix the leak; the node is healthy. This is a local problem, not a node problem.

## Interview Questions

**Q: What is the difference between OOMKilled and Evicted?**

A: OOMKilled is a container-level enforcement by the Linux Kernel (the container hit its own cgroup limit). Evicted is a node-level survival action by the Kubelet (the node is out of memory).

**Q: Which QoS class is evicted first during MemoryPressure?**

A: BestEffort (no request and no limit).

**Q: How does Kubernetes protect a node from crashing when it is low on memory?**

A: The Kubelet monitors node conditions. When it hits the hard eviction threshold for memory, it triggers an eviction. It ranks all Pods by QoS class and priority, terminating BestEffort and Burstable Pods first to free RAM and keep the node alive.

**Q: How does the scheduler react to a node with MemoryPressure=True?**

A: It stops placing new Pods on that node.

**Q: True or False: If a Pod is OOMKilled, it means the node ran out of memory.**

A: False. It means the container hit its own limit; the node is likely healthy.

## Scenario Questions

**Scenario 1:** A user reports their Pod was restarted and rescheduled to a different node. `kubectl describe pod` shows `Reason: Evicted`. What happened, and how do you prevent it from happening to critical apps?

A: The Pod's old node experienced core resource pressure (Memory or Disk) and the Kubelet evicted the lowest-ranked Pod to save the node. For a critical app, give it Guaranteed QoS (`requests == limits`) and a high PriorityClass so it is evicted last.

**Scenario 2 (Mini Project - The Pressure Simulator):**

Deploy a Pod with no resource limits (BestEffort). Deploy a second Pod with `requests == limits` (Guaranteed). Then:

```bash
kubectl get pod <name> -o jsonpath='{.status.qosClass}'
```

Mental exercise: If the node runs out of memory, which Pod dies first? (Answer: The BestEffort one.)

## Quiz

1. Which component triggers an Eviction?
   - A. The Linux Kernel
   - B. The Kubelet
   - C. The kube-scheduler
   - D. The container runtime

2. Which component triggers OOMKilled?
   - A. The Kubelet
   - B. The kube-scheduler
   - C. The Linux Kernel
   - D. The API Server

3. Which QoS class is evicted first during MemoryPressure?
   - A. Guaranteed
   - B. Burstable
   - C. BestEffort
   - D. BestEffort-Guaranteed

4. Default hard eviction threshold for memory is:
   - A. `memory.available < 1Mi`
   - B. `memory.available < 10Mi`
   - C. `memory.available < 50Mi`
   - D. `memory.available < 100Mi`

5. When a node has `MemoryPressure=True`, what does the scheduler do?
   - A. Schedules more Pods to it
   - B. Stops scheduling new Pods to it
   - C. Reboots the node
   - D. Moves existing Pods off the node

Answers: 1-B, 2-C, 3-C, 4-D, 5-B.

## Revision

One-minute revision:

- Pressure = the node is unhealthy.
- Eviction = Kubelet kills Pods to save the node.
- OOMKilled = kernel kills a container to enforce a cgroup limit.
- BestEffort dies first, then Burstable, then Guaranteed last.

Memory trick:

- **OOMKilled:** A witness dragging a drunk guest who drank too much (hit their personal limit).
- **Eviction:** The fire marshal evacuating the whole building because the foundation is cracking (node out of memory). They kick out the loiterers (BestEffort) first.

Key facts:

- Node Conditions: `MemoryPressure`, `DiskPressure`, `PIDPressure`.
- Eviction is node-level; OOMKilled is container-level.
- Hard threshold default is `100Mi` available memory.
- The scheduler skips nodes in pressure.
- Traffic thrashes if a Pod keeps landing back on the same drained node.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl describe node <name>` | Check Conditions for Memory- or Disk-Pressure |
| `kubectl describe node <name> \| grep Allocatable` | Show requested vs allocatable resource |
| `kubectl get events --all-namespaces \| grep -i evicted` | Find Pods the Kubelet evicted |
| `kubectl get pod <name> -o jsonpath="{.status.qosClass}"` | Print the Pod's QoS class |
| `kubectl describe pod <name>` | Check if the container was OOMKilled |

## References

- [Kubernetes Documentation: Node-pressure Eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/)
- [Kubernetes Documentation: Configure Pod Distribution Budget](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
- [Kubernetes Documentation: Resource Quality of Service](https://kubernetes.io/docs/concepts/workloads/pods/resources/)
- [Kubernetes Blog: Managing Resource Quotas](https://kubernetes.io/blog/)

## Related Lessons

- [Lesson 25 - Resource Requests, Limits, and Quotas](../06-configuration/lesson-25-resource-requests-limits-and-quotas.md) - how `request` and `limit` map to QoS.
- [Lesson 28 - Cluster Upgrades and Maintenance (Cordon and Drain)](../12-production/lesson-28-cluster-upgrades-and-maintenance.md) - voluntary node eviction with `drain`.
- [Lesson 27 - The SRE Troubleshooting Masterclass](../13-troubleshooting/lesson-27-sre-troubleshooting-masterclass.md) - systematic debugging of node conditions.

## Coming Next

The next lesson is the Troubleshooting Networking and Cluster Issues playbook: debugging DNS, Service connectivity, Ingress, and CNI problems across the control plane and data plane.