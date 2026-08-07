---
title: Lesson 8 - StatefulSets
module: 03 Workloads
lesson: 8
status: Complete
tags: [kubernetes, statefulsets, headless-service, stable-identity, volumeclaimtemplates, orderedready, databases]
---

# Lesson 8 - StatefulSets

## Table of Contents

- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Real-world Motivation](#real-world-motivation)
- [Core Concepts](#core-concepts)
- [Architecture](#architecture)
- [ASCII Diagrams](#ascii-diagrams)
- [Hands-on](#hands-on)
- [Commands](#commands)
- [YAML Explanation](#yaml-explanation)
- [Production Notes](#production-notes)
- [Best Practices](#best-practices)
- [Common Mistakes](#common-mistakes)
- [Troubleshooting](#troubleshooting)
- [Interview Questions](#interview-questions)
- [Scenario Questions](#scenario-questions)
- [Quiz](#quiz)
- [Revision](#revision)
- [Cheat Sheet](#cheat-sheet)
- [References](#references)
- [Related Lessons](#related-lessons)
- [Coming Next](#coming-next)

---

## Learning Objectives

By the end of this lesson you will be able to:

- Explain why Deployments and ReplicaSets fail for distributed databases.
- Describe what a StatefulSet is and how it provides stable, ordered identities.
- Explain the role of a Headless Service in StatefulSet DNS.
- Describe how `volumeClaimTemplates` provide unique storage per Pod.
- Explain how `podManagementPolicy: OrderedReady` can freeze a rollout.

## Prerequisites

- Completion of Lessons 1 through 12.
- A running Kubernetes cluster (see [Lesson 01](../01-fundamentals/lesson-01-anatomy-of-a-container.md) for kind setup instructions).
- kubectl installed and configured.

## Real-world Motivation

### The Lost Peer

Imagine you deploy a 3-node Cassandra database cluster using a standard Deployment.

1. Pod 1 (db-a1, IP: 10.1.0.5) is elected Master.
2. Pod 2 (db-x9, IP: 10.1.0.6) connects to Pod 1 to replicate data.
3. Pod 2 crashes. The ReplicaSet replaces it with Pod 4 (db-c4, IP: 10.1.0.9).
4. The Master (Pod 1) tries to replicate data to db-x9, but it's gone. The replication breaks. The database cluster fragments and data is lost.

Databases require strict, predictable hostnames and stable identities to form quorums and manage replication.

### Why This Exists

Kubernetes needed a way to provide stable network identities and stable storage in a highly ephemeral environment. StatefulSets were created to give Pods a sticky, predictable identity. Pods are named `<app>-0`, `<app>-1`, `<app>-2`. If `<app>-1` dies, the new Pod is also named `<app>-1`.

### Real Company Examples

**Pinterest:** Pinterest runs massive Kafka clusters on Kubernetes using StatefulSets. Kafka brokers require stable identities to manage topic partitions. If a broker crashes, a new broker spins up with the exact same name (`kafka-2`), attaches to the same PVC (recovering its disk data), and rejoins the cluster seamlessly. Users never notice the broker died.

## Core Concepts

### Explain Like I'm 12

Imagine a royal family. The king is King 0, the prince is King 1, the princess is King 2. If King 0 dies, the prince becomes King 0. The title (hostname) is passed down to the replacement. Also, they are introduced to the public one at a time, strictly in order. The prince isn't introduced until the king is ready.

### Explain Like I'm a Junior Engineer

A StatefulSet gives Pods a sticky, predictable identity. Pods are named `db-0`, `db-1`, `db-2`. If `db-1` dies, the new Pod is also named `db-1`. They are created in strict order (0, then 1, then 2) and deleted in reverse order (2, then 1, then 0).

### Explain Technically

- **StatefulSet:** A controller that watches Pod states. It expects the Pod's exit code to be 0.
- **Headless Service:** By setting `clusterIP: None`, you tell CoreDNS to create specific A-records for each Pod IP, rather than one record for a virtual IP.
- **OrderedReady:** The StatefulSetController waits for the API Server to report `status.phase: Running` and `status.conditions: Ready` for Pod N before creating Pod N+1.

### How Kubernetes Implements It Internally

The StatefulSetController runs in the `kube-controller-manager`. When it creates a Pod, it explicitly sets the `hostname` and `subdomain` fields in the Pod spec. It also sets an `ownerReference` so the Pod is garbage collected if the StatefulSet is deleted. For storage, it uses the PersistentVolumeClaim API to clone the `volumeClaimTemplate` for each Pod sequentially.

### Why Kubernetes Was Designed That Way

StatefulSets separate identity from compute. In a Deployment, Pods are interchangeable cattle. In a StatefulSet, Pods are named pets. This distinction is critical for distributed systems that rely on stable network identities and persistent storage to maintain data consistency.

## Architecture

```
[ StatefulSet ]
      |
      +---> [ Headless Service (clusterIP: None) ] (Provides db-0.db-svc, db-1.db-svc DNS)
      |
      +---> [ Pod: db-0 ] ---> [ PVC: data-db-0 ] (Must be Ready)
                |
                v (Only after db-0 is Ready...)
      +---> [ Pod: db-1 ] ---> [ PVC: data-db-1 ] (Must be Ready)
                |
                v (Only after db-1 is Ready...)
      +---> [ Pod: db-2 ] ---> [ PVC: data-db-2 ]
```

### Terminology

| Term | Definition |
|------|------------|
| StatefulSet | A workload API used to manage stateful applications. It manages deployment and scaling deterministically. |
| Headless Service | A Service (`clusterIP: None`) that doesn't load-balance. Instead, it returns the direct IP addresses of the Pods. |
| OrderedReady | The default `podManagementPolicy`. Pod N+1 is not created until Pod N is Running and Ready. |
| volumeClaimTemplate | A blueprint used by the StatefulSet to automatically create a unique PVC for every Pod. |
| Stable Network Identity | A predictable hostname and DNS name that persists across Pod restarts. |

### How It Works Internally

1. You create a StatefulSet with `replicas: 3` and a `serviceName`.
2. The StatefulSetController creates Pod `db-0`.
3. It waits. It polls the API Server. Once Pod `db-0` is Ready, it creates Pod `db-1`.
4. Because the Pods have deterministic names, the Headless Service can create specific DNS A-records for each Pod IP.
5. If `db-0` crashes, the controller waits for it to be recreated (with the same name) before proceeding with any other scaling operations.

### Step-by-Step Workflow

1. Developer creates a StatefulSet YAML referencing a Headless Service.
2. API Server saves it to etcd.
3. Controller creates `db-0` and a PVC `data-db-0`.
4. Scheduler assigns `db-0` to a node. Kubelet starts it.
5. Controller sees `db-0` is Ready. It creates `db-1` and `data-db-1`.
6. Process repeats until 3 Pods are running.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | Pods are created sequentially (0, 1, 2). |
| Scaling Up | Pod N+1 is only created when Pod N is Ready. |
| Scaling Down | Pods are deleted in reverse order (2, 1, 0). The PVCs are NOT deleted. |
| Update | If the Pod template changes, it updates Pods in reverse order (2, then 1, then 0). |

### Deployment vs StatefulSet

| Feature | Deployment | StatefulSet |
|---------|------------|-------------|
| Pod Names | Random (`app-xyz-123`) | Predictable (`app-0`, `app-1`) |
| Pod Startup | Parallel | Sequential (OrderedReady) |
| Storage | Usually shared PVCs | Unique PVC per Pod (`volumeClaimTemplates`) |
| Network Identity | Random IP, Service load-balances | Stable IP, Headless Service resolves to specific Pod |
| Use Case | Web servers, APIs | Databases, Kafka, ZooKeeper |

### Common Myths

| Myth | Fact |
|------|------|
| "StatefulSets are just Deployments with volumes." | False. The core difference is the identity and ordering. A Deployment's Pods are identical cattle; a StatefulSet's Pods are named pets. |
| "StatefulSets use a standard ClusterIP Service for load balancing." | False. They use Headless Services for direct identity resolution. |
| "Deleting a StatefulSet deletes its PVCs." | False. PVCs are NOT deleted. They persist and can be reattached by a new StatefulSet. |

## ASCII Diagrams

Mental Model: A StatefulSet is like building a staircase. You cannot build step 2 until step 1 is fully poured and dried. If step 1 collapses, all work on the stairs stops until step 1 is fixed.

```
[ StatefulSet (replicas: 3) ]
      |
      v (Controller creates Pod 0)
[ Pod: db-0 ] ---> [ PVC: data-db-0 ]
      | (Watches API Server... is db-0 Ready? Yes.)
      v (Controller creates Pod 1)
[ Pod: db-1 ] ---> [ PVC: data-db-1 ]
      | (Watches API Server... is db-1 Ready? Yes.)
      v (Controller creates Pod 2)
[ Pod: db-2 ] ---> [ PVC: data-db-2 ]
```

### DNS Resolution Flow

```
[ Client Pod ]
      | (Asks CoreDNS: "What is db-0.db-svc?")
      v
[ CoreDNS ]
      | (Returns Pod IP: 10.1.0.5)
      v
[ Client connects directly to db-0 at 10.1.0.5 ]
```

## Hands-on

### Objective

Create a StatefulSet that intentionally breaks on the first Pod, demonstrating the strict ordering trap.

### Step 1: Create a Headless Service

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: db-svc
spec:
  clusterIP: None
  selector:
    app: db
  ports:
  - port: 80
EOF
```

### Step 2: Create the StatefulSet

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
spec:
  serviceName: db-svc
  replicas: 3
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: db
        image: busybox:latest
        command: ["sh", "-c", "echo 'Database starting...' && exit 1"]
  podManagementPolicy: OrderedReady
EOF
```

### Step 3: Investigate the Freeze

```bash
kubectl get pods -l app=db
```

Only `db-0` exists. It is in `CrashLoopBackOff`. `db-1` and `db-2` do not exist because `db-0` is not Ready.

### Step 4: Fix the StatefulSet

```bash
kubectl delete statefulset db

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
spec:
  serviceName: db-svc
  replicas: 3
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: db
        image: busybox:latest
        command: ["sh", "-c", "echo 'Database started on \$(hostname)' && sleep 3600"]
  podManagementPolicy: OrderedReady
EOF
```

```bash
kubectl get pods -l app=db --watch
```

Expected: Pods boot one by one: `db-0`, then `db-1`, then `db-2`.

### Step 5: Verify Stable DNS

```bash
kubectl run -it --rm dns-test --image=busybox -- nslookup db-0.db-svc
```

### Step 6: Verify Unique PVCs

```bash
kubectl get pvc
```

Expected: 3 PVCs: `data-db-0`, `data-db-1`, `data-db-2`.

### Step 7: Test Scaling Down

```bash
kubectl scale statefulset db --replicas=1
kubectl get pods -l app=db
kubectl get pvc
```

Expected: `db-2` and `db-1` are deleted. `db-0` remains. PVCs are NOT deleted.

### Step 8: Cleanup

```bash
kubectl delete statefulset db
kubectl delete svc db-svc
kubectl delete pvc data-db-0 data-db-1 data-db-2
```

## Commands

```bash
# List StatefulSets
kubectl get statefulset

# Describe a StatefulSet
kubectl describe statefulset <name>

# Scale a StatefulSet
kubectl scale statefulset <name> --replicas=5

# Check PVCs created by volumeClaimTemplates
kubectl get pvc

# Test Headless Service DNS
kubectl run -it --rm dns-test --image=busybox -- nslookup <pod-name>.<service-name>

# Delete a StatefulSet (does NOT delete PVCs)
kubectl delete statefulset <name>

# Manually delete PVCs
kubectl delete pvc <pvc-name>
```

## YAML Explanation

```yaml
apiVersion: v1
kind: Service
metadata:
  name: db-svc
spec:
  clusterIP: None
  selector:
    app: db
  ports:
  - port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
spec:
  serviceName: db-svc
  replicas: 3
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: db
        image: busybox:latest
        command: ["sh", "-c", "echo 'Database started on \$(hostname)' && sleep 3600"]
  podManagementPolicy: OrderedReady
```

### Field-by-Field Explanation

- `spec.clusterIP: None`: Makes the Service headless. CoreDNS creates A-records for each Pod IP.
- `spec.serviceName: db-svc`: Links the StatefulSet to the Headless Service.
- `spec.podManagementPolicy: OrderedReady`: Pods are created sequentially (0, then 1, then 2).

## Production Notes

- **Use Headless Services.** Always create a Headless Service (`clusterIP: None`) and link it via `serviceName` in the StatefulSet. Without it, DNS resolution for individual Pods breaks.
- **Use `volumeClaimTemplates`.** Never share a single PVC across StatefulSet Pods. Each Pod needs its own disk to prevent data corruption.
- **Use Pod Anti-Affinity.** For production databases, always use Pod Anti-Affinity to ensure `db-0`, `db-1`, and `db-2` land on different physical nodes. If they all land on one node and it crashes, you lose the whole cluster.
- **Back up PVCs.** StatefulSets don't back up data. Use Velero or similar tools for disaster recovery.
- **Test disaster recovery.** Simulate node failures and verify that StatefulSet Pods recover correctly.

### When to Use / When NOT to Use

**Use a StatefulSet when:**

- Running distributed databases (PostgreSQL, MySQL, Cassandra).
- Running message queues (Kafka, RabbitMQ).
- Any application requiring a stable, predictable hostname or persistent storage tied to a specific Pod identity.

**Do NOT use a StatefulSet when:**

- Running stateless web applications. It makes scaling slow and complex.
- Applications that don't care about Pod identity.

### Performance and Security Considerations

**Performance:** `OrderedReady` makes scaling slow. If you have a 10-node database cluster and you scale up, it boots them one by one. If each takes 2 minutes to boot, scaling up takes 20 minutes. You can change `podManagementPolicy: Parallel` to boot them all at once (if the app supports it).

**Security:** StatefulSets often run privileged databases. Ensure you use a dedicated namespace and strict RBAC to prevent other applications from accessing the database Pods.

## Best Practices

- Use Headless Services for StatefulSets.
- Use `volumeClaimTemplates` for unique storage per Pod.
- Use Pod Anti-Affinity to spread Pods across nodes.
- Back up PVCs regularly with Velero or similar tools.
- Use `OrderedReady` for databases that require strict startup order.
- Use `Parallel` for applications that can start simultaneously.
- Test disaster recovery procedures.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| The Frozen Rollout | First Pod fails, blocking all others | Fix Pod 0 immediately; it blocks the entire rollout |
| Orphaned PVCs | Deleting StatefulSet doesn't delete PVCs | Manually delete PVCs when needed |
| Using StatefulSets for Web Apps | Misunderstanding the use case | Use Deployments for stateless workloads |
| No Pod Anti-Affinity | All Pods land on one node | Use Pod Anti-Affinity rules |

## Troubleshooting

**Symptom: StatefulSet stuck with only Pod 0 in CrashLoopBackOff**

Cause: `OrderedReady` policy blocks subsequent Pods until Pod 0 is Ready.

```bash
kubectl describe pod db-0
kubectl logs db-0 --previous
```

Fix: Fix the issue with Pod 0 (image, config, resources). The StatefulSet will proceed once Pod 0 is Ready.

**Symptom: PVCs not created**

Cause: `volumeClaimTemplates` not defined in the StatefulSet spec.

```bash
kubectl describe statefulset <name>
```

Fix: Add `volumeClaimTemplates` to the StatefulSet spec.

**Symptom: DNS resolution fails for StatefulSet Pods**

Cause: Headless Service not linked or not created.

```bash
kubectl get svc <service-name>
kubectl get endpoints <service-name>
```

Fix: Ensure the Service has `clusterIP: None` and the StatefulSet references it via `serviceName`.

## Interview Questions

**Q: What are the two main reasons to use a StatefulSet instead of a Deployment?**

A: 1. Pods need stable network identities (predictable names/DNS). 2. Pods need stable, persistent storage that doesn't change on restart.

**Q: What is a Headless Service?**

A: A Service with `clusterIP: None`. It doesn't load balance. It returns the direct IP addresses of the Pods behind it via DNS, allowing clients to connect to a specific instance by name.

**Q: If a StatefulSet is stuck and only `app-0` exists (in CrashLoopBackOff), why aren't `app-1` and `app-2` being created?**

A: Because the default `podManagementPolicy` is `OrderedReady`. The controller will not create the next Pod until the current one is Running and Ready.

**Q: You delete a StatefulSet and its Pods, but not the PVCs. You then recreate the StatefulSet with a new image version. The new Pods crash immediately on startup. Why?**

A: Deleting a StatefulSet does not delete the PVCs. When the new StatefulSet is created, it reattaches to the old disks. If the new image version expects a different database schema or file format, it will fail to read the old data and crash. You must manually delete the PVCs or migrate the data.

**Q: What is the difference between `OrderedReady` and `Parallel` pod management?**

A: `OrderedReady` creates Pods sequentially (0, then 1, then 2) and waits for each to be Ready. `Parallel` creates all Pods simultaneously. Use `Parallel` when the application can handle simultaneous startup.

**Q: Do StatefulSets delete PVCs when the StatefulSet is deleted?**

A: No. PVCs are NOT deleted. They persist and can be reattached by a new StatefulSet with the same name.

## Scenario Questions

**Scenario 1:** You have a 5-node Kafka cluster using a StatefulSet. You need to scale to 8 nodes. How long will it take?

A: With `OrderedReady` (default), it will take as long as it takes for each Pod to become Ready, one by one. If each Pod takes 2 minutes to boot, it will take about 6 minutes for the 3 new Pods. You could use `podManagementPolicy: Parallel` to speed this up if Kafka supports it.

**Scenario 2:** You need to upgrade your database image from v1 to v2. How does the StatefulSet handle this?

A: The StatefulSet performs a rolling update in reverse order: Pod 2, then Pod 1, then Pod 0. Each Pod must be Ready before the next one is updated.

**Scenario 3 (Mini Project - The Unique Disks):**

Create a StatefulSet with 3 replicas that successfully runs (`sleep 3600`). Use `volumeClaimTemplates` to request 1GB per Pod. Watch the Pods boot one by one. Run `kubectl get pvc` and verify that 3 completely separate PVCs were created automatically (`data-db-0`, `data-db-1`, `data-db-2`).

## Quiz

1. What does a StatefulSet provide that a Deployment does not?
   - A. Load balancing
   - B. Stable network identities and ordered scaling
   - C. Parallel Pod creation
   - D. Automatic backups

2. What is a Headless Service?
   - A. A Service with a LoadBalancer
   - B. A Service with `clusterIP: None`
   - C. A Service with NodePort
   - D. A Service with ExternalName

3. What happens when a StatefulSet is deleted?
   - A. Pods and PVCs are deleted
   - B. Pods are deleted, PVCs persist
   - C. Only Pods are deleted
   - D. Nothing happens

4. What is the default `podManagementPolicy`?
   - A. Parallel
   - B. OrderedReady
   - C. Serial
   - D. Random

5. When would you use `podManagementPolicy: Parallel`?
   - A. For databases
   - B. For applications that can start simultaneously
   - C. For web servers
   - D. Never

Answers: 1-B, 2-B, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- StatefulSets are for stateful applications (databases, queues).
- They provide sticky identities (`db-0`, `db-1`).
- They require a Headless Service (`clusterIP: None`) for direct DNS resolution.
- `OrderedReady` ensures Pod N+1 is not created until Pod N is Ready. If Pod 0 fails, the rollout freezes.
- They use `volumeClaimTemplates` to automatically generate a unique PVC for every single Pod.

Memory trick:

- Deployment: Cattle. Replaceable, random names.
- StatefulSet: Pets. Named, cared for individually, hard to replace.
- OrderedReady: A staircase. Can't build step 2 until step 1 is dry.

Key facts:

- StatefulSet = Sticky names + Ordered boot + Unique disks.
- Headless Service = `clusterIP: None` (DNS per Pod).
- Deleting StatefulSet does NOT delete PVCs.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl get statefulset` | Lists StatefulSets |
| `kubectl describe statefulset <name>` | Shows StatefulSet details and events |
| `kubectl scale statefulset <name> --replicas=5` | Scales a StatefulSet |
| `kubectl get pvc` | Check for PVCs generated by `volumeClaimTemplates` |
| `kubectl delete statefulset <name>` | Deletes a StatefulSet (does NOT delete PVCs!) |
| `kubectl run -it --rm dns-test --image=busybox -- nslookup <pod>.<svc>` | Tests Headless Service DNS |

## References

- [Kubernetes Documentation: StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Kubernetes Documentation: Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)
- [Kubernetes Documentation: Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Kubernetes Documentation: Pod Anti-Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#pod-affinity-and-anti-affinity)

## Related Lessons

- [Lesson 6 - Pods, ReplicaSets, and Deployments](lesson-06-pods-replicasets-and-deployments.md) - for stateless workloads.
- [Lesson 9 - DaemonSets](lesson-09-daemonsets.md) - for node-level infrastructure.
- [Lesson 6 - Jobs and CronJobs](lesson-10-jobs-and-cronjobs.md) - for batch workloads.
- [Lesson 16 - Persistent Storage (PVs, PVCs, and StorageClasses)](../05-storage/lesson-19-persistent-storage-pv-pvc-sc.md) - PVs, PVCs, and StorageClasses.
- [Module 12 - Production](../12-production/README.md) - production hardening.

## Coming Next

Now that you understand StatefulSets for stateful workloads, the next lesson covers DaemonSets, which ensure a Pod runs on every node in the cluster.
