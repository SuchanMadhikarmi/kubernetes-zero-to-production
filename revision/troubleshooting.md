---
title: Revision - Troubleshooting
module: 13 Troubleshooting
status: Complete
tags: [revision, troubleshooting, debugging, logs, eviction, diagnosis]
---

# Revision - Troubleshooting

## The Funnel

Work outside-in: Service -> Endpoints -> Pod -> Container -> code.

```text
Cluster:  api-server, scheduler, controller-manager, etcd
Node:     kubelet, runtime (containerd), kube-proxy, CNI
Workload: Pod/ReplicaSet/Deployment status
Container: logs, exec, resources
Network:  Service endpoints, DNS, Ingress, NetworkPolicy
```

## Always Start With

```bash
kubectl get nodes
kubectl get pods -A
kubectl get events -A --sort-by='.lastTimestamp'
kubectl describe pod <name>
kubectl logs <pod> --previous
kubectl top nodes / pods
```

## Pod Status Cheat

| Status | Likely cause |
|--------|--------------|
| Pending | scheduling (FailedScheduling), capacity, taints/affinity |
| CrashLoopBackOff | app crashes / liveness killing / OOM |
| ImagePullBackOff | bad tag, private registry creds |
| Evicted | node pressure / resource pressure |
| Terminating (stuck) | finalizers, PDB, node gone |
| Unknown | node unreachable |

## Common Fixes

- `kubectl logs --previous` reads the pre-crash logs (the stack trace or `OOMKilled`).
- Empty Service `endpoints` = selector mismatch or Pods not Ready.
- PVC stuck `Terminating`: remove the `kubernetes.io/pvc-protection` finalizer as a last resort.
- Node NotReady: check kubelet, containerd, CNI, disk pressure; drain/uncordon.

## Related Lessons

- [Lesson 27 - SRE Troubleshooting Masterclass](../docs/13-troubleshooting/lesson-27-sre-troubleshooting-masterclass.md)
- [Lesson 29 - Node Pressure and Evictions](../docs/13-troubleshooting/lesson-29-node-pressure-and-evictions.md)

## Related Material

- [Troubleshooting Cheat Sheet](../cheatsheets/troubleshooting-cheatsheet.md)
- [Interview - Troubleshooting](../interview/troubleshooting.md)

[Back to Revision Index](README.md)