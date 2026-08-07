---
title: Revision - Architecture
module: 02 Architecture
status: Complete
tags: [revision, architecture, control-plane, nodes, kubelet, scheduler, API server]
---

# Revision - Architecture

## 1. The Mental Model

Think of a Kubernetes cluster as a small company.

- The **control plane** (the management office) makes decisions. It decides what should run, where it should run, and it constantly checks that the cluster matches your wishes.
- The **worker nodes** (the factory floor) do the actual work. Each worker runs your containers.
- Deep in the office is a **shared ledger** (etcd) that records, in writing, exactly what the "desired state" of the whole company is: which apps should exist, how many copies, and what they should look like.

The entire system runs on one simple and elegant idea: **you declare the desired state, and Kubernetes keeps reconciling the actual state until it matches.** You never tell Kubernetes step by step what to do; you describe the end result it should guarantee. Controllers are the clerks who constantly compare the ledger to reality and take corrective action when the two differ.

## 2. Core Concepts

### Control Plane Components

| Component | What it is | How it works | Why it matters |
|-----------|-----------|--------------|----------------|
| **kube-apiserver** | The front door of the cluster and the only component every other component talks to. | It authenticates you (are you who you say you are), authorizes you (are you allowed to do this), runs admission controllers (validating/mutating plugins), and serves the REST API. It is stateless and is the **only** component that reads and writes to etcd. | Every command, watch, and update passes through it. It is the single gateway, which is what makes centralized security and access control possible. |
| **etcd** | A distributed key-value store that holds the cluster's desired state and configuration. | It keeps multiple copies of the data across its members to survive failures. It needs a **quorum** (a majority of an odd number of members) to make writes, which is why production clusters run an odd number (3, 5, 7) of etcd nodes. | It is the "single source of truth." If etcd is lost, the cluster forgets everything it was supposed to run, so backups and quorum are critical. |
| **kube-scheduler** | The component that decides which node each unscheduled Pod should run on. | It watches the API server for Pods that have no `nodeName` assigned. For each one it runs a two-phase algorithm: **Filtering** (drop nodes that do not fit: not enough CPU/RAM, missing required labels, untolerated taints) then **scoring** (rank remaining nodes, e.g. least requested resources, preferred affinity) and then binds the Pod by writing `spec.nodeName`. | Every Pod's placement, from simple to complex (affinity, priority), goes through it. If it is misconfigured, Pods never reach workers. |
| **kube-controller-manager** | A set of **controller loops** that reconcile actual state with desired state. | Each controller (Node, ReplicaSet, Endpoints, Deployment, etc.) continuously watches the API Server, notices the difference between desired and actual, and makes small corrections until they match. | This is the "self-healing" brain. A dead Pod gets recreated by the ReplicaSet controller; dead Pod IPs get removed by the Endpoints controller. |
| **cloud-controller-manager** | The control plane component that bridges Kubernetes to a specific cloud provider. | It runs cloud-specific controllers (node lifecycle, load balancers, routes). It lets the rest of the control plane stay cloud-agnostic. | In managed Kubernetes and on-demand cloud load-balancer revisions it automates cloud resources. Missing in bare-metal/kind clusters. |

### Worker Node Components

| Component | What it is | How it works | Why it matters |
|-----------|-----------|--------------|----------------|
| **kubelet** | The node agent running on every worker node. | It registers the node with the API Server, watches for Pods assigned to its node, and starts/oversees the containers. It runs liveness/readiness/startup probes and continuously reports node and Pod status back to the API Server. | It is the primary worker-side agent. Without it no containers start and no health data reaches the control plane. |
| **container runtime** | The software that actually runs the containers (default: `containerd`), via the CRI (Container Runtime Interface). | It takes the image the kubelet requests, runs it, manages the container lifecycle, and reports status to the kubelet. | It is the low-level engine. The kubelet talks to it, never directly to the container. |
| **kube-proxy** | A network agent that runs per node. | It programs `iptables` (or `ipvs`) rules so that traffic to a Service's ClusterIP and Port is network-address-translated (DNAT) and forwarded to the Pods behind that Service. | It is how "Service" abstractions become real, working network routes to the appropriate Pods. |
| **CNI plugin** | The container-network-interface plugin (Calico, Cilium, Flannel). | It wires up each Pod's virtual network interface so Pods on any node can reach each other, and it provides pod IP assignment. | It is Pod-to-Pod networking. Without it Pods cannot communicate across nodes. |

### Scheduling and Taints (Lesson 07)

The scheduler uses a two-phase algorithm (filter, then score).

- **nodeSelector**: a simple (key=value) field in the Pod spec that **pulls** the Pod toward nodes carrying that label. If no node matches, the Pod stays **Pending** forever; this is a hard rule.
- **Taint**: a mark on a **node** that **repels** Pods (push). A node with a taint of `gpu=true:NoSchedule` refuses any Pod that does not tolerate it. Subsequent examples: `NoSchedule` (no new Pods), `PreferNoSchedule` (try to avoid), `NoExecute` (no new Pods and evict existing Pods that don't tolerate).
- **Toleration**: a mark on a **Pod** saying "I am allowed to run on a node with that taint." Operators used are `Equal` (key and value must match) and `Exists` (only the key must exist).
- The control plane nodes are automatically tainted with `node-role.kubernetes.io/control-plane:NoSchedule` to keep user workloads off them.

### Pod Priority and Preemption (Lesson 17)

- A **PriorityClass** is a cluster-scoped object mapping a name to an integer `value`. Higher value = more important.
- **Preemption** (default `preemptionPolicy: PreemptLowerPriority`) is the scheduler-level action where, if no node can fit a high-priority Pending Pod, the scheduler picks lower-priority "victim" Pods to delete so the important Pod can schedule.
- A sys Pod is much more important than a sacrificial batch job. This lets you run clusters near 100% by packing low-priority jobs in the gaps and reclaiming the space on demand.
- **QoS vs Priority** distinction: QoS determines which Pods the kubelet kills when a node runs out of memory (eviction/OOM). PriorityClass determines which Pods the scheduler kills to make room for a more important Pending Pod.
- If `preemptionPolicy: Never`, a Pod jumps ahead in the scheduling queue but never kills other Pods; it runs when space frees up naturally.

### Node Affinity and Pod Anti-Affinity (Lesson 25)

- **Node Affinity** is the expressive upgrade to `nodeSelector` you match against **node labels**. Supports operators like `In`, `NotIn`, `Exists`.
- **Pod Anti-Affinity** matches against **Pod labels** on nodes; it is how you keep replicas of the same app spread apart.
- Both affinity types have two modes:
  - `requiredDuringSchedulingIgnoredDuringExecution`: hard rule. If not met, the Pod stays Pending.
  - `preferredDuringSchedulingIgnoredDuringExecution`: soft rule. The scheduler tries, but ignores it if impossible.
- **topologyKey** defines the boundary for anti-affinity spreading: `kubernetes.io/hostname` = separate by node; `topology.kubernetes.io/zone` = separate by cloud availability zone (protects against a whole datacenter outage).

### How Controllers Reconcile

A controller is a loop: **watch desired state and actual state, compute the diff, and act until there is no diff.** Example: the Deployment/ReplicaSet controller checks how many matching Pods actually exist vs the `replicas` number. If fewer, it creates Pods; if more, it deletes them. The Node controller marks a node `NotReady` after `node-monitor-grace-period` (default 40s) and Pods are dropped after `pod-eviction-timeout` (default 5m).

## 3. Key Commands

```bash
# Node labels
kubectl label nodes <node> <key>=<val>          # add
kubectl label nodes <node> <key>-               # remove
kubectl get nodes --show-labels

# Taints and tolerations test
kubectl taint nodes <node> <key>=<val>:NoSchedule    # add
kubectl taint nodes <node> <key>=<val>:NoSchedule-   # remove
kubectl describe node <node> | grep -A 5 Taints

# Scheduling debugging (look for FailedScheduling)
kubectl describe pod <name> | grep -A 10 Events
kubectl get pods <name> -o wide

# Priority
kubectl get priorityclasses
kubectl get pod <name> -o yaml | grep priorityClassName
kubectl get priorityclass <name> -o yaml

# Affinity checks
kubectl get pods -l app=web -o wide
kubectl describe pod -l app=web | grep -A 5 Events
```

## 4. YAML Patterns

### Tolerations + affinity

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: memory-app
spec:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app
              operator: In
              values:
              - web
          topologyKey: kubernetes.io/hostname
  tolerations:
  - key: "gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
  containers:
  - name: app
    image: busybox:latest
```

Field-by-field:

- `affinity.podAntiAffinity`: tells Kubernetes to consider other Pods when deciding placement.
- `preferredDuringSchedulingIgnoredDuringExecution`: soft rule; the scheduler morally wants to satisfy it, but will schedule anyway if it cannot (use this for safer HA).
- `weight` (100): how strongly to prefer this rule (only for preferred rules).
- `labelSelector.matchExpressions`: `key: app, operator: In, values: [web]` matches other Pods labeled `app=web` (the same label this app uses).
- `topologyKey: kubernetes.io/hostname`: the rule applies per node, i.e. "do not place two `app=web` Pods on the same hostname".
- `tolerations[].key`: the taint key to match; `operator: Equal` requires an exact value match, `Exists` only requires the key.
- `tolerations[].value`: the taint value to match; `effect: NoSchedule` corresponds to the node taint effect being tolerated.

### Node Affinity (hard rule)

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: disktype
            operator: In
            values:
            - ssd
```

This is a **hard** rule: the Pod only schedules on a node labeled `disktype=ssd`; otherwise it stays Pending.

### PriorityClass + usage

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
description: "Critical apps that must schedule."
---
spec:
  priorityClassName: high-priority
  containers:
  - name: app
    image: busybox:latest
    resources:
      requests:
        cpu: "1000m"
```

- `value`: integer priority; higher wins preemption.
- `globalDefault: false`: don't apply to every Pod automatically.
- `resources.requests.cpu: "1000m"`: the claim that decides how much space the Pod needs when the scheduler decides about preemption.

## 5. How It Fits Together (Step by Step)

A full creation flow, from a command to a running container:

1. `kubectl apply -f file.yaml` → the user sends a request to the **API Server**.
2. The API Server **authenticates** the user (who?), **authorizes** the action (RBAC), and runs **admission controllers** (mutating/validating). All checks pass → the request is valid.
3. The API Server persists the wanted object (desired state) into **etcd** and returns a response.
4. The **controllers** (e.g. kube-controller-manager) watch the API Server. A Deployment controller notices the Deployment and creates a Pod (its desired state).
5. The **scheduler** notices a Pod with no `nodeName`, it runs filter/score, picks a node, and writes `spec.nodeName` back through the API Server to etcd.
6. The **kubelet** on the chosen node watches the API Server, sees the Pod assigned to it, and asks the **container runtime** (via CRI/containerd) to start the containers. The runtime loads the image, which runs.
7. The kubelet reports Pod/node status back to the API Server.
8. For incoming traffic: Ingress/cloud LB → **Service** → **kube-proxy** rewrites Service ClusterIP traffic to the Pod IP (DNAT) → **CNI** delivers it to the container.

```
kubectl -> API Server -> Auth(RBAC) -> Admission -> etcd
  -> controllers reconcile -> Scheduler picks node -> kubelet -> CRI(containerd) -> runc -> container
User -> cloud LB -> Ingress -> Service (kube-proxy DNAT) -> Pod -> container
```

## 6. Common Mistakes and Gotchas

| Mistake | Result | Fix |
|---------|--------|-----|
| Over-constrain with hard `nodeSelector`/required affinity | Apps die when the matching node fails; replicas stay Pending | Use preferred rules or match more nodes |
| Using required anti-affinity with fewer worker nodes than replicas | 3rd+ replica Pending forever | Ensure `replicas <= available nodes`, or use preferred |
| Tainting the GPU node but forgetting to document it | New Pods mysteriously stay Pending | Document all taints in runbooks |
| Removing the control-plane taint | User apps land on control plane and crash the API | Never remove it in production |
| Misspelling labels or `topologyKey` (`kubernetes.io/hostname`) | Affinity rules never match or spread wrong | Verify with `kubectl get nodes --show-labels` |
| Making every app high priority | Preemption no longer works; everything queues | Reserve high priority for truly critical services |
| Confusing QoS with Pod priority | Expecting the scheduler to evict on OOM (it does not) | QoS = kubelet/eviction, Pod priority = scheduler/preemption |
| Letting developers create PriorityClasses or taint nodes | They could preempt CoreDNS or run Pods on the control plane | Restrict creation via RBAC; admin-only |

## 7. Quick Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Pod stuck in Pending | No node fits constraints | `kubectl describe pod <name>` and read `FailedScheduling` events; relax rules or add nodes |
| Pod stuck in Pending (taints) | Node tainted, Pod has no toleration | Add a matching toleration or remove the taint |
| Replica doesn't schedule due where expected | topologyKey doesn't suit node labels | Check `kubectl get nodes --show-labels` for the exact key |
| Pod lands on the wrong node | Labels/taints don't match rules | Verify labels and taints match your scheduling YAML |
| High-priority Pod stays Pending despite low-priority Pods | Low-priority pods have equal or higher priority | Check `priorityClassName` and the `value` of PriorityClasses |
| Preemption not happening | `preemptionPolicy: Never` is set | Confirm the policy via `kubectl get priorityclass <name> -o yaml` |
| Low-priority victim not recreated | ReplicaSet wants to recreate but space is taken | Expected; it stays Pending until the high-priority Pod goes away |

## 8. 30-Second Recap

- The **API Server** is the door to the cluster; **etcd** is the source of truth for desired state.
- The **scheduler** assigns Pods to nodes (filter → score → bind); **controllers** reconcile actual state to desired state.
- The **kubelet** runs containers via the CRI, **kube-proxy** routes Service, traffic,**CNI** wires Pod networking.
- `nodeSelector`/Node-affinity pull Pods to nodes; **Taints** push them away; **Tolerations** let a Pod in.
- **PriorityClass** lets a high-priority Pod **preempt** low-priority `victim` Pods when the cluster is full.
- Required affinity/anti-affinity can leave Pods Pending if you over-constrain a cluster with too few nodes.

## Related Lessons

- [Lesson 07 - Worker Node Architecture](../docs/02-architecture/lesson-07-worker-node-architecture.md)
- [Lesson 17 - Pod Priority and Preemption](../docs/02-architecture/lesson-17-pod-priority-and-preemption.md)
- [Lesson 25 - Node Affinity and Anti-Affinity](../docs/02-architecture/lesson-25-node-affinity-and-anti-affinity.md)

## Related Material

- [Revision - Workloads](workloads.md)
- [Interview - Architecture](../interview/architecture.md)

[Back to Revision Index](README.md)