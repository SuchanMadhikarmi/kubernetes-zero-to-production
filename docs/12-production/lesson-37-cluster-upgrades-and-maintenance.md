---
title: Lesson 37 - Cluster Upgrades and Maintenance (Cordon and Drain)
module: 12 Production
lesson: 37
status: Complete
tags: [kubernetes, cordon, drain, uncordon, eviction, pdb, node-maintenance, production]
---

# Lesson 37 - Cluster Upgrades and Maintenance (Cordon and Drain)

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

- Safely take a node offline for maintenance without causing application downtime.
- Explain the difference between `cordon`, `drain`, and `uncordon`.
- Describe how Kubernetes gracefully evicts Pods using `SIGTERM` and `terminationGracePeriodSeconds`.
- Intentionally trigger a drain protection error and bypass it safely with the correct flags.
- Use PodDisruptionBudgets to protect application availability during voluntary disruptions.

## Prerequisites

- Completion of Lessons 1 through 27, especially the scheduling concepts from Module 02 and the troubleshooting methodology from Lesson 27.
- A running kind cluster, ideally the multi-node cluster with 2 worker nodes (`kind-worker` and `kind-worker2`).
- `kubectl` installed and configured with the correct context.

## Real-world Motivation

### The Reboot Dilemma

Imagine you need to apply a critical Linux kernel patch to Node A. If you simply run `sudo reboot`, the node goes offline instantly. Any Pods running on Node A are terminated abruptly. Users actively connected to those Pods get `502 Bad Gateway` errors. Furthermore, ReplicaSets will not know to recreate those Pods until the control plane realizes the node is dead, which takes about 40 seconds by default (node-monitor-grace-period). You have just caused an unnecessary production outage for the sake of a routine patch.

### Why This Exists

Kubernetes needed a way to handle voluntary disruptions such as maintenance, scaling down, and kernel upgrades safely. The `drain` command initiates a graceful shutdown. It tells the control plane: "I want to stop these Pods, please reschedule them elsewhere before I turn off the power." This ensures zero downtime during planned infrastructure maintenance.

### Real Company Examples

**Salesforce:** Salesforce runs an automated "Node Rotator" service. Every night it checks for nodes running older Amazon Machine Image (AMI) versions. It cordons the node, drains it while respecting PodDisruptionBudgets, terminates the EC2 instance, and lets the Cluster Autoscaler spin up a fresh, patched node. This is how they maintain security at scale with zero downtime.

## Core Concepts

### Explain Like I'm 12

Imagine a hotel wants to renovate the 3rd floor. The manager does not just lock the doors while guests are sleeping.

- **Cordon:** The manager puts a "Do Not Assign" sign on the 3rd floor. New guests are sent to other floors.
- **Drain:** The manager goes to the current guests, knocks on their doors, and politely asks them to move to a different floor so construction can begin.
- **Uncordon:** After the renovation, the manager removes the sign, and new guests can be assigned to the 3rd floor again.

### Explain Like I'm a Junior Engineer

- `kubectl cordon <node>`: Stops the scheduler from placing new Pods on the node.
- `kubectl drain <node>`: Evicts all running Pods from the node. The ReplicaSet recreates them on healthy nodes.
- `kubectl uncordon <node>`: Allows scheduling again.

### Explain Technically

When you run `kubectl drain`, the CLI calls the Eviction API at `/api/v1/namespaces/default/pods/<name>/eviction`. The API Server checks whether the eviction violates any PodDisruptionBudgets (PDBs). If it is safe, the Pod is deleted. The Pod receives a `SIGTERM` signal, starting its `terminationGracePeriodSeconds` countdown.

Furthermore, `drain` refuses to evict Pods that are not managed by a controller (bare Pods) and refuses to evict DaemonSet Pods by default. A DaemonSet is supposed to run on every node, so deleting its Pod is pointless: the controller will simply recreate it immediately.

### How Kubernetes Implements It Internally

The `kubectl drain` command is a client-side helper. It loops through all Pods on the node and sends Eviction API requests. If an eviction is blocked by a PodDisruptionBudget, `kubectl drain` keeps retrying until the PDB allows it or until the command times out. This is why a drain can hang when a PDB blocks all evictions.

### Why Kubernetes Was Designed That Way

Kubernetes separates node maintenance from workload management. By making the scheduler treat a cordoned node as `SchedulingDisabled`, and by making drain respect PDBs, Kubernetes protects applications from the developer forgetting to plan for maintenance. The design guarantees that voluntary disruption never violates the availability contract expressed by a PodDisruptionBudget.

## Architecture

```
[ Node A (Cordoned) ]                     [ Node B (Schedulable) ]
      |  Pod 1 (app=web)                       |  Pod 3 (app=web)
      |    |                                   |  Pod 1-NEW (app=web)
      |    |  (Drain/Evict)                    |      ^
      |    v                                   |      |
      |  [ API Server ] ------------------------      |
      |      |  (ReplicaSet recreates here)  ---------+
      |      v
      |  [ Deleted ]
      |
      |  Pod 2 (DaemonSet) --> [ Refuses to Evict! ]
```

### Terminology

| Term | Definition |
|------|------------|
| Voluntary Disruption | An interruption caused by an admin (for example, draining a node or upgrading a cluster). |
| Involuntary Disruption | An interruption caused by hardware failure or network issues. |
| Cordon | Marks a node as `Unschedulable`. New Pods are not placed on it. Existing Pods keep running. |
| Drain | Evicts all running Pods from a node so it can be shut down or rebooted. |
| Uncordon | Marks the node as `Schedulable` again. |
| PodDisruptionBudget (PDB) | A policy that limits the number of Pods that can be down simultaneously during voluntary disruptions. |
| Eviction API | The Kubernetes API that safely deletes a Pod while respecting PDBs. |
| SIGTERM | The termination signal sent to a process to tell it to shut down gracefully. |
| terminationGracePeriodSeconds | The time a Pod is given to shut down cleanly before it is force-killed with `SIGKILL`. |

### How It Works Internally

1. You run `kubectl drain node-1`.
2. `kubectl` queries the API Server for all Pods running on `node-1`.
3. It filters out DaemonSet Pods (unless `--ignore-daemonsets` is passed).
4. It sends Eviction requests to the API Server for the remaining Pods.
5. The API Server deletes the Pods. The Kubelet sends `SIGTERM` to the container processes.
6. The ReplicaSet controller notices the Pods are gone and creates new ones on `node-2`.

### Step-by-Step Workflow

1. Admin needs to patch Node A.
2. Admin runs `kubectl cordon node-a`.
3. Admin runs `kubectl drain node-a --ignore-daemonsets --delete-emptydir-data`.
4. Workloads migrate to Node B.
5. Admin SSHs into Node A and applies the OS patch.
6. Admin reboots Node A.
7. Admin runs `kubectl uncordon node-a`.

### Lifecycle

| State | Description |
|-------|-------------|
| Cordon | Node is marked `SchedulingDisabled`. No new Pods are scheduled. |
| Drain | Pods are evicted. The node is empty of user workloads. |
| Maintenance | OS patching, hardware replacement, or kernel upgrade takes place. |
| Uncordon | Node is marked `Ready`. Scheduling resumes. |

### Communication Patterns

| Communication | Mechanism | Example |
|---------------|-----------|---------|
| kubectl -> API Server | List Pods on the node | `GET /api/v1/nodes/node-1` |
| kubectl -> API Server | Evict a Pod | `POST /api/v1/namespaces/default/pods/<name>/eviction` |
| Kubelet -> Container runtime | Stop containers | Sends `SIGTERM`, then `SIGKILL` after the grace period |
| Scheduler -> API Server | Place new Pods on schedulable nodes | Skips nodes with `SchedulingDisabled` |

### Common Myths

| Myth | Fact |
|------|------|
| "Cordon stops Pods from running." | False. Cordon only stops new Pods from being scheduled. Existing Pods continue to run. |
| "You must drain a node to stop a compromised Pod." | False. Draining is a graceful process. If a Pod is compromised, run `kubectl delete pod <name>` immediately to kill it instantly. |

## ASCII Diagrams

Mental Model: Cordon is a "Closed" sign on a restaurant. Drain is politely asking the current diners to finish up and leave so you can lock the doors.

```text
[ 1. Cordon Node A ]
[ Node A ] -> Status: Ready, SchedulingDisabled
[ Node B ] -> Status: Ready

[ 2. Drain Node A ]
[ Node A ] -> Pod 1 (web) evicted -> SIGTERM sent -> Pod 1 deleted
[ Node B ] -> ReplicaSet notices Pod 1 is gone -> Creates Pod 1-NEW on Node B

[ 3. Reboot Node A (Patch OS) ]

[ 4. Uncordon Node A ]
[ Node A ] -> Status: Ready
```

## Hands-on

### Objective

Deploy an app, cordon a node, safely drain it, and watch the app migrate to another node with zero downtime.

### Step 1: Deploy an App

Deploy 3 replicas of Nginx:

```bash
kubectl create deployment web-app --image=nginx:alpine --replicas=3
```

Verify they are spread across the 2 worker nodes:

```bash
kubectl get pods -o wide
```

### Step 2: Cordon a Node

Pretend `kind-worker` needs a security patch:

```bash
kubectl cordon kind-worker
```

Verify it is marked `Ready` with `SchedulingDisabled`:

```bash
kubectl get nodes
```

Note: The node is still `Ready`. It is simply not accepting new Pods.

### Step 3: Try to Drain the Node (The Failure)

Try to evict the running Pods from that node:

```bash
kubectl drain kind-worker
```

Expected Output: It will output a bunch of text and likely fail or hang, complaining about DaemonSets and Pods with emptyDir volumes.

**Your Task:**

1. Did the drain succeed, or did it error out?
2. What are the two specific types of Pods that Kubernetes refused to evict, causing the error? (Hint: Look for the suggestions in the error message about what flags to use.)
3. Why does Kubernetes protect these specific types of Pods from eviction?

(Answer: 1. It errored out. 2. DaemonSet-managed Pods and Pods with emptyDir volumes. 3. It protects DaemonSets because they are supposed to run on every node; deleting them is pointless as they will just be recreated. It protects emptyDir Pods because deleting the Pod deletes the local data, which might cause data loss.)

### Step 4: The Fix - Bypassing the Protections

In a real maintenance window, we want to drain the node. We know the DaemonSet Pods will just die when the server reboots (which is fine, they are usually logging or monitoring agents), and we know our app Pods do not rely on emptyDir for critical data.

```bash
kubectl drain kind-worker --ignore-daemonsets --delete-emptydir-data
```

Explanation:

- `--ignore-daemonsets`: Leaves the DaemonSet Pods alone. They are killed when the node reboots and recreated when it returns.
- `--delete-emptydir-data`: Allows deletion of Pods that use ephemeral (emptyDir) storage.

### Watch the Migration

Wait a few seconds, then run:

```bash
kubectl get pods -o wide
```

**Your Task:**

1. Did the drain command succeed this time?
2. Look at the `NODE` column. Did all of your `web-app` Pods move to `kind-worker2`?
3. Run `kubectl get nodes`. What is the status of `kind-worker` now?

(Answer: 1. Yes. 2. Yes, they were recreated on `kind-worker2`. 3. `Ready, SchedulingDisabled`.)

### Step 5: Finish Maintenance (Uncordon)

The security patch is applied and the server is ready for use again. Bring it back into the cluster:

```bash
kubectl uncordon kind-worker
```

Verify it is ready for new Pods:

```bash
kubectl get nodes
```

It should say `Ready` again, without `SchedulingDisabled`.

### Step 6: Cleanup

```bash
kubectl delete deployment web-app
```

## Commands

```bash
# Stop new Pods from being scheduled on a node (existing Pods keep running)
kubectl cordon <node>

# Evict running Pods so the node can be shut down safely
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Force-evict a node ignoring all protection (use with extreme caution)
kubectl drain <node> --force --ignore-daemonsets --delete-emptydir-data

# Allow scheduling again after maintenance
kubectl uncordon <node>

# List nodes and their scheduling status
kubectl get nodes

# Check PodDisruptionBudgets before draining
kubectl get pdb
```

## YAML Explanation

The core object in this lesson is the PodDisruptionBudget. Drain honors it automatically.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-app-pdb
spec:
  minAvailable: 4
  selector:
    matchLabels:
      app: web-app
```

### Field-by-Field Explanation

- `apiVersion: policy/v1`: The stable API version for PodDisruptionBudgets.
- `minAvailable: 4`: At least 4 Pods matching the selector must always be running. Drain will not evict a Pod if doing so would drop the count below 4.
- `selector.matchLabels`: Selects the Pods this PDB protects. It must match the labels of your workload's Pods.

An equivalent policy can be expressed with `maxUnavailable: 1`, which is often easier to reason about: at most 1 Pod may be down at a time during voluntary disruptions.

## Production Notes

- **Always cordon before drain:** While `drain` automatically cordons the node, doing it explicitly prevents new Pods from sneaking in while you are preparing the drain command.
- **Always use PodDisruptionBudgets:** If you have 5 web Pods, set a PDB requiring at least 4 to be running. If someone tries to drain a node holding 2 Pods, Kubernetes only evicts 1, keeping your app highly available.
- **Set `terminationGracePeriodSeconds` properly:** If your app takes 60 seconds to save state and shut down, the default 30-second grace period will cause a `SIGKILL` and potential data loss.
- **Automate the cycle:** In production, cordon/drain/uncordon should be wrapped in automation (Ansible playbooks, Cluster API, or a node rotator like Salesforce's) so maintenance windows are repeatable and auditable.

### When to Use / When NOT to Use

**Use cordon and drain when:**

- Upgrading the node operating system or Kubernetes version.
- Replacing failing hardware (RAM, disk, NIC).
- Resizing the cluster by scaling down node pools.

**Avoid cordon and drain when:**

- The node is already dead during a live incident. Just delete the node from the cluster; the control plane reschedules the Pods itself.

### Performance and Security Considerations

**Performance:** Draining a node with large stateful workloads (for example, a 500 GB database) can take hours if the Pod needs to flush data to disk. Always set a generous `terminationGracePeriodSeconds` for stateful applications.

**Security:** When a node is cordoned, the Pods on it are still running. If a Pod is compromised, the attacker can still operate on the cordoned node. You must drain to actually stop the processes. Never use `--force` blindly: it bypasses the Eviction API and ignores PDBs, which can cause an outage.

## Best Practices

- Always cordon explicitly before running a drain.
- Define PodDisruptionBudgets for every workload that must stay available during maintenance.
- Use `--ignore-daemonsets` and `--delete-emptydir-data` deliberately, only after confirming the data is disposable.
- Drain nodes one at a time; never drain multiple nodes that run the same workload simultaneously.
- Uncordon promptly after maintenance so the node returns to the scheduling pool.
- Automate the cordon-drain-patch-uncordon sequence for repeatable maintenance windows.
- Run `kubectl get pdb` before any maintenance window to confirm you are not about to violate an availability contract.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Running `kubectl drain` without flags | It hits DaemonSets and bare Pods and hangs forever | Use `--ignore-daemonsets` and `--delete-emptydir-data` |
| Forgetting to uncordon | The node is patched and ready but the scheduler ignores it, wasting capacity | Run `kubectl uncordon <node>` immediately after maintenance |
| Force killing with `--force` | `--force` bypasses the Eviction API and just DELETEs Pods | Reserve `--force` for bare Pods only, never to ignore PDBs |
| Draining without a PDB | Availability contract is unknown, so a drain can take all replicas down | Define PDBs for all critical workloads |
| Draining multiple nodes at once | Draining nodes hosting the same workload simultaneously causes an outage | Drain nodes sequentially, one at a time |

## Troubleshooting

**Symptom: The Hanging Drain**

You run `kubectl drain` and it just hangs forever.

Check PodDisruptionBudgets:

```bash
kubectl get pdb
```

If a PDB requires 4 Pods to be running but only 4 exist, the drain hangs forever waiting for a 5th Pod to appear so it can safely evict one. Solution: temporarily scale up, or verify the PDB is correct.

Check for emptyDir:

```bash
kubectl get pod <name> -o jsonpath='{.spec.volumes[*].emptyDir}'
```

If a Pod uses an emptyDir volume, drain refuses to evict it by default to prevent data loss. Use `--delete-emptydir-data` if the data is disposable.

Check for bare Pods:

```bash
kubectl get pod <name> -o jsonpath='{.metadata.ownerReferences[0].kind}'
```

If a Pod is not managed by a Deployment or ReplicaSet (a "naked" Pod), draining it permanently deletes it. You must use `--force` to bypass this protection.

**Symptom: Pods land back on the node you are draining**

Cause: The node was never cordoned, so the scheduler keeps placing new Pods on it while you drain.

Fix: Always run `kubectl cordon <node>` first, then drain.

## Interview Questions

**Q: What is the difference between cordon and drain?**

A: Cordon stops new Pods from scheduling on a node but leaves existing Pods running. Drain evicts existing Pods so the node can be safely shut down.

**Q: Why do we need to drain a node before rebooting it?**

A: To ensure zero downtime. Draining gracefully evicts the Pods, allowing ReplicaSets to recreate them on healthy nodes before the node goes offline.

**Q: You run `kubectl drain` but it gets stuck and never finishes. What are two common reasons?**

A: 1. It hit a DaemonSet or a Pod with an emptyDir volume; use `--ignore-daemonsets` and `--delete-emptydir-data`. 2. A PodDisruptionBudget is preventing the eviction to ensure high availability.

**Q: What happens to a DaemonSet when you drain a node?**

A: By default, drain refuses to evict it. If you use `--ignore-daemonsets`, drain leaves the DaemonSet Pod running on the node. It is killed when the node reboots, and the DaemonSet controller recreates it when the node comes back online.

**Q: True or False: Cordon affects currently running Pods.**

A: False. Cordon only prevents new Pods from being scheduled.

## Scenario Questions

**Scenario 1:** You need to perform maintenance on a node. Walk through the exact commands.

A: First, `kubectl cordon <node>` to stop new Pods. Then, `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data` to evict workloads. Once drained, perform the maintenance. Finally, `kubectl uncordon <node>` to return it to the pool.

**Scenario 2:** Your app runs 5 replicas and must stay at 4 during maintenance. You drain a node holding 2 replicas. What happens?

A: The drain evicts only 1 Pod (keeping 4 running to satisfy the PDB) and then waits. It will not evict the second Pod until an additional replica exists somewhere in the cluster.

**Scenario 3 (Mini Project - The PDB Protection):**

- Create a Deployment with 3 replicas.
- Create a PodDisruptionBudget with `minAvailable: 3`.
- Try to drain one of the nodes where these Pods are running.
- Observe that the drain hangs or refuses to evict the Pod because it would violate the PDB.
- Delete the PDB and the drain should succeed.

## Quiz

1. What does `kubectl cordon <node>` do?
   - A. Stops all Pods on the node
   - B. Stops new Pods from being scheduled, existing Pods keep running
   - C. Deletes all Pods on the node
   - D. Reboots the node

2. Which flag is required to drain a node that runs DaemonSet Pods?
   - A. `--force`
   - B. `--delete-emptydir-data`
   - C. `--ignore-daemonsets`
   - D. `--evict-daemonsets`

3. What signal does a Pod receive first during a graceful eviction?
   - A. SIGKILL
   - B. SIGTERM
   - C. SIGHUP
   - D. SIGSTOP

4. What is the default `terminationGracePeriodSeconds`?
   - A. 5 seconds
   - B. 15 seconds
   - C. 30 seconds
   - D. 60 seconds

5. Which object limits the number of Pods that can be down during voluntary disruptions?
   - A. ResourceQuota
   - B. LimitRange
   - C. PodDisruptionBudget
   - D. PriorityClass

Answers: 1-B, 2-C, 3-B, 4-C, 5-C.

## Revision

One-minute revision:

- Cordon = no new Pods.
- Drain = evict existing Pods.
- Uncordon = allow new Pods again.
- Drain needs `--ignore-daemonsets` and usually `--delete-emptydir-data`.
- Drain respects PodDisruptionBudgets.
- Graceful termination sends `SIGTERM`, then `SIGKILL` after the grace period (default 30s).

Memory trick:

- **Cordon:** The "Do Not Disturb" sign on a hotel room door. Housekeeping (the Scheduler) will not put new towels in there.
- **Drain:** Asking the current occupants to pack up and move to a new room so the plumber can fix the sink.
- **Uncordon:** Taking the sign off the door so housekeeping can service it again.

Key facts:

- `kubectl cordon <node>` marks a node `Unschedulable`.
- `kubectl drain <node>` evicts Pods so the node can be safely rebooted.
- Drain refuses to evict DaemonSets by default; use `--ignore-daemonsets`.
- Drain refuses to evict bare Pods; use `--force` if you truly want to delete them.
- `kubectl uncordon <node>` makes the node schedulable again.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl cordon <node>` | Stops new Pods from being scheduled |
| `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data` | Safely evicts apps, ignoring system daemons and ephemeral data |
| `kubectl uncordon <node>` | Allows scheduling again |
| `kubectl get pdb` | Lists PodDisruptionBudgets that may block the drain |

## References

- [Kubernetes Documentation: Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)
- [Kubernetes Documentation: PodDisruptionBudgets](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
- [Kubernetes Documentation: Disruptions](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
- [Kubernetes Documentation: Node Conformance and Maintenance](https://kubernetes.io/docs/tasks/administer-cluster/)

## Related Lessons

- [Lesson 3 - Controlling Where Pods Run (Scheduling and Taints)](../02-architecture/lesson-03-worker-node-architecture.md) - how the Kubelet and kube-proxy behave during node maintenance.
- [Lesson 5 - Node Affinity and Pod Anti-Affinity](../02-architecture/lesson-05-node-affinity-and-anti-affinity.md) - how scheduling rules interact with a cordoned node.
- [Lesson 39 - Horizontal Pod Autoscaler](lesson-36-horizontal-pod-autoscaler.md) - why the Cluster Autoscaler recreates patched nodes after drain.
- [Lesson 44 - The SRE Troubleshooting Masterclass](../13-troubleshooting/lesson-41-sre-troubleshooting-masterclass.md) - diagnosing workloads that fail to migrate during a drain.

## Coming Next

The next lesson covers high availability and multi-zone deployments: designing clusters that survive node and zone failures while keeping the control plane and workloads available.
