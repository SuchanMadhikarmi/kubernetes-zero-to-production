---
title: Lab 37 - Cluster Upgrades and Maintenance
lesson: 37
module: 12 Production
tags: [kubernetes, upgrades, maintenance, cordon, drain, kubeadm]
---

# Lab 37 - Cluster Upgrades and Maintenance

## Objective

In this lab you will safely take a node out of the cluster for maintenance, migrate workload off of it, restore it, and walk through the complete kubeadm upgrade flow. You will demonstrate the cordon, drain, uncordon cycle and understand how a real cluster upgrade sequences the control plane and worker nodes.

## Prerequisites

- A running kind cluster, ideally multi-node with 2 worker nodes (`kind-worker` and `kind-worker2`)
- kubectl installed and configured with the correct context
- Completion of Lesson 37 on cordon, drain, and PodDisruptionBudgets

## Pre-Lab Checklist

- [ ] kind cluster running and `kubectl get nodes` shows all nodes `Ready`
- [ ] Decide which node you will patch (for example `kind-worker`)
- [ ] Confirm no production traffic is running on the lab cluster

---

## Step 1: Deploy an App

Deploy a scaled workload so there is something to migrate:

```bash
kubectl create deployment web-app --image=nginx:alpine --replicas=3
```

Confirm the Pods are running and note which node each Pod lands on:

```bash
kubectl get pods -o wide
```

Expected output shows 3 `web-app` Pods in `Running` status spread across the nodes, for example `kind-worker` and `kind-worker2`.

## Step 2: Cordon the Node

Pretend `kind-worker` needs a Linux security patch. Mark it so it stops accepting new Pods:

```bash
kubectl cordon kind-worker
```

Expected output:

```text
node/kind-worker cordoned
```

Verify the node status:

```bash
kubectl get nodes
```

Expected output shows `kind-worker` as `Ready,SchedulingDisabled`. The node is still `Ready`; it simply will not accept new Pods. Existing Pods keep running.

## Step 3: Attempt a Raw Drain (The Protection)

Try to evict the Pods without any flags:

```bash
kubectl drain kind-worker
```

The command fails with an error because Kubernetes refuses to evict certain Pod types by default. The exact error text depends on your workloads, but it will list unmanaged Pods, DaemonSet Pods, or Pods using emptyDir volumes.

Note: The error deliberately refuses to evict these Pods and instructs you to add `--ignore-daemonsets` and `--delete-emptydir-data` if you are sure.

Examine what lives on the node to understand the protection:

```bash
kubectl get pods -o wide --all-namespaces
```

**Your Task:**

1. Did the raw drain succeed, or did it error out?
2. Which two Pod types is Kubernetes protecting by refusing to evict them?
3. Why does Kubernetes protect these Pods from eviction?

## Step 4: Drain the Node with the Correct Flags

For a normal maintenance window we deliberately bypass the protections because DaemonSet Pods (monitoring, logging, networking agents) are recreated on reboot and any emptyDir data on this node is disposable.

```bash
kubectl drain kind-worker --ignore-daemonsets --delete-emptydir-data
```

Run the Drain using the Eviction API. The Pods are evicted gracefully and the ReplicaSet recreates them on `kind-worker2`. Verify:

```bash
kubectl get pods -o wide
kubectl get nodes
```

**Your Task:**

1. Did the drain command succeed this time?
2. Look at the `NODE` column. Did all `web-app` Pods move to `kind-worker2`?
3. What is the status of `kind-worker` now?

## Step 5: Perform the Node Maintenance

The node is now empty of user workloads, so you can patch your OS or replace hardware. In a local kind or minikube environment this is simulated by simply letting the node sit cordoned and drained.

Since a real OS reboot is outside the scope of the lab, you can simulate the maintenance window by inspecting the node and confirming it has no schedulable workload:

```bash
kubectl describe node kind-worker
```

Scroll to `Taints` and `Non-terminated Pods`. Confirmed node should show the maintenance taint and no user Pods.

## Step 6: Uncordon and Return the Node to the Pool

The patch is applied and the node is ready to accept workload again:

```bash
kubectl uncordon kind-worker
```

Expected output:

```text
node/kind-worker uncordoned
```

Verify the node is schedulable again:

```bash
kubectl get nodes
```

Expected output shows `kind-worker` as `Ready` with no `SchedulingDisabled` marker.

## Step 7: The kubeadm Upgrade Flow (Local Simulation)

A real control plane upgrade cannot run in a kind or minikube environment, which use single-node control planes that do not run the `kubeadm` upgrade tool directly. These commands are shown for reference so you understand the production flow. The sequence always upgrades the control plane first, then the workers.

Check the current Kubernetes version:

```bash
kubectl get nodes -o wide
```

For a reference-based [UPGRADE_TARGET], a platform-node upgrade proceeds through these three stages:

Stage 1, Update the kubeadm binary to the target version:

```text
apt-get update && apt-get install -y kubeadm=UPGRADE_TARGET
```

Stage 2, Run the kubeadm upgrade plan and execute it on the control plane:

```text
kubeadm upgrade plan
kubeadm upgrade apply UPGRADE_TARGET
```

Stage 3, Drain, upgrade kubelet and kubectl, then uncordon on each worker node:

```text
kubectl drain kind-worker --ignore-daemonsets
apt-get update && apt-get install -y kubelet=UPGRADE_TARGET kubectl=UPGRADE_TARGET
systemctl restart kubelet
kubectl uncordon kind-worker
```

Your Task (conceptual):

1. Why must you enter the control plane before the worker nodes?
2. Which command performs each of the three stages: bring-down, package upgrade, bring-up?
3. What is the equivalent of cordon in the worker upgrade flow above?

## Step 8: Cleanup

Remove the deployment created at the start:

```bash
kubectl delete deployment web-app
```

Confirm your cluster is back to its pre-lab state:

```bash
kubectl get nodes
kubectl get pods
```

---

## Lab Questions

1. What is the difference between cordon and drain?
2. Why does drain fail unless you pass `--ignore-daemonsets` and `--delete-emptydir-data`?
3. In the kubeadm flow, why is the control plane upgraded before the worker nodes?
4. What would happen if you forgot to run uncordon after maintenance completed?

---

## Expected Results

After completing this lab:

- You can cordon, drain, and uncordon a node
- You understand the default eviction protections
- You can walk through the kubeadm control plane and worker upgrade sequence
- You know why PodDisruptionBudgets must be checked before draining

---

## Key Commands Reference

| Command | Purpose |
|---------|---------|
| `kubectl cordon <node>` | Stop new Pods from scheduling on a node |
| `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data` | Evict workloads so the node can be maintained |
| `kubectl uncordon <node>` | Allow scheduling again after maintenance |
| `kubectl get nodes` | Show scheduling status of all nodes |
| `kubeadm upgrade plan` | Preview the target cluster upgrade |
| `kubeadm upgrade apply <version>` | Apply the upgrade to the control plane |

---

## Next

- Return to the [Lesson 37 file](../docs/12-production/lesson-37-cluster-upgrades-and-maintenance.md) to review cordon, drain, and PodDisruptionBudget concepts
- Try the Mini Project: define a PodDisruptionBudget with `minAvailable: 3` and observe a drain holding at the PDB
- Proceed to the next lesson to learn about high availability and multi-zone deployments