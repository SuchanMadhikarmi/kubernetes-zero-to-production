---
title: Troubleshooting Cheat Sheet
topic: troubleshooting
status: Complete
tags: [cheatsheet, troubleshooting, debugging, diagnosis, logs]
---

# Troubleshooting Cheat Sheet

Follow the funnel: identify the layer (cluster, node, pod, container, network) and probe from cheap and observable data inward.

```text
Cluster level:  api-server, scheduler, controller-manager, etcd
Node level:     kubelet, container runtime, kube-proxy, CNI
Workload level: Pod status, ReplicaSet, Deployment, StatefulSet
Container level: logs, exec, resource limits, image
Network level:  Service endpoints, DNS, Ingress, NetworkPolicy
```

## Start with these

```bash
kubectl get nodes                        # all Ready?
kubectl get pods -A                      # any CrashLoop/ImagePullBackOff/Pending
kubectl get events -A --sort-by='.lastTimestamp'
kubectl describe node <node>
kubectl cluster-info
```

## Pod debugging

```bash
kubectl get pod <name> -o wide
kubectl describe pod <name>              # Conditions + Events (critical)
kubectl logs <name> -f
kubectl logs <name> --previous           # crashed instance logs
kubectl logs -l app=<app> --tail=200
kubectl exec -it <name> -- sh
kubectl exec <name> -- ls /app
```

Pod status cheat:

| Status | Meaning | First check |
|--------|---------|-------------|
| `Pending` | not scheduled | `kubectl describe pod` Events (FailedScheduling), node capacity, taints |
| `ContainerCreating` | runtime pulling/creating | image availability, registry access, runtime errors |
| `Running` | running | ready probes, logs |
| `CrashLoopBackOff` | keeps crashing/restarting | `kubectl logs --previous`, OOMKilled, liveness |
| `ImagePullBackOff` | image pull failed | image tag typo, private registry creds, tag policy |
| `Terminating` | stuck deletion | finalizers, PDB, node gone |
| `Evicted` | evicted for resources/disk | node pressure, requests |

Describe pod output to inspect:

```bash
kubectl describe pod <name> | grep -A10 Conditions
kubectl describe pod <name> | grep -A5 Events
kubectl get pod <name> -o jsonpath='{.status.containerStatuses[0].state}'
```

## Container-level debugging

```bash
kubectl logs <pod> -c <container>          # multi-container
kubectl logs <pod> --all-containers
kubectl exec -it <pod> -c <container> -- sh
kubectl debug <pod> -it --image=busybox -- sh    # temporary sidecar/debug container
kubectl debug node/<node> -it --image=busybox    # node-level debug pod
kubectl cp <pod>:/var/log/app.log ./app.log
```

Check resource pressure:

```bash
kubectl top node
kubectl top pod
kubectl describe node <node> | grep -A12 'Allocated resources'
kubectl get events | grep -i 'evict\|oom'
```

## CrashLoopBackOff workflow

1. `kubectl logs <pod> --previous` - the last crash log (started fine on fresh restart).
2. `kubectl describe pod <name>` - exit codes, restart counts, OOM.
3. Exec into the pod and run the command manually if possible.
4. Check image/liveness/supportability; fix the underlying cause (code, config, resource).

## Networking debugging

```bash
kubectl get endpoints -A               # selector/probe issues -> empty
kubectl get svc -A -o wide
kubectl describe svc <name>
kubectl get pods -l app=<app> -o wide
kubectl exec -it <util> -- nslookup <svc>.<ns>.svc.cluster.local
kubectl exec -it <util> -- curl -v http://<svc>:<port>
kubectl exec -it <util> -- nc -vz <pod-ip> <port>
kubectl get networkpolicies -A
kubectl get ingress -A
```

Diagnostic flow for "service down":

1. `kubectl get endpoints <svc>` empty? selector labels mismatch or Pods not Ready.
2. Pods Ready but endpoints exist - test Pod IP directly.
3. DNS resolves? CoreDNS healthy? `kubectl rollout restart -n kube-system deploy/coredns`.
4. Ingress -> Service -> Pod path; check ingress controller logs.

## Cluster-level debugging

```bash
kubectl get nodes -o wide
kubectl describe node <name>
kubectl cordon <node> && kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl uncordon <node>
kubectl get componentstatuses           # control plane components (legacy API)
journalctl -u kubelet                    # on node (if access)
kubectl get --raw /healthz
kubectl get csr                            # pending node cert requests
kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'
```

Node NotReady: check kubelet, container runtime (containerd), CNI, disk pressure. `kubectl get events -A` often shows the cause.

## Storage debugging

```bash
kubectl get pv,pvc -A -o wide
kubectl describe pvc <name>              # Pending: class/provisioner/capacity
kubectl describe pv <name>
kubectl get sc -A
kubectl get events -A | grep -i volume
```

PVC stuck in `Terminating`: check `kubernetes.io/pvc-protection` finalizer (still used by a Pod), or the PV ReclaimPolicy/cloud disk stuck. Removing the finalizer manually is a last resort:

```bash
kubectl patch pvc <name> -p '{"metadata":{"finalizers":null}}'
```

## Config / quota debugging

```bash
kubectl describe pod <name> | grep -i 'limitrange\|quota\|resource'
kubectl get quota -A
kubectl describe quota
kubectl get events -A | grep -i 'quota\|limitrange'
kubectl get secrets,configmaps -n <ns>
```

## HPA debugging

```bash
kubectl get --raw /apis/metrics.k8s.io/v1beta1
kubectl top pods
kubectl describe hpa <name>
kubectl get hpa -o yaml
```

HPA `<unknown>`: Metrics Server down, or no `resources.requests` on the Pod template.

## RBAC / auth debugging

```bash
kubectl auth can-i --list
kubectl auth can-i get pods --as=system:serviceaccount:ns:sa
kubectl get roles,rolebindings,clusterroles,clusterrolebindings -A
kubectl describe rolebinding <name>
kubectl auth can-i create deployments
```

## Logs and events summary

```bash
kubectl get events -A -w
kubectl logs --prefix -l app=web --tail=50
kubectl logs -f <pod> -c <container>
kubectl describe pod | grep -i 'message\|reason'
```

## Golden troubleshooting mindset

- Always read Events first (they carry reasons and messages).
- `logs --previous` for the crash, `describe` for status and events, `exec` for live inspection.
- Work outside-in: Service -> endpoints -> Pod -> container -> code.
- Collect evidence before fixing: `get`, `describe`, `logs`, `top`, `events`.
