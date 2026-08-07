---
title: Revision - Architecture
module: 02 Architecture
status: Complete
tags: [revision, architecture, control-plane, nodes, kubelet, scheduler, API server]
---

# Revision - Architecture

## Core Ideas

- A Kubernetes cluster has a **control plane** (brain) and **worker nodes** (workers).
- Control plane components: **API Server**, **etcd**, **scheduler**, **controller-manager**, and the cloud-controller-manager for cloud integration.
- Worker node components: **kubelet**, container runtime (**containerd**), **kube-proxy**, and the **CNI** pod network plugin.

## Control Plane

| Component | Role |
|-----------|------|
| API Server | Front door; authenticates, authorizes, runs admission, serves the API. Stateless; the only thing that talks to etcd. |
| etcd | Distributed key-value store; the single source of desired state. Needs quorum (odd number of members). |
| Scheduler | Watches for unscheduled Pods; binds them to nodes based on filtering and scoring. |
| Controller-manager | Runs controllers (Node, ReplicaSet, Endpoints, etc.) that reconcile state. |

## Worker Node

| Component | Role |
|-----------|------|
| kubelet | Node agent; registers with API Server, starts/oversees pods, runs probes, reports status. |
| container runtime | Runs containers via the CRI (containerd is default). |
| kube-proxy | Programs iptables/ipvs to route Service ClusterIP traffic to Pods. |
| POD CNI | Provides Pod networking (Calico/Cilium/Flannel). |

## A Request Through the Cluster (60 seconds)

```text
kubectl -> API Server -> Auth (RBAC) -> Admission (Kyverno) -> etcd
  -> Scheduler picks node -> kubelet -> CRI (containerd) -> runc -> container
User -> Cloud LB -> Ingress -> Service (kube-proxy DNAT) -> Pod (Istio sidecar) -> container
```

## Key Concepts

- **Declarative** desired state stored in etcd; controllers make actual state match desired.
- **Node controller** marks a node `NotReady` after `node-monitor-grace-period` (default 40s); Pods are evicted after `pod-eviction-timeout` (default 5m).
- **Pod** failure: the ReplicaSet controller reschedules; the EndpointsController removes dead Pod IPs.

## Related Lessons

- [Lesson 07 - Worker Node Architecture](../docs/02-architecture/lesson-07-worker-node-architecture.md)
- [Lesson 17 - Pod Priority and Preemption](../docs/02-architecture/lesson-17-pod-priority-and-preemption.md)
- [Lesson 25 - Node Affinity and Anti-Affinity](../docs/02-architecture/lesson-25-node-affinity-and-anti-affinity.md)

## Related Material

- [Revision - Workloads](workloads.md)
- [Interview - Architecture](../interview/architecture.md)

[Back to Revision Index](README.md)