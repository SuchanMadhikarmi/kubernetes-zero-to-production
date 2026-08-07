---
title: Interview - Workloads
module: 03 Workloads
status: Complete
tags: [interview, workloads, pod, deployment, statefulset, daemonset, job]
---

# Interview - Workloads

## Beginner

**Q: What is the difference between a Pod and a container?**

A: A container is a Linux process isolated by namespaces and cgroups. A Pod is a Kubernetes abstraction that wraps one or more containers sharing a network IP and volumes.

**Q: Do I need a Deployment for a simple one-off Pod?**

A: Not usually. Use a Pod for a quick test, or a Job for a run-to-completion task. Deployments are for apps that should stay running and be scaled.

**Q: What is an init container?**

A: A container that runs to completion before the main container starts, often for setup (wait for dependencies, populate config).

## Intermediate

**Q: How does a rolling update differ from Recreate?**

A: RollingUpdate scales up the new ReplicaSet while scaling down the old one, respecting `maxUnavailable` and `maxSurge`, so there is minimal downtime. Recreate kills all old Pods first, causing downtime but guaranteeing only one version exists.

**Q: When would you choose a StatefulSet over a Deployment?**

A: When the workload needs stable network identity, stable storage per replica (databases, caches, queues), or ordered deployment/scaling. It relies on a headless Service and `volumeClaimTemplates`.

**Q: How does readiness differ from liveness?**

A: A failing readiness probe removes the Pod from Service endpoints (no restart). A failing liveness probe restarts the container.

## Scenario

Q: A Deployment shows all Pods `CrashLoopBackOff`. How do you debug?

A: Read the crash log with `kubectl logs <pod> --previous`, describe the Pod for exit codes/OOM, exec into it if runnable, and check the image, liveness probe, and resource limits.

## True/False

- Deployment selector is immutable after creation. (True)
- A failing readiness probe restarts the container. (False - it removes the Pod from endpoints.)

## Related

- [Revision - Workloads](../revision/workloads.md)
- [Lesson 13 - StatefulSets](../docs/03-workloads/lesson-13-statefulsets.md)

[Back to Interview Index](README.md)