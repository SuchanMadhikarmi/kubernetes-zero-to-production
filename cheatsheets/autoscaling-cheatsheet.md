---
title: Autoscaling Cheat Sheet
topic: autoscaling
status: Complete
tags: [cheatsheet, autoscaling, hpa, vpa, cluster-autoscaler, resources]
---

# Autoscaling Cheat Sheet

Kubernetes has three autoscalers. They scale different things and are meant to work together.

| Autoscaler | Scales | Trigger |
|-----------|--------|---------|
| HorizontalPodAutoscaler (HPA) | number of Pod replicas | metrics (CPU/memory/custom) |
| VerticalPodAutoscaler (VPA) | Pod CPU/memory requests/limits | observed usage (recommend/recreate) |
| Cluster Autoscaler | number of nodes | unschedulable + pending Pods |

## Horizontal Pod Autoscaler

HPA (version `autoscaling/v2`) uses metrics (default: resource CPU) to scale the Deployment/ReplicaSet. It needs the **Metrics Server**.

```bash
kubectl get --raw /apis/metrics.k8s.io/v1beta1 2>/dev/null   # check metrics API
kubectl top pods -n <ns>                                     # check metrics pipeline
```

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

```bash
kubectl autoscale deployment web --cpu-percent=70 --min=2 --max=10
kubectl get hpa
kubectl describe hpa web-hpa     # look at Metrics, Conditions, Events
kubectl get hpa web-hpa -o yaml
```

Why HPA shows `<unknown>/...%`: the Metrics Server is not installed or unreachable, or the Pod template has no `resources.requests.cpu`/memory. The HPA needs the requests baseline to compute a utilization percentage.

Common tuning with `behavior`:

- `scaleUp` and `scaleDown` stabilization windows and policies prevent thrashing.

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 0
    policies:
    - type: Percent
      value: 100
      periodSeconds: 15
  scaleDown:
    stabilizationWindowSeconds: 300
    policies:
    - type: Minutes
      value: 5
      periodSeconds: 60
```

Reason the HPA does not scale:
- Metric resource missing or no requests set.
- AverageUtilization is relative to `requests`, so set accurate requests.
- Pod count hits `maxReplicas`.
- Metrics Server not reporting.

## Vertical Pod Autoscaler (VPA)

VPA recommends / sets CPU and memory requests based on usage; can recreate pod for resourcing.

```bash
helm install vpa -n kube-system ./hack/vertical-pod-autoscaler
kubectl get crd verticalpodautoscalers.autoscaling.k8s.io
```

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: web-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  updatePolicy:
    updateMode: Auto        # Off (recommend only) | Initial | Recreate
  resourcePolicy:
    containerPolicies:
    - containerName: "*"
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: "2"
        memory: 4Gi
```

`UpdateMode` values: `Off` (only recommend), `Initial` (apply only on creation; use with HPA), `Recreate` (resize by recreating). VPA is often incompatible with HPA on the same resource for the same metric (set `behavior`).

Caution: Do not run VPA and HPA on the same Deployment with the same metric type.

## Cluster Autoscaler

Scales nodes. Needs cloud integration (AWS/GCP/Azure) or a provider of the node group. It removes capacity when Pods cannot schedule and when a node is underutilized and can be drained safely.

```bash
kubectl logs -n kube-system deployment/cluster-autoscaler | grep -i 'filtered out'
kubectl get nodes --show-labels
```

- Place `requests` accurately; underutilized nodes are candidates to remove.
- Useful: `--scale-down-utilization-threshold` (default 0.5) and `--scale-down-unneeded-time`.
- Use `topology.kubernetes.io/zone` preferences for balanced scale.
- Cloud provider controls node groups; on local/kind there is no Cloud.

## Pod Disruption Budget (PDB) + maxUnavailable

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
spec:
  minAvailable: 2          # or maxUnavailable: 1
  selector:
    matchLabels: {app: web}
```

PDBs constrain voluntary disruption (node drain, VPA) so you always keep a minimum. Invasive involuntary evictions and node failures still happen; PDBs are not about that.

## Resource management reminders

- Setting honest `requests` is what makes the HPA useful and the scheduler accurate.
- Min/max autoscale number of replicas fit within the node; set hard limits.
- Over-supplying `limits` thins cluster density.

## Quick autoscaling command pass

```bash
kubectl autoscale deployment web --cpu-percent=50 --min=2 --max=10
kubectl get hpa -A
kubectl describe hpa web-hpa
kubectl top nodes
kubectl get deployment web -o wide   # watch DESIRED/CURRENT
# audit node count
kubectl get nodes
```