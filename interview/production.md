---
title: Interview - Production
module: 12 Production
status: Complete
tags: [interview, production, hpa, node-maintenance, velero, multi-cluster]
---

# Interview - Production

## Beginner

**Q: What does a HorizontalPodAutoscaler do?**

A: It scales the number of replicas of a Deployment/ReplicaSet based on metrics (typically CPU) so the app handles load without manual scaling.

**Q: What is a PodDisruptionBudget?**

A: A policy that limits how many Pods of an app can be voluntarily disrupted at once (via node drains, upgrades, or VPA), protecting availability.

## Intermediate

**Q: How do you safely upgrade a node?**

A: Cordon it so no new Pods schedule, drain it (`kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`) so Pods move elsewhere, upgrade/reboot, then uncordon. PDBs protect critical apps during the drain.

**Q: What does Velero back up?**

A: Kubernetes objects plus one or more volumes (PVC/PV), stored in an object store, and can restore them to a cluster or migrate them.

**Q: When would you need an HPA?**

A: When load varies: you want to scale replicas out automatically for bursts and back down for quiet periods. The HPA uses the Pod's `resources.requests` baseline to compute a utilization percentage, so an accurate baseline is required.

## Scenario

Q: A node reports DiskPressure and Pods are being evicted. What do you do?

A: Identify what fills the disk (container logs, images, emptyDir) with `kubectl describe node` and node events, delete unneeded images, cap log storage, shrink volumes, and increase disk capacity. Cordon & evict cleanly before taking the node offline if needed.

## Related

- [Revision - Production](../revision/production.md)
- [Lesson 36 - Horizontal Pod Autoscaler](../docs/12-production/lesson-36-horizontal-pod-autoscaler.md)
- [Lesson 38 - Backups and Disaster Recovery with Velero](../docs/12-production/lesson-38-backups-and-disaster-recovery-with-velero.md)

[Back to Interview Index](README.md)