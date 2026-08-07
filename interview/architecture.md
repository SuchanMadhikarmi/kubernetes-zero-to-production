---
title: Interview - Architecture
module: 02 Architecture
status: Complete
tags: [interview, architecture, control-plane, nodes, kubelet, scheduler]
---

# Interview - Architecture

## Beginner

**Q: What does the API Server do?**

A: It is the front door to the cluster. It authenticates and authorizes requests, runs admission control, and persists objects to etcd. It is the only component that talks directly to etcd.

**Q: What does the scheduler do?**

A: It watches for Pods with no node assigned and binds them to nodes by filtering (capacity, taints, affinity) then scoring candidates.

## Intermediate

**Q: What happens when you type `kubectl run nginx --image=nginx`?**

A: kubectl POSTs a Pod manifest to the API Server; the API Server authenticates and authorizes (RBAC), runs admission controllers, and stores the Pod in etcd. The scheduler sees the Pending Pod, picks a node, and binds it. The kubelet on that node sees the bound Pod, asks the CRI (containerd) to pull the image and start the container via runc, then reports status back.

**Q: A node goes offline. What happens to its Pods?**

A: The node controller marks the node NotReady after the grace period (default 40s for `node-monitor-grace-period`). Pods on it are evicted after `pod-eviction-timeout` (default 5m). The ReplicaSet controller schedules replacement Pods on healthy nodes, and the EndpointsController removes the dead Pod IPs from Services.

**Q: What is the role of kube-proxy?**

A: It maintains network rules (iptables/ipvs) that implement Services, translating ClusterIP:port into backing Pod IPs (DNAT).

## Scenario

Q: The control plane is down and etcd lost quorum. What do you do?

A: Restore etcd from the latest backup to one member, let it form quorum again, then restart the remaining control plane components. Keep etcd backups current and test restores regularly.

## Related

- [Revision - Architecture](../revision/architecture.md)
- [Lesson 42 - etcd Backup and Restore](../docs/14-certifications/lesson-42-etcd-backup-and-restore.md)

[Back to Interview Index](README.md)