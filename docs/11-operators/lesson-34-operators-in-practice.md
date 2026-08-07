---
title: Lesson 34 - Operators in Practice (Managing Stateful Apps)
module: 11 Operators
lesson: 34
status: Complete
tags: [kubernetes, operator, crd, custom-resource, reconciliation-loop, stateful, failover, redis, production]
---

# Lesson 34 - Operators in Practice (Managing Stateful Apps)

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

- Explain what an Operator is and how it encodes human operational knowledge into software.
- Describe how the Reconciliation Loop works for custom resources.
- Install an Operator and use it to deploy a stateful application.
- Explain how an Operator automatically recovers from failures (for example, recreating deleted Pods or StatefulSets).

## Prerequisites

- Completion of Lessons 1 through 33, specifically Lesson 32 on CRDs.
- A running kind cluster.
- `kubectl` installed and configured.
- Helm CLI installed (covered in Module 09/Lesson 15).

## Real-world Motivation

### The 3 AM Database Failover

Imagine you run a 3-node PostgreSQL database cluster. At 3 AM the master node crashes. A human on-call engineer must wake up, identify the most up-to-date replica, promote it to master, reconfigure the application to point to the new master, and recreate the missing replica. This takes 30-60 minutes and costs the company thousands of dollars per minute in downtime.

### Why This Exists

To automate operational knowledge. An Operator is a custom controller that acts like a robot system administrator. It knows exactly how to manage a specific application (like PostgreSQL). When the master node crashes, the Operator detects it in seconds, promotes a replica automatically, and reconfigures the app. No humans required.

### Real Company Examples

**Twitter:** Twitter uses the Prometheus Operator. Instead of manually creating ConfigMaps and Deployments for Prometheus, they create a `Prometheus` CR. The Operator automatically scales Prometheus, manages its storage, and updates its scrape configurations dynamically.

## Core Concepts

### Explain Like I'm 12

Imagine you have a pet dog. You need to feed it at the right time, take it to the vet for checkups, and give it medicine when sick. Now imagine you have 100 dogs. You can not manage them all yourself, so you need a robot that knows what each dog needs, feeds them automatically, and calls the vet when they are sick. An Operator is that robot for complex applications.

### Explain Like I'm a Junior Engineer

An Operator is a custom Kubernetes controller. Standard controllers (like the Deployment controller) only know how to keep N replicas of a Pod running. An Operator knows how to manage the lifecycle of a specific application. For example, the Redis Operator knows how to configure Redis replication, handle failover if a node dies, and upgrade Redis version-by-version without downtime.

### Explain Technically

An Operator uses the same machinery as built-in controllers: an informer, a workqueue, and a reconcile loop. It runs as a Pod inside the cluster. It uses the `client-go` library to watch the API Server for changes to its specific Custom Resource. When it sees a change, it executes custom business logic (written in Go, Python, or Ansible) to create, update, or delete standard Kubernetes resources (StatefulSets, Services, Secrets) to match the desired state.

### How Kubernetes Implements It Internally

Kubernetes does not know what a `RedisCluster` is. It only stores the YAML in etcd. The Operator Pod watches the API Server. When it sees a new Redis CR, it parses the spec (for example, `replicas: 3`), constructs a StatefulSet YAML, and sends it to the API Server. The standard StatefulSet controller takes over from there to create the Pods. The Operator continues watching, ready to intervene if a Pod crashes or a backup needs to be taken.

### Why Kubernetes Was Designed That Way

The reconciliation pattern is the universal mechanism Kubernetes uses to converge on desired state. By reusing the same informer/reconcile machinery that built-in controllers use, operators plug seamlessly into the control plane. The core stays generic; domain knowledge lives only in the operator. This keeps the platform stable and the ecosystem extensible.

## Architecture

An Operator is a Kubernetes controller (a Pod running code) that watches a Custom Resource (CR) and takes action to ensure the cluster matches the desired state.

```
[ Developer: kubectl apply -f redis-cluster.yaml ] (Custom Resource)
      |
      v
[ API Server ] -> [ etcd ] (Saves the CR)
      |
      v (Operator watches API Server)
[ Operator Pod ] "I see a new Redis CR!"
      |
      v (Operator translates logic)
[ API Server ] -> "Create a StatefulSet" + "Create a Service" + "Create ConfigMaps"
```

### Terminology

| Term | Definition |
|------|------------|
| Operator | A custom controller that manages a specific application lifecycle. |
| Reconciliation Loop | The continuous process of comparing Desired State (the CR) with Live State (the actual Pods/Services) and fixing differences. |
| CRD | Custom Resource Definition. The schema for the object the Operator watches. |
| CR | Custom Resource. The instance of the CRD. |
| Domain Knowledge | The Operator-specific logic (backup, bootstrap, failover) for an application. |
| Control Plane | The Operator that manages the application. |
| Data Plane | The Pods the Operator creates and runs. |

### How It Works Internally

1. You install the Redis Operator. It registers the Redis CRD with the API Server.
2. You create a Redis CR with `replicas: 3`.
3. The Operator's SharedInformer detects the new CR.
4. The Reconciliation Loop triggers.
5. The Operator sees 0 StatefulSet replicas, but 3 are desired.
6. The Operator constructs a StatefulSet YAML and sends it to the API Server.
7. The StatefulSet controller creates the 3 Pods.
8. The Operator waits. If a Pod dies, the Operator detects the diff and creates a new one.

### Step-by-Step Workflow

1. Admin installs the Operator (via Helm or YAML).
2. The Operator registers its CRDs.
3. A developer creates a Custom Resource (CR).
4. The Operator detects the CR.
5. The Operator creates Deployments, StatefulSets, Services, and PVCs to satisfy the CR.
6. The Operator continuously monitors the created resources for health and scaling.

### Lifecycle

| State | Description |
|-------|-------------|
| Provisioning | A CR is created. The Operator provisions the application. |
| Scaling | Developer changes `replicas: 3` to `replicas: 5`. The Operator detects the change and updates the StatefulSet. |
| Failover | A Pod crashes. The Operator detects it and orchestrates recovery (for example, promoting a replica). |
| Upgrade | Developer changes `version: 7.0` to `7.2`. The Operator performs a rolling update and any schema migrations. |
| Deletion | A CR is deleted. The Operator cleans up resources, often using Finalizers to ensure external cleanup. |

### Communication Patterns

| Communication | Mechanism | Example |
|---------------|-----------|---------|
| Operator -> API Server | Watch CRs | SharedInformer on the Operator's kind |
| Operator -> API Server | Create StatefulSet | `POST /apis/apps/v1/namespaces/default/statefulsets` |
| StatefulSet controller -> API Server | Create Pods | Owns and reconciles the Pods |
| Operator -> CR status | Report progress/errors | `status.conditions` on the CR |

### Common Myths

| Myth | Fact |
|------|------|
| "Operators are just Helm charts." | False. Helm renders YAML once. An Operator is a continuously running controller managing the lifecycle forever. |
| "You must write Go to create an Operator." | False. Go is most common (Operator SDK), but you can write Operators in Python, Ansible, or Helm. |

## ASCII Diagrams

Mental Model: An Operator is a specialized manager for a specific application.

```text
+-------------------------------------------------------------+
|                    Kubernetes Cluster                        |
|                                                             |
|  +-----------------+           +------------------------+   |
|  | Custom Resource |           |      Operator Pod       |   |
|  | (e.g. Redis)    | --------> |  (Controller)           |   |
|  |                 |  Watch    |                         |   |
|  | spec:           |           |  Reconcile Loop:        |   |
|  |  replicas: 3    |           |  1. Compare desired vs  |   |
|  |  version: 7.0   |           |     actual state        |   |
|  +-----------------+           |  2. Create/update Pods  |   |
|                                |  3. Handle failures     |   |
|                                |  4. Perform backups     |   |
|                                +-----------+-------------+   |
|                                            |                 |
|                                            v                 |
|  +------------------------------------------------------+   |
|  |                  Manages                              |   |
|  |  +--------+  +----------+  +----------+  +---------+ |   |
|  |  | Pods   |  | Services |  |ConfigMaps|  | Secrets | |   |
|  |  +--------+  +----------+  +----------+  +---------+ |   |
|  +------------------------------------------------------+   |
+-------------------------------------------------------------+
```

## Hands-on

### Objective

Install the Redis Operator, create a Redis cluster, and watch the Operator automatically recover from a disaster.

### Step 1: Install the Redis Operator

We use the OT Container Kit Redis Operator via Helm.

```bash
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/
helm repo update
helm install redis-operator ot-helm/redis-operator --namespace redis-operator-system --create-namespace
```

Wait for the Operator Pod to be running:

```bash
kubectl get pods -n redis-operator-system
```

### Step 2: Create a Redis Cluster

Create `redis-cluster.yaml`:

```yaml
apiVersion: redis.opstreelabs.in/v1beta2
kind: Redis
metadata:
  name: my-redis
spec:
  redis:
    replicas: 3
    image: redis:7.0-alpine
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
  kubernetesConfig:
    imagePullPolicy: IfNotPresent
    updateStrategy:
      type: RollingUpdate
```

Apply it:

```bash
kubectl apply -f redis-cluster.yaml
```

### Step 3: Watch the Operator Create Resources

Watch the Redis Pods being created automatically by the Operator:

```bash
kubectl get pods -l app=my-redis -w
```

Wait until 3 Pods are `Running`, then press Ctrl+C.

Check the StatefulSet the Operator created:

```bash
kubectl get statefulset
```

### Step 4: Break Things on Purpose

Simulate a crash that takes down a Redis Pod and accidentally deletes the StatefulSet.

```bash
kubectl delete pod my-redis-0
```

Watch it be recreated:

```bash
kubectl get pods -l app=my-redis -w
```

Now delete the entire StatefulSet:

```bash
kubectl delete statefulset my-redis
```

### Step 5: Investigate the Recovery

Watch the Pods again:

```bash
kubectl get pods -l app=my-redis -w
```

**Your Task:**

1. What happened when you deleted the `my-redis-0` Pod? Did it come back?
2. What happened when you deleted the entire StatefulSet? Did the Pods come back?
3. Based on the Reconciliation Loop, explain exactly what the Operator did when you deleted the StatefulSet.

(Answer: 1. Yes, the StatefulSet controller recreated it. 2. Yes, the Pods came back. 3. The Operator's reconciliation loop detected that the Live State (0 StatefulSets) did not match the Desired State (CR says 3 replicas). It immediately constructed a new StatefulSet YAML and sent it to the API Server, which recreated the Pods.)

### Step 6: Check What Happens When the Operator Dies

Scale the Operator to 0 to simulate an unavailable operator:

```bash
kubectl scale deployment redis-operator -n redis-operator-system --replicas=0
```

Now try to scale the Redis cluster:

```bash
kubectl patch redis my-redis --type='json' -p='[{"op": "replace", "path": "/spec/redis/replicas", "value": 1}]'
```

Check the StatefulSet:

```bash
kubectl get statefulset my-redis
```

The StatefulSet still shows 3 replicas. Nothing happened because the Operator is dead.

Bring the Operator back:

```bash
kubectl scale deployment redis-operator -n redis-operator-system --replicas=1
```

Wait 30 seconds, then check the StatefulSet again. The Operator sees the diff (Desired: 1, Live: 3) and scales it down to 1.

### Cleanup

```bash
kubectl delete redis my-redis
helm uninstall redis-operator -n redis-operator-system
kubectl delete namespace redis-operator-system
```

## Commands

```bash
# List instances of a Custom Resource
kubectl get redis

# Inspect the Operator's status and error messages
kubectl describe redis my-redis

# Check why an Operator is failing
kubectl logs -n <ns> <operator-pod>

# Check the CRDs the Operator registered
kubectl get crd | grep redis
```

## YAML Explanation

```yaml
apiVersion: redis.opstreelabs.in/v1beta2
kind: Redis
metadata:
  name: my-redis
spec:
  redis:
    replicas: 3
    image: redis:7.0-alpine
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
  kubernetesConfig:
    imagePullPolicy: IfNotPresent
    updateStrategy:
      type: RollingUpdate
```

### Field-by-Field Explanation

- `apiVersion`: the API group and version registered by the Operator's CRD.
- `kind: Redis`: the Custom Resource introduced by the Operator.
- `spec.redis.replicas: 3`: the desired Redis replica count that the Operator enforces.
- `spec.redis.image`: the container image the Operator will use for the Redis Pods.
- `resources.requests`/`limits`: the size of the Pods the Operator creates.
- `kubernetesConfig.updateStrategy`: how the Operator updates the replicated Redis (rolling update).

## Production Notes

- Use existing operators. Do not write your own for PostgreSQL or Kafka. Use battle-tested ones: CrunchyData PGO, Strimzi, the Prometheus Operator.
- RBAC is critical. Operators need broad permissions; lock down the Operator's ServiceAccount so it can only manage resources in specific namespaces.
- Watch out for deletion. Deleting a CR (for example, `kubectl delete redis my-cluster`) tells the Operator to destroy everything, including the underlying PVCs. Communicate this risk.
- An Operator dying freezes lifecycle management (scaling, backup, recovery) even though the workload keeps running. Monitor operator Pods like production workloads.

### When to Use / When NOT to Use

**Use an Operator when:**

- Managing stateful applications (PostgreSQL, MySQL, Cassandra, Kafka, Redis).
- Applications need complex lifecycle management (backups, restore, upgrades, failover).
- Automating repetitive operational tasks.

**Avoid an Operator when:**

- Managing stateless web applications: a Deployment + Helm chart is sufficient.
- The application does not require custom operational logic.

### Performance and Security Considerations

**Performance:** Operators poll the API Server. A poorly written Operator that polls too frequently can overload the API Server.

**Security:** Operators require broad RBAC (creating/deleting Deployments, PVCs). If the Operator Pod is compromised, the attacker can destroy many resources. Lock down the Operator's ServiceAccount.

## Best Practices

- Prefer established operators from OperatorHub / CNCF over in-house ones.
- Scope the Operator's ServiceAccount to a namespace and least-privilege role.
- Isolate critical operators behind their own namespace.
- Monitor the Operator Pod and its CR status as production workloads.
- Test CR deletion behavior before rolling out to real data.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Treating CRs as unimportant | The CR is the source of truth; deleting it deletes the app | Document CR deletion semantics; add backups/finalizers |
| Building an Operator for a stateless app | A Deployment handles stateless work | Use it only for stateful applications with Day-2 needs |
| Ignoring Finalizers | External cleanup needs finalizers; missing them leaks cloud resources | Ensure the Operator sets finalizers on its CRs |
| Over-scoping Operator RBAC | Operators need broad perms, tempting ClusterRole | Bind to namespace-scoped Role |

## Troubleshooting

**Symptom: Operator is not taking action**

You create a CR, but no Pods appear.

Check the Operator Pod:

```bash
kubectl get pods -n <operator-namespace>
```

Is it `Running` or `CrashLoopBackOff`?

```bash
kubectl logs -n <operator-namespace> <operator-pod>
```

The Operator may lack RBAC to create Deployments. Check the CR status field, which usually contains the Operator's state and errors:

```bash
kubectl describe redis my-redis
```

**Symptom: The CR hangs in Terminating**

An Operator using finalizers to clean up external resources (for example, S3 buckets) cannot finalize because the Operator Pod is down. Restore the Operator before deleting the CR.

## Comparison Table

| Feature | Helm Chart | Operator |
|---------|-----------|----------|
| What it does | Renders YAML and applies it once | Continuously manages the application lifecycle |
| Day 2 Operations | None. Manual upgrades/backups | Automated: backups, failover, upgrades |
| State | Stateless one-shot install | Watches the cluster continuously |
| Use Case | Installing an app | Running a production database cluster |

## Interview Questions

**Q: What is a Kubernetes Operator?**

A: A custom controller that extends Kubernetes to manage a specific stateful application. It defines a desired state with a CRD and a reconciliation loop that ensures the actual state matches, automating backups, scaling, and failover.

**Q: Why use an Operator instead of a Helm chart?**

A: Helm installs an application once but does not manage its lifecycle. An Operator runs continuously handles Day 2 operations like backups, scaling, and failover, which Helm cannot.

**Q: How does an Operator detect a crashed Pod?**

A: It runs a SharedInformer that watches the API Server. When a Pod's status changes to Failed or the Pod is deleted, the informer triggers the reconciliation loop, which creates a new Pod to restore the desired replica count.

**Q: What happens if the Operator Pod crashes?**

A: The application remains running, but lifecycle management (scaling, recovery, backups) stops until the Operator Pod is restarted.

**Q: True or False: Operators replace Deployments.**

A: False. Operators often create and manage Deployments or StatefulSets.

## Scenario Questions

**Scenario 1:** You need a PostgreSQL cluster with automated backups and failover. How do you implement it?

A: Install a PostgreSQL Operator (for example, CrunchyData PGO), which registers a `PostgresCluster` CRD. Create a `PostgresCluster` CR specifying replicas, storage size, and backup schedule. The Operator watches the CR and creates the StatefulSets, PVCs, and CronJobs to run the database and handle failover.

**Scenario 2 (Mini Project - The Prometheus Operator):**

Install the Prometheus Operator via Helm (`kube-prometheus-stack`). Create a `Prometheus` CR. Verify the Operator creates the Prometheus Pods, then delete the Prometheus Pod and watch the Operator recover it.

## Quiz

1. What is a Kubernetes Operator?
   - A. A web debugger
   - B. A Helm chart for all apps
   - C. A custom controller managing a specific stateful app
   - D. A wrapper around etcd

2. Which loop does an Operator use?
   - A. Event loop
   - B. Reconciliation loop
   - C. Polling loop
   - D. Compilation loop

3. What happens if the Operator Pod crashes?
   - A. The app is deleted
   - B. The app keeps running but crashes
   - C. The app keeps running, but lifecycle management stops until restarted
   - D. The entire cluster stops

4. What does the CR commonly encode that the Operator reacts to?
   - A. The physical server model
   - B. The image and replicas of the managed app
   - C. The hardware model
   - D. The OS kernel version

5. True/False: An Operator is just a Helm chart with a longer name.
   - A. True
   - B. False

Answers: 1-C, 2-B, 3-C, 4-B, 5-B.

## Revision

One-minute revision:

- Operator = CRD + custom controller.
- Encodes human operational knowledge.
- Uses a reconciliation loop.
- Used for stateful apps.

Memory trick:

- CRD = the dictionary definition.
- CR = the sentence using the word.
- Operator = the worker reading the sentence.
- Reconciliation Loop = the worker checking that the job is still correct.

Key facts:

- Operators create standard resources (StatefulSets, Services) not the app directly.
- If the Operator dies, lifecycle management stops but the app keeps running.
- Deleting a CR tells the Operator to delete the app.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl get <custom-resource>` | Lists instances of a CR (e.g., `kubectl get redis`) |
| `kubectl describe <custom-resource> <name>` | See the Operator's status and errors |
| `kubectl logs -n <ns> <operator-pod>` | Check why an Operator is failing |

## References

- [Kubernetes Documentation: Operator Pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
- [Operator SDK Documentation](https://sdk.operatorframework.io/)
- [OperatorHub](https://operatorhub.io/)
- [OT Container Kit Redis Operator](https://github.com/OTContainerKit/redis-operator)

## Related Lessons

- [Lesson 32 - Extending Kubernetes (CRDs and Operators)](lesson-32-extending-kubernetes-crds-and-operators.md) - the CRD foundation this lesson builds on.
- [Lesson 25 - Resource Requests, Limits, and Quotas](../06-configuration/lesson-25-resource-requests-limits-and-quotas.md) - how the Operator requests resources for managed Pods.
- [Lesson 27 - RBAC and Service Accounts](../07-security/lesson-27-rbac-and-service-accounts.md) - the RBAC that grants Operators their permissions.

## Coming Next

In the next lesson we move into Module 09, Packaging, and cover Helm in depth: charts, templates, values, and how to package and distribute reusable applications.