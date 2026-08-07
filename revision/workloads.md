---
title: Revision - Workloads
module: 03 Workloads
status: Complete
tags: [revision, workloads, pod, deployment, statefulset, daemonset, job]
---

# Revision - Workloads

## Core Ideas

- **Pod**: smallest schedulable unit; one or more containers sharing a network namespace, IP, and volumes.
- **ReplicaSet**: ensures N identical Pods. Usually managed by a Deployment.
- **Deployment**: manages ReplicaSets; enables rolling updates, rollback, scaling, pause. Default for stateless apps.
- **StatefulSet**: stable identity, stable DNS, ordered scaling; needs a headless Service and `volumeClaimTemplates`.
- **DaemonSet**: exactly one Pod per node (agents, exporters, CNI).
- **Job / CronJob**: run-to-completion workloads; CronJobs add a cron schedule.

## Deployment Essentials

```yaml
strategy:
  type: RollingUpdate        # or Recreate
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 1
```

```bash
kubectl set image deployment/web web=nginx:1.26
kubectl rollout status / undo / history / restart deployment/web
kubectl scale deployment/web --replicas=5
kubectl rollout undo deployment/web --to-revision=2
```

Revision history retention: `revisionHistoryLimit` (default 10).

## StatefulSet Essentials

```yaml
spec:
  serviceName: db            # headless Service
  volumeClaimTemplates:
  - metadata: {name: data}
    spec:
      accessModes: [ReadWriteOnce]
      resources: {requests: {storage: 10Gi}}
```

Stable DNS: `db-0.db.default.svc.cluster.local`. Ordered creation/termination by default.

## Probes (the lifesavers)

| Probe | Failure means |
|-------|---------------|
| `startupProbe` | gate before liveness for slow starts |
| `livenessProbe` | restart the container |
| `readinessProbe` | remove from Service Endpoints (no restart) |

## Workload Choice

| Need | Use |
|------|-----|
| Stateless API | Deployment |
| Database / cache / queue | StatefulSet |
| One agent per node | DaemonSet |
| Batch / scheduled | Job / CronJob |
| Precondition before main | initContainers |

## Pod Lifecycle

`Pending -> Running -> Succeeded`; failures: `CrashLoopBackOff`, `ImagePullBackOff`, `Evicted`, `Terminating`.

## Related Lessons

- [Lesson 10 - Pods, ReplicaSets, and Deployments](../docs/03-workloads/lesson-10-pods-replicasets-and-deployments.md)
- [Lesson 12 - Deployments and Rollout Strategies](../docs/03-workloads/lesson-12-deployments-and-rollout-strategies.md)
- [Lesson 13 - StatefulSets](../docs/03-workloads/lesson-13-statefulsets.md)
- [Lesson 14 - DaemonSets](../docs/03-workloads/lesson-14-daemonsets.md)
- [Lesson 15 - Jobs and CronJobs](../docs/03-workloads/lesson-15-jobs-and-cronjobs.md)
- [Lesson 22 - Init Containers](../docs/03-workloads/lesson-22-init-containers.md)
- [Lesson 38 - Advanced Stateful Workloads](../docs/03-workloads/lesson-38-advanced-stateful-workloads.md)

## Related Material

- [Workload Cheat Sheet](../cheatsheets/workload-cheatsheet.md)
- [Interview - Workloads](../interview/workloads.md)

[Back to Revision Index](README.md)