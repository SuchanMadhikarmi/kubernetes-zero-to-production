---
title: Revision - Production
module: 12 Production
status: Complete
tags: [revision, production, autoscaling, hpa, velero, upgrades, multi-cluster]
---

# Revision - Production

Module 12 is about operating Kubernetes safely in a real environment: keep workloads running during traffic spikes, keep the cluster healthy during maintenance, survive a full failure, and ship new code without taking the app down. This file reminds you of the pieces, how each works, and how they fit together, so you can re-learn the whole module by reading it top to bottom.

## 1. The Mental Model

Production Kubernetes is a loop of four disciplines: **capacity**, **maintenance**, **recovery**, and **delivery**.

- **Capacity** = keep enough Pods and Nodes. The HPA adds Pods; the Cluster Autoscaler adds Nodes; the VPA resizes Pod requests.
- **Maintenance** = keep the workers healthy. Cordon, drain, patch, uncordon so you never reboot workloads blindly.
- **Recovery** = assume deletion and outages happen. Velero snapshots cluster YAML plus Persistent Volume data and can rebuild everything.
- **Delivery** = assume code ships bugs. Argo Rollouts sends a small percentage of users to the new version, checks metrics, and reverts automatically.

A useful frame for everything below: *nobody can break availability if each stage is gated by data.* HPA gates replicas on CPU, drain gates node removal on PodDisruptionBudgets, Velero gates recovery on tested restores, and Rollouts gates a release on real 5xx and latency numbers.

## 2. Core Concepts

### Horizontal Pod Autoscaling (HPA)

- HPA (`autoscaling/v2`) scales the number of Pod replicas of a Deployment/ReplicaSet.
- It is `a control loop` in kube-controller-manager that polls the **Metrics Server** every ~15 seconds through the `metrics.k8s.io` API.
- Utilization is computed **against the Pod's `resources.requests`**, not the limit. Without a request there is no baseline and HPA reports `<unknown>`.
- The key formula: `desired = ceil(currentReplicas * (currentUtilization / targetUtilization))`.
- Scale-up is fast; scale-down is deliberately slow (a stabilization window, ~5 minutes) to avoid thrashing.
- It cannot scale to zero with normal CPU metrics (a Pod with 0 replicas produces no metrics). Use KEDA or custom metrics for scale-to-zero.
- `behavior` block tunes scaleUp/scaleDown stabilization windows and policies to prevent oscillation.

### VPA and Cluster Autoscaler (brief)

| Autoscaler | Scales | Trigger |
|------------|--------|---------|
| HPA | number of Pods | metrics (CPU/memory/custom) |
| VPA | Pod requests/limits | observed usage (recommend or recreate) |
| Cluster Autoscaler | number of Nodes | Pods stuck `Pending` / underutilized nodes |

- VPA with `updateMode: Auto` can recreate a Pod to resize it; better to run it in `Off`/`Initial` mode and pair it with HPA rather than scale the same resource on the same metric twice.
- Cluster Autoscaler talks to the cloud provider (AWS/GCP/Azure) node groups; it sees `Pending` Pods no node can hold and adds nodes, and removes underutilized nodes that can be drained safely. It has no effect on kind (no cloud).

### Cluster upgrades and maintenance

- **Cordon** marks a Node `SchedulingDisabled`: no new Pods are scheduled, existing Pods keep running.
- **Drain** evicts the running Pods so you can shut the Node down safely. It respects PodDisruptionBudgets and sends `SIGTERM`, then `SIGKILL` after `terminationGracePeriodSeconds` (default 30s).
- **Uncordon** re-enables scheduling after maintenance.
- A drain refuses to evict DaemonSet Pods (they run on every node, deleting them would just be recreated) and Pods with emptyDir volumes. Pass `--ignore-daemonsets` and `--delete-emptydir-data` to override.
- Node replacement: the usual cycle is cordon, drain, patch/reboot, and uncordon; or cordon, drain, terminate the instance, and let the Cluster Autoscaler/cloud node group replace it.
- **PodDisruptionBudget (PDB)** protects availability during voluntary disruptions: `minAvailable` or `maxUnavailable` caps how many matching Pods can be down at once. A drain waits rather than violate a PDB.

### Backups and disaster recovery with Velero

- Velero runs as a Deployment in the `velero` namespace and uses CRDs: `Backup`, `Restore`, `Schedule`, `BackupStorageLocation`, `VolumeSnapshotLocation`.
- A `Backup` exports Kubernetes YAML to an object store (S3) and can snapshot Persistent Volumes (cloud/CSI snapshots, or Restic/Kopia for file-level, cross-cloud).
- A `Restore` reapplies that YAML to the same or a different cluster and reattaches volume data.
- A `Schedule` triggers backups on a cron with a `ttl`.
- It does **not** back up container images (those must still exist in a registry) or replace database-native backups (`pg_dump`).
- An etcd snapshot (`etcdctl snapshot save`) captures YAML only, no PV data; Velero does both.

### Multi-cluster

- Kubernetes is single-cluster by design; etcd does not sync across clusters. Multi-cluster is achieved with external tools and Git as the single source of truth.
- **Why:** reduce blast radius, achieve failover, and lower latency by placing clusters near users, plus compliance/tenancy isolation.
- Patterns: **Active-Active** (all clusters serve live traffic, the rest pick up on failure) and **Active-Passive** (one serves traffic, one is standby for DR).
- **ApplicationSet** is the ArgoCD CRD that renders one Application per target cluster from a list or directory generator.
- A **global load balancer** (Route53, Cloudflare) health-checks each cluster's Ingress and routes users to the nearest healthy cluster.

### Progressive Delivery and Argo Rollouts

- Progressive Delivery gradually shifts traffic to a new version, gating each step on evidence.
- **Canary:** route a small % (e.g. 10%) of traffic to the new ReplicaSet; if metrics pass, ramp up; if they fail, revert.
- **Blue-green:** deploy 100% of the new version but route 0% until an explicit promote switch.
- **Rollout CRD** (`argoproj.io/v1alpha1`) replaces a Deployment, keeping a **Stable** ReplicaSet and a **Canary** ReplicaSet with a `strategy` block.
- **AnalysisTemplate** is a CRD that queries a metrics provider (e.g. Prometheus) and evaluates `successCondition`/`failureCondition`; a failure aborts the rollout.
- Argo Rollouts and ArgoCD complement each other: ArgoCD syncs the Rollout YAML from Git; the Argo Rollouts controller executes the canary steps.
- True traffic shifting needs an Ingress controller or Service Mesh; merely scaling replicas does not isolate long-lived requests.

## 3. Key Commands

### HPA

```bash
kubectl get hpa                                   # TARGETS vs target, replicas
kubectl describe hpa <name>                       # Conditions and Events
kubectl top pods                                  # proves the Metrics Server works
kubectl top nodes
kubectl autoscale deployment web --cpu-percent=50 --min=2 --max=10
kubectl get --raw /apis/metrics.k8s.io/v1beta1    # check metrics API exists
```

### Node maintenance

```bash
kubectl cordon <node>          # stop new Pods
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl drain <node> --force --ignore-daemonsets --delete-emptydir-data  # only for bare Pods
kubectl uncordon <node>        # allow scheduling again
kubectl get nodes              # check Ready vs SchedulingDisabled
kubectl get pdb                # check availability limits before draining
```

### Velero

```bash
velero backup create <name> --include-namespaces <ns>
velero backup describe <name> --details
velero restore create --from-backup <name>
velero schedule create <name> --schedule="0 2 * * *"
velero backup delete <name>
```

### Multi-cluster

```bash
kubectl config get-contexts
kubectl config use-context <name>
argocd cluster add <name>
argocd cluster list
```

### Argo Rollouts

```bash
kubectl apply -f rollout.yaml
kubectl argo rollouts get rollout <name> --watch
kubectl argo rollouts set image <name> <container>=<image>
kubectl argo rollouts promote <name>   # skip pauses -> 100%
kubectl argo rollouts abort <name>     # fail the canary, revert to stable
```

## 4. YAML Patterns (HorizontalPodAutoscaler, Argo Rollout)

### HorizontalPodAutoscaler

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

Explanation:

- `scaleTargetRef` points at the workload, the autoscaler patches its `replicas` field.
- `minReplicas`/`maxReplicas` cap how far it may go; set honestly so it can both absorb a spike and not waste money.
- `metrics[].type: Resource` uses the standard metrics; `name: cpu`, `averageUtilization: 70` means keep each Pod at ~70% of its CPU request. Without `resources.requests.cpu` in the Deployment, could lie and report `<unknown>`.
- `behavior` tunes the same defaults here: near-immediate scale up, a 5-minute scale-down stabilization window threshold to stop thrash.

### Argo Rollout (canary steps)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app-rollout
spec:
  replicas: 4
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: app
        image: nginx:alpine
  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause: {duration: 10s}
      - setWeight: 40
      - pause: {duration: 10s}
      - setWeight: 60
      - pause: {}          # no duration = wait for manual promote
```

Explanation:

- `argoproj.io/v1alpha1` makes a Rollout, not the Deployment; the Argo Rollouts controller watches it.
- `spec.template` is a normal Pod spec, so a Rollout looks like a Deployment until the `strategy` block.
- `strategy.canary.steps` sequences traffic shifted: each `setWeight` tells the Ingress/Service Mesh what % of requests goes to the new version; each `pause` holds there for a `duration`, or with `{}` until you manually `promote`.
- `pause: {duration: 10s}` is a lab convenience; production pauses should be long enough (2-5 min) for Prometheus to scrape meaningful metrics.

### Argo AnalysisTemplate (gates each step)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  metrics:
  - name: success-rate
    interval: 60s
    successCondition: result[0] >= 0.95
    failureCondition: result[0] < 0.95
    provider:
      prometheus:
        address: http://prometheus:9090
        query: |
          sum(rate(http_requests_total{job="myapp", status=~"5.."}[1m]))
```

During a rollout Argo creates an `AnalysisRun` from this template, runs the query at the interval, and checks the conditions. A `failureCondition` breach aborts the canary and reverts traffic to the Stable ReplicaSet.

## 5. How It Fits Together

**Scaling flow (HPA + Cluster Autoscaler):** traffic spikes, the Metrics Server sees CPU above the average utilization, HPA patches the Deployment `replicas` up to `maxReplicas`. If the new Pods cannot fit on any node they stay `Pending`, the Cluster Autoscaler provisions a new node, and they schedule. When traffic drops, HPA scales Pods down after the stabilization window, nodes become underutilized, and the Cluster Autoscaler drains and removes them.

**Upgrade and maintenance flow:**

```
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
# PDB keeps <workload> available while the drain evicts
# patch/reboot the node, or terminate it and let cloud create a fresh one
kubectl uncordon <node>
```

A PDB guarantees voluntary disruption used not take all replicas down. To replace a bad node, cordon + drain + delete it and let the autoscaler/ASG spin up a patched replacement.

**Disaster recovery restore flow:**

1. Install Velero pointing at your object store (S3).
2. Publish `Backup` or a `Schedule`; Velero writes cluster YAML to object storage and snapshots PV data (CSI snapshot or Restic).
3. A namespace is deleted or the cluster lost.
4. Restore: `velero restore create --from-backup <name>` (into the same cluster or a new one provisioned for migration).
5. Confirm Deployment, Service, ConfigMap, and Volume data are back; repeat this in staging often.

**Progressive delivery flow:**

standard Deployment -> blind rolling update. To gate it: replace with a Rollout + AnalysisTemplate. New image triggers steps (10-20%), the AnalysisRun queries error/latency, on success it ramps to 100%, on failure it scales the Canary to 0 and sends 100% to Stable. Use this with GitOps (ArgoCD syncs the Rollout YAML; the Rollouts controller executes it).

## 6. Common Mistakes and Gotchas

| Mistake | Consequence | Fix |
|---------|-------------|-----|
| HPA deployed without the Metrics Server | shows `<unknown>/xx%`, never scales | run `kubectl top pods`; metrics server first |
| No `resources.requests` on the target | current utilization in HPA cannot be computed | set a realistic `requests.cpu` |
| Confusing HPA and Cluster Autoscaler | add Pods, not Nodes, or vice versa | label each: HPA=Pod replicas, CA=nodes |
| VPA `Auto` + HPA on the same metric | conflicting resizes | use VPA `Off`/`Initial` or keep them on different resources |
| `kubectl drain` without flags | hangs on DaemonSet and empty Pods | add `--ignore-daemonsets --delete-emptydir-data` |
| Forgetting to `uncordon` | node ready but scheduler ignores it, waste capacity | uncordon immediately after maintenance |
| Draining multiple nodes hosting the same workload | outage because replicas dropped everywhere | drain sequentially; define a PDB |
| Never testing restores | a backup that fails on restore is worthless | restore into staging regularly |
| Deleting the `velero` namespace | backup history in the cluster is lost | protect the `velero` namespace and CRDs |
| Backing up a database only with Velero | file-level copy can catch a mid-write DB | use a DB-native dump (`pg_dump`) |
| Treating Argo Rollouts as a "box to tick" | without a metrics provider the canary is a slow rolling update | wire Prometheus + an AnalysisTemplate |
| `pause: {}` expecting auto-advance | sits at a step forever | provide a duration or call `promote` |
| A Rollout with no traffic router | only replica counts change, broken requests still error | use Ingress/Service Mesh for real canary |
| Kubectl `apply` straight to multi-cluster prod | config drift and no rollback | use GitOps + ApplicationSets |

## 7. Quick Troubleshooting

HPA shows `<unknown>/xx%`: check `kubectl top pods` (Metrics Server up?) and the Deployment YAML (`resources.requests` present?).

HPA not scaling under load: `kubectl describe hpa <name>` -> look at Conditions and Events; confirm `maxReplicas` is not already reached and the metric is below target.

Drain hangs forever: `kubectl get pdb` (is a PDB refusing the eviction?), check emptyDir volumes (`--delete-emptydir-data` missing?), or bare Pods (`--force` needed).

Pods repopulate onto the node being drained: the node was never cordoned; cordon before drain.

Velero backup stuck `New`/`InProgress`: Pod in `velero` namespace healthy? `kubectl logs -n velero deployment/velero` for S3/auth errors; does the BSL reach object storage?

Restore completes but volumes are empty: the backup did not include PV data; re-run with volume snapshots or `--use-restic`.

ArgoCD cannot sync to a target cluster: connectivity (`curl -k https://<cluster>:6443`) and ServiceAccount credentials.

Rollout stuck at a weight: check for `pause: {}` (needs `promote`), check the AnalysisRun status or `Pending`, and whether Prometheus is actually scraping the app.

Multi-cluster traffic not failing over: the Global LB health checks likely point at the wrong Ingress/Service or DNS records.

## 8. 30-Second Recap

- **HPA** scales Pods on metrics (CPU % of the request); Cluster Autoscaler scales nodes; VPA resizes Pod requests.
- **Cordon** no new Pods; **drain** evicts running Pods; **uncordon** restores. A PDB caps how many can be down.
- **Velero** = time machine: backs up cluster YAML + PV data, restores to the same or another cluster; always test restores.
- **Multi-cluster** = many independent control planes linked via GitOps; Global LB fails over by health.
- **Argo Rollouts** replaces Deployments with canary/blue-green, gates each step on an AnalysisTemplate, and auto-reverts on failure.

Production = bounded blast radius everywhere: bound replicas, bound disruption (PDB), bound data loss (Velero), bound release risk (Rollouts).

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