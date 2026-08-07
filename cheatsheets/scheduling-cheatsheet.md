---
title: Scheduling Cheat Sheet
topic: scheduling
status: Complete
tags: [cheatsheet, scheduling, taints, tolerations, affinity, node-selector]
---

# Scheduling Cheat Sheet

The kube-scheduler filters candidate nodes, then scores them, then binds the Pod. This sheet covers how to steer Pods to nodes.

## Node Selector (simple required match)

```yaml
spec:
  nodeSelector:
    disktype: ssd
```

Matches node label `disktype=ssd`. Simple, equality only.

```bash
kubectl label node <node> disktype=ssd
kubectl get nodes --show-labels
```

## Taints and Tolerations

Taints repel Pods from a node unless the Pod has a matching toleration. Taints live on nodes; tolerations on Pods.

```bash
kubectl taint nodes <node> key=value:NoSchedule
kubectl taint nodes <node> key=value:NoExecute
kubectl taint nodes <node> key=value:NoSchedule-   # remove taint (trailing -)
kubectl describe node <node> | grep -i taints
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tolerant-pod
spec:
  tolerations:
  - key: "key"
    operator: "Equal"      # or "Exists"
    value: "value"
    effect: "NoSchedule"   # NoSchedule | PreferNoSchedule | NoExecute
  containers:
  - name: app
    image: nginx
```

Toleration modes:

| Effect | Behavior |
|--------|----------|
| `NoSchedule` | New Pods without toleration are not scheduled. Existing stay if already running (unless NoExecute). |
| `PreferNoSchedule` | Soft preference: node tries to avoid but excludes only by scoring. |
| `NoExecute` | Evict Pods already running that lack toleration. |

Toleration `operator: Exists` matches any value for the key. Omitting toleration removes it. Events are useful to see why.

```yaml
# Match all taints (rare, use sparingly)
tolerations:
- operator: Exists
```

## Node Affinity

Affinity (node or pod) is expressed as `preferredDuringSchedulingIgnoredDuringExecution` (soft, weight) or `requiredDuringSchedulingIgnoredDuringExecution` (hard).

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: topology.kubernetes.io/zone
            operator: In
            values: [us-east-1a]
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: disktype
            operator: In
            values: [ssd]
```

Operators: `In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt`, `Lt`.

## Pod Affinity / Anti-Affinity

```yaml
spec:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app: web
          topologyKey: kubernetes.io/hostname
```

Combined with `topologyKey`:

| topologyKey | Spread over |
|-------------|-------------|
| `kubernetes.io/hostname` | nodes (copy across nodes) |
| `topology.kubernetes.io/zone` | availability zones |
| `topology.kubernetes.io/region` | regions |

Use anti-affinity to spread replicas of a stateful/critical app across nodes or zones. Hard anti-affinity can make scheduling impossible (pods fewer than nodes).

## Topology Spread Constraints

```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule   # or ScheduleAnyway (soft)
    labelSelector:
      matchLabels:
        app: web
```

Spread replicas evenly, even above a level in different zones.

## Operator: Node Name / taint on node setup

```yaml
spec:
  nodeName: worker-1     # hard pin; bypasses scheduler (discouraged in prod)
```

## Common patterns and quick checks

```bash
kubectl get pods -o wide          # see node each pod is on
kubectl describe pod <name> | grep -A5 Events    # FailedScheduling events
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

Debug: if a Pod is `Pending` with `FailedScheduling`, add the events string to the description; it tells you the real constraint (affinity, resource, taint, nodePort).

## kubectl top vs Scheduling (resource context)

The scheduler can only place a Pod on a node that has enough allocatable capacity for the Pod's `requests`. Essential context, not a scheduling command:

```bash
kubectl describe node <node> | grep -A10 Allocated resources
```