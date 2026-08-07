---
title: Workload Cheat Sheet
topic: workloads
status: Complete
tags: [cheatsheet, workloads, pod, deployment, statefulset, daemonset, job]
---

# Workload Cheat Sheet

## Pods

Pods are the smallest schedulable unit. One Pod = one or more containers sharing a network namespace, IP, and volumes.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
  labels:
    app: web
spec:
  restartPolicy: Always
  containers:
  - name: web
    image: nginx:1.25-alpine
    ports:
    - containerPort: 80
  initContainers:
  - name: init-db
    image: busybox
    command: ['sh', '-c', 'until nc -z db 5432; do sleep 2; done;']
```

Init containers run to completion in order before the main container starts. Restart policy of `Always` is required except for Jobs/CronJobs.

## ReplicaSet

ReplicaSet ensures N identical Pods. Normally managed by a Deployment; almost never created directly.

```bash
kubectl get rs
kubectl describe rs <name>
kubectl scale rs <name> --replicas=5
kubectl get rs <name> -o yaml
```

Ownership: RS uses `metadata.ownerReferences` so the Deployment drives the RS, which drives Pods. Never delete a Pod the RS manages to fix it; the RS recreates it.

## Deployment

Deployment is the standard way to run stateless apps. It manages ReplicaSets and enables rolling updates, rollback, scaling, pause.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1        # default 25%
      maxSurge: 1              # default 25%
  selector:
    matchLabels: {app: web}
  template:
    metadata:
      labels: {app: web}
    spec:
      containers:
      - name: web
        image: nginx:1.25-alpine
```

| Strategy | Behavior |
|----------|----------|
| `RollingUpdate` | Gradual: new RS scaled up while old RS scaled down, honoring maxUnavailable/maxSurge. Default. |
| `Recreate` | Kill all old Pods, then start new ones. Downtime; use only when a single instance must exist. |

```bash
kubectl set image deployment/web web=nginx:1.26
kubectl rollout status deployment/web
kubectl rollout undo deployment/web            # rollback to previous revision
kubectl rollout undo deployment/web --to-revision=2
kubectl rollout history deployment/web
kubectl rollout restart deployment/web         # rotate Pods, same image
kubectl rollout pause deployment/web           # pause a rollout
kubectl rollout resume deployment/web
kubectl scale deployment/web --replicas=5
```

ReplicaSet revision retention (default 10) is controlled by `.spec.revisionHistoryLimit`.

## StatefulSet

StatefulSet gives stable identity, stable network DNS, and ordered deployment/scaling for stateful apps (databases, queues). Requires a Headless Service.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
spec:
  serviceName: db            # must match the headless Service
  replicas: 3
  selector:
    matchLabels: {app: db}
  template:
    metadata:
      labels: {app: db}
    spec:
      containers:
      - name: db
        image: postgres:16
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 10Gi
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: db
spec:
  clusterIP: None            # headless
  selector: {app: db}
  ports:
  - port: 5432
```

Stable network identity: `db-0.db.default.svc.cluster.local`, `db-1.db...`.

| Field | Effect |
|-------|--------|
| `serviceName` | Binds to the headless Service used for per-Pod DNS. |
| `volumeClaimTemplates` | Creates one PVC per replica (`data-db-0`, `data-db-1`). |
| `podManagementPolicy` | `OrderedReady` (default) or `Parallel`. |
| `updateStrategy` | `RollingUpdate` with `partition` for phased upgrades. |

Ordered behavior: scale up `db-0` first, wait ready, then `db-1`; on scale down, delete in reverse.

## DaemonSet

DaemonSet runs exactly one Pod on every node (and new nodes that join). Use for agents: kube-proxy, CNI, log shippers (Promtail), node exporters.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
spec:
  selector:
    matchLabels: {app: node-exporter}
  template:
    metadata:
      labels: {app: node-exporter}
    spec:
      hostNetwork: true       # commonly needed for node agents
      containers:
      - name: node-exporter
        image: prom/node-exporter:latest
        ports:
        - containerPort: 9100
```

```bash
kubectl get daemonsets -A
kubectl rollout restart daemonset/<name>
```

Taints/taint-tolerations control whether the DaemonSet Pod lands on a node.

## Job and CronJob

Jobs run one or more Pods to completion. CronJobs run Jobs on a schedule (cron syntax).

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pi
spec:
  completions: 3             # total successful Pods required
  parallelism: 2             # run 2 at a time
  backoffLimit: 4
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: pi
        image: perl:5.34
        command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
```

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup
spec:
  schedule: "0 2 * * *"       # cron expression (5 fields)
  concurrencyPolicy: Forbid   # Allow | Forbid | Replace
  successfulJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: busybox
            command: ["sh", "-c", "echo backup"]
```

```bash
kubectl create job manual --from=cronjob/backup   # trigger one-off run
kubectl get jobs
kubectl logs job/pi
kubectl wait --for=condition=complete job/pi
kubectl delete job pi
```

Key Job fields: `completions`, `parallelism`, `backoffLimit`, `activeDeadlineSeconds`, `ttlSecondsAfterFinished` (auto-cleanup). CronJob timezone field `schedule` uses `timeZone` or UTC by default.

## Probes

| Probe | When | Failing means |
|-------|------|---------------|
| `startupProbe` | Before other probes are evaluated | Container not ready yet; restarts via liveness on failure |
| `livenessProbe` | While running | Restart the container (kill and recreate) |
| `readinessProbe` | While running | Remove Pod IP from Service Endpoints (no restart) |

```yaml
readinessProbe:
  httpGet: {path: /ready, port: 8080}
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 1
  failureThreshold: 3
livenessProbe:
  httpGet: {path: /live, port: 8080}
  periodSeconds: 15
  failureThreshold: 3
startupProbe:
  httpGet: {path: /healthz, port: 8080}
  failureThreshold: 30     # slow-start apps: 30 * periodSeconds grace
  periodSeconds: 2
```

Probe handlers: `httpGet`, `tcpSocket`, `exec` (command exit code 0 = success), `grpc`.

## Workload Choice Quick Table

| App type | Use | Because |
|----------|-----|---------|
| Stateless web API | Deployment | Rolling updates, easy scaling |
| Database / queue / cache | StatefulSet | Stable identity + persistent PVC per replica |
| Node agent / exporter | DaemonSet | One Pod per node automatically |
| Batch / data processing | Job | Run-to-completion |
| Scheduled tasks | CronJob | Cron-like scheduling |
| One-off bootstrap | initContainers | Run before main container |

## Pod Lifecycle Phases

```text
Pending -> Running -> Succeeded
              |            +-> (Jobs only)
              v
            Failed -> CrashLoopBackOff / Error
```

`kubectl get pods` states: `Pending`, `Running`, `Succeeded`, `Failed`, `Unknown`, `ContainerCreating`, `CrashLoopBackOff`, `Terminating`.
