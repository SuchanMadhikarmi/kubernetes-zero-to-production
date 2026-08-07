---
title: Revision - Production
module: 12 Production
status: Complete
tags: [revision, production, autoscaling, hpa, velero, upgrades, multi-cluster]
---

# Revision - Production

## Core Ideas

- Production = availability, capacity, automation, and recovery.
- **HPA** scales Pod replicas on metrics; needs the Metrics Server and `requests`.
- **Velero** backs up cluster objects + PVs and restores them.
- **Cluster upgrades** use drain/cordon/uncordon to move workloads safely.
- **Multi-cluster** adds isolation, failover, and cost control.
- **Progressive Delivery** (Argo Rollouts) gates releases with canary + analysis.

## HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: web}
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource: {name: cpu, target: {type: Utilization, averageUtilization: 70}}
```

`<unknown>/...%` in HPA status: Metrics Server down or missing `resources.requests`.

## Node Maintenance

```bash
kubectl cordon <node>        # no new pods
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl uncordon <node>
kubectl get nodes
```

## Production practices

- Use **PodDisruptionBudgets** to protect availability during voluntary drains.
- Back up etcd and use Velero for cluster disaster recovery.
- Add **readiness/liveness probes** and **resource limits** to every workload.
- Roll out changes gradually with Argo Rollouts; keep `kubectl apply` out of prod.

## Related Lessons

- [Lesson 24 - Building a 3-Tier Web Application](../docs/12-production/lesson-24-building-a-3-tier-web-application.md)
- [Lesson 26 - Horizontal Pod Autoscaler](../docs/12-production/lesson-26-horizontal-pod-autoscaler.md)
- [Lesson 28 - Cluster Upgrades and Maintenance](../docs/12-production/lesson-28-cluster-upgrades-and-maintenance.md)
- [Lesson 35 - Backups and Disaster Recovery with Velero](../docs/12-production/lesson-35-backups-and-disaster-recovery-with-velero.md)
- [Lesson 36 - Multi-Cluster Kubernetes](../docs/12-production/lesson-36-multi-cluster-kubernetes.md)
- [Lesson 46 - Progressive Delivery (Argo Rollouts)](../docs/12-production/lesson-46-progressive-delivery-argo-rollouts.md)

## Related Material

- [Autoscaling Cheat Sheet](../cheatsheets/autoscaling-cheatsheet.md)
- [GitOps Cheat Sheet](../cheatsheets/gitops-cheatsheet.md)
- [Interview - Production](../interview/production.md)

[Back to Revision Index](README.md)