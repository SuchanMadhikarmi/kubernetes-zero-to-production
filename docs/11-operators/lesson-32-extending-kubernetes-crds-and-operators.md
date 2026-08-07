---
title: Lesson 32 - Extending Kubernetes (CRDs and Operators)
module: 11 Operators
lesson: 32
status: Complete
tags: [kubernetes, crd, custom-resource, operator, controller, reconciliation, extensibility, production]
---

# Lesson 32 - Extending Kubernetes (CRDs and Operators)

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

- Explain how Kubernetes is natively extensible.
- Define a Custom Resource Definition (CRD) that teaches the API Server a new object type.
- Distinguish a Custom Resource (CR) from its CRD.
- Explain the Operator Pattern, which teaches Kubernetes how to manage that new object.
- Intentionally create a Custom Resource before the CRD exists and watch the API Server reject it.

## Prerequisites

- Completion of Lessons 1 through 31.
- A running kind cluster.
- `kubectl` installed and configured.
- A working understanding of the API Server and etcd from Module 02.

## Real-world Motivation

### The Operational Nightmare

Imagine you need to deploy a highly available PostgreSQL database cluster. It requires 3 Pods, each with its own persistent disk. You need to handle backups, initialize replicas, and manage failover if the master node dies. If you try to do this with raw Deployments and StatefulSets, you have to manually run SQL scripts to initialize replication. If a node crashes, a human must manually promote a replica to master. This does not scale.

### Why This Exists

Kubernetes needed a way to encode human operational knowledge into software. Operators solve this. An Operator is a custom controller that watches a Custom Resource (for example, a `PostgresCluster` object). When you create that object, the Operator automatically does the complex work: creating PVCs, initializing the database, and handling failover automatically.

### Real Company Examples

**Twitter:** Twitter uses the Prometheus Operator. Instead of manually creating ConfigMaps and Deployments for Prometheus, they just create a `Prometheus` CR. The Operator automatically scales Prometheus, manages its storage, and updates its scrape configurations dynamically.

## Core Concepts

### Explain Like I'm 12

Kubernetes comes out of the box knowing about Pods, Services, and Deployments.

- A CRD is like giving Kubernetes a new dictionary with a new word in it: "Database".
- An Operator is a robot you hire. When you say "I want a Database", the robot reads the dictionary, understands what a Database is, and goes and builds all the Pods and disks required to make it real.

### Explain Like I'm a Junior Engineer

A CRD is a YAML file that defines a new API resource type. It tells the API Server to accept a new kind of object. A Custom Resource (CR) is an instance of that CRD. An Operator is a custom controller (a Pod running code) that watches CRs. When you create a CR, the Operator sees it and runs its logic to create the actual Deployments and PVCs.

### Explain Technically

- **CRD:** `apiextensions.k8s.io/v1`. It defines the spec schema (using OpenAPI v3) for the new resource. The API Server dynamically adds a new RESTful endpoint (for example, `/apis/mycompany.com/v1/namespaces/default/databases`).
- **Operator Pattern:** A custom controller using the Kubernetes reconciliation loop. It continuously compares the Desired State (the Custom Resource) with the Live State (the actual Deployments/PVCs) and takes actions to align them.

### How Kubernetes Implements It Internally

When you apply a CRD, the API Server's `apiextensions-apiserver` validates the schema. The API Server then dynamically registers a new API path. `kubectl get` and `kubectl apply` work natively with this new path. CRs are stored in etcd just like standard resources. The Operator runs as a Pod, using the `client-go` library to watch the API Server for changes to its CR.

### Why Kubernetes Was Designed That Way

Kubernetes is a platform for platforms. Rather than special-casing every database or queue, it exposes a generic extension mechanism. The core API handles everything with the same lifecycle (admission, validation, storage, reconciliation), and operators plug in domain logic on top. This keeps the core stable while allowing the ecosystem to grow arbitrarily.

## Architecture

Extending Kubernetes requires two parts:

1. The CRD teaches the API Server to accept a new object type.
2. The Operator (custom controller) watches those objects and takes action.

```
[ Developer: kubectl apply -f my-db.yaml ] (kind: MyDatabase)
      |
      v
[ API Server ] -> "Is 'MyDatabase' a valid kind?" -> No (if CRD missing)
                -> "Yes" -> Saves to etcd.
      |
      v (Operator watches API Server)
[ Operator Pod ] "I see a new MyDatabase CR!"
      |
      v (Operator translates logic)
[ API Server ] -> "Create a Deployment" + "Create a PVC"
```

### Terminology

| Term | Definition |
|------|------------|
| CRD | Custom Resource Definition. The schema/blueprint for a new Kubernetes object. |
| CR | Custom Resource. An instance of a CRD stored in etcd. |
| Operator | A custom controller that manages Custom Resources. |
| Reconciliation Loop | The continuous process of comparing desired state vs actual state and fixing differences. |
| apiVersion | The API group and version of a resource, for example `stable.example.com/v1`. |

### How It Works Internally

1. You apply a CRD YAML.
2. The API Server validates the OpenAPI schema.
3. The API Server registers a new REST endpoint (for example, `/apis/stable.example.com/v1/crontabs`).
4. You apply a CR YAML (`kind: CronTab`).
5. The API Server validates the CR against the CRD schema. If it passes, it saves it to etcd.
6. The Operator Pod (running a SharedInformer) detects the new CR.
7. The reconciliation loop triggers. It reads the CR spec and creates standard Kubernetes resources (Pods, Services) to fulfill the request.

### Step-by-Step Workflow

1. Admin installs the CRD to the cluster.
2. Admin deploys the Operator Pod.
3. Developer creates a Custom Resource (CR).
4. The API Server saves the CR to etcd.
5. The Operator detects the CR.
6. The Operator creates Deployments/PVCs to satisfy the CR.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | A CR is created. The Operator detects it and provisions resources. |
| Update | The CR spec changes (e.g., `replicas: 3` to `replicas: 5`). The Operator detects the diff and scales the underlying Deployment. |
| Deletion | The CR is deleted. The Operator detects the deletion and cleans up the underlying resources (Pods, PVCs) unless a finalizer holds them. |

### Communication Patterns

| Communication | Mechanism | Example |
|---------------|-----------|---------|
| kubectl -> API Server | Apply CRD | `POST /apis/apiextensions.k8s.io/v1/customresourcedefinitions` |
| kubectl -> API Server | Create CR | `POST /apis/stable.example.com/v1/namespaces/default/crontabs` |
| Operator -> API Server | Watch CRs | SharedInformer on `stable.example.com/v1` |
| Operator -> API Server | Reconcile resources | Create/update Deployments, PVCs |

### Common Myths

| Myth | Fact |
|------|------|
| "Operators are just Helm charts." | False. Helm renders YAML once. An Operator is a running controller managing the application's lifecycle forever. |
| "You must write Go to create an Operator." | False. Go is most common (Operator SDK), but you can write Operators in Python, Ansible, or Helm using the Operator Framework. |

## ASCII Diagrams

Mental Model: The Kubernetes API Server is a database. A CRD is a `CREATE TABLE` command. A CR is an `INSERT INTO`. The Operator is a background trigger that wakes on a new row and does the work.

```text
[ User: kubectl apply -f my-db.yaml ] (kind: CronTab)
      |
      v
[ API Server ] -> "Is 'CronTab' a valid kind?" -> No (if CRD missing)
                -> "Yes" -> Saves to etcd.
      |
      v (Operator watches API Server)
[ Operator Pod ] "I see a new CronTab CR!"
      |
      v (Operator translates logic)
[ API Server ] -> "Create a Pod" + "Create a ConfigMap"
```

## Hands-on

### Objective

Create a CRD that lets us define a `CronTab`, then try to create a Custom Resource before the CRD exists to see the API rejection.

### Step 1: Break Things on Purpose

Create `broken-crontab.yaml`:

```yaml
apiVersion: stable.example.com/v1
kind: CronTab
metadata:
  name: my-cron
spec:
  cronSpec: "* * * * */5"
```

Try to apply it:

```bash
kubectl apply -f broken-crontab.yaml
```

**Your Task:**

1. What error message did the API Server return?
2. Why did the API Server reject this YAML? What is missing?

(Answer: 1. `error: unable to recognize "broken-crontab.yaml": no matches for kind "CronTab" in version "stable.example.com/v1"`. 2. The API Server is strictly typed. It searches its internal registry for a schema matching kind `CronTab` in API group `stable.example.com/v1`. It found nothing, so it rejected the request. The CRD is missing.)

### Step 2: Install the CRD

Create `crontab-crd.yaml`:

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: crontabs.stable.example.com   # Must be <plural>.<group>
spec:
  group: stable.example.com
  scope: Namespaced
  names:
    plural: crontabs
    singular: crontab
    kind: CronTab
    shortNames:
    - ct
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              cronSpec:
                type: string
```

Apply it:

```bash
kubectl apply -f crontab-crd.yaml
```

### Step 3: Verify the API Server Learned It

Wait about 5 seconds for the API Server to register the new endpoint, then run:

```bash
kubectl get crontabs
```

It should say `No resources found` in the default namespace instead of throwing an error.

### Step 4: Create the Custom Resource

Now that the API Server knows what a `CronTab` is, apply your original YAML again:

```bash
kubectl apply -f broken-crontab.yaml
```

Verify it was saved to etcd:

```bash
kubectl get ct
```

You should see `my-cron` listed.

### Cleanup

```bash
kubectl delete crontab my-cron
kubectl delete -f crontab-crd.yaml
```

## Commands

```bash
# List all Custom Resource Definitions
kubectl get crd

# List instances of a Custom Resource (e.g., kubectl get crontabs, or short name)
kubectl get <custom-plural-name>

# Describe a CRD
kubectl describe crd crontabs.stable.example.com

# Check which API groups and versions are served
kubectl api-resources | grep stable
```

## YAML Explanation

### The CRD

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: crontabs.stable.example.com
spec:
  group: stable.example.com
  scope: Namespaced
  names:
    plural: crontabs
    singular: crontab
    kind: CronTab
    shortNames:
    - ct
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              cronSpec:
                type: string
```

### Field-by-Field Explanation

- `metadata.name`: Must be the plural name followed by the group (`crontabs.stable.example.com`).
- `spec.group`: The API group (for example, `stable.example.com`).
- `spec.scope`: `Namespaced` or `Cluster`. Determines whether instances live in a namespace.
- `spec.names`: `plural`, `singular`, `kind`, and optional `shortNames` (`ct`) for quick `kubectl` access.
- `spec.versions` `name`, `served`, `storage`: a CRD can serve multiple versions; only one is used for storage.
- `schema.openAPIV3Schema`: the schema that validates the CR. It enforces that `spec.cronSpec` is a string.

### The Custom Resource

```yaml
apiVersion: stable.example.com/v1
kind: CronTab
metadata:
  name: my-cron
spec:
  cronSpec: "* * * * */5"
```

The `apiVersion` and `kind` must exactly match the CRD's `group`, `version`, and `kind`. The `spec` is validated against the CRD `openAPIV3Schema`.

## Production Notes

- Use existing operators: don't write your own operator for PostgreSQL or Redis. Use battle-tested ones like CrunchyData Postgres Operator or Strimzi Kafka Operator.
- Version your CRDs: CRDs have versions (`v1alpha1`, `v1beta1`, `v1`). Provide a conversion webhook if you make breaking schema changes.
- Use finalizers: if a user deletes a CR, the Operator should use a finalizer to clean up external resources (cloud DNS records, S3 buckets) before removing the CR from etcd.
- A CR is stored in etcd: deleting a `PostgresCluster` CR tells the Operator to destroy the database, including underlying PVCs. Communicate CR deletion semantics to your team.

### When to Use / When NOT to Use

**Use an Operator when:**

- Managing stateful applications (databases, message queues).
- Applications need complex lifecycle management (backups, restore, upgrades).
- Automating repetitive operational tasks.

**Avoid an Operator when:**

- Managing stateless web applications: a Deployment + Helm chart is sufficient.
- The application does not require custom operational logic.

### Performance and Security Considerations

**Performance:** CRDs are stored in etcd. Creating thousands of CRs increases the etcd database size and can slow the API Server.

**Security:** Operators often require broad RBAC (creating/deleting Deployments, PVCs). If an Operator Pod is compromised, an attacker can destroy many resources. Lock down the Operator's ServiceAccount.

## Best Practices

- Install the CRD and the Operator before creating any CRs.
- Use well-established operators from OperatorHub and the CNCF ecosystem.
- Version CRDs cycle; register conversion webhooks when breaking.
- Use `openAPIV3Schema` validation with `additionalProperties: false` to reject typos in the spec.
- Scope operators and their RBAC to the minimum necessary (namespaced Role, not ClusterRole, when possible).
- Set finalizers on any CR that owns external resources.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Creating a CR before the CRD | The API Server has no schema for the kind and rejects it | Install the CRD first, or wait for the Operator registration |
| Treating CRs as trivial state | A CR deletion triggers the Operator to delete backing resources | Document CR deletion semantics and watch for permanent data loss |
| Building an Operator for a stateless app | A Deployment can do it with Helm, no extra machinery | Let controllers you already use manage them |
| Over-broad Operator RBAC | Operator needs CRUD on many kinds, tempting broad permissions | Scope to a namespace and least-privilege Role |

## Troubleshooting

**Symptom: `no matches for kind`**

You try to apply YAML for a CRD-based object and get `no matches for kind`.

Check the CRD:

```bash
kubectl get crd | grep -i <kind>
```

Is the CRD actually installed? Operators sometimes take a moment to register their CRDs after install. Also check that `apiVersion` in your YAML matches the CRD's group and version exactly.

**Symptom: The Operator is not taking action**

You created a CR but no Pods are created.

```bash
kubectl get pods -n <operator-namespace>
```

Is the Operator Pod running, or is it crashing?

```bash
kubectl logs -n <operator-namespace> <operator-pod>
```

The Operator might be failing to create Deployments because its RBAC permissions are insufficient.

## Interview Questions

**Q: What is a Kubernetes Operator?**

A: A custom controller that extends Kubernetes to manage a specific stateful application. It uses a CRD to define a new resource type and a reconciliation loop to ensure the actual state matches the desired state defined in the Custom Resource.

**Q: What is the difference between a CRD and a CR?**

A: A CRD (Custom Resource Definition) is the schema that teaches the API Server about a new object type. A CR (Custom Resource) is an actual instance of that type, stored in etcd.

**Q: What happens if you apply a Custom Resource before the CRD is installed?**

A: The API Server rejects it with an error like `no matches for kind "CronTab" in version "stable.example.com/v1"`, because the schema for that kind does not exist yet.

**Q: How does an Operator know when a Custom Resource is created?**

A: It runs a SharedInformer that watches the API Server for changes to its kind. A new CR triggers the reconciliation loop.

**Q: How are CRs and CRDs stored?**

A: Both the definitions (CRDs) and the instances (CRs) are stored in etcd.

**Q: True or False: Operators replace Deployments.**

A: False. Operators often create and manage Deployments rather than replacing them.

## Scenario Questions

**Scenario 1:** You need to run a PostgreSQL cluster in Kubernetes with automated backups and failover. How do you implement this?

A: I install a PostgreSQL Operator (like CrunchyData PGO). The Operator registers a `PostgresCluster` CRD. I create a `PostgresCluster` CR specifying replicas, storage size, and backup schedule. The Operator watches this CR and creates the StatefulSets, PVCs, and CronJobs required to run the database and handle failover.

**Scenario 2 (Mini Project - The CRD Explorer):**

Install Cert-Manager, a popular operator:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
```

Then:

```bash
kubectl get crd | grep cert-manager
```

Create a `Certificate` CR (per the Cert-Manager docs) and watch the Operator create the TLS Secret automatically.

## Quiz

1. What does a CRD do?
   - A. Scales a Deployment
   - B. Defines a new API resource type the API Server can accept
   - C. Manages a StatefulSet
   - D. Creates the etcd database

2. What is a Custom Resource?
   - A. An instance of a CRD stored in etcd
   - B. A subclass of a Pod
   - C. A new type of container runtime
   - D. A storage class

3. What happens if you apply a CR before the CRD is defined?
   - A. It is created immediately
   - B. The API ignores everything and crashes
   - C. The API Server rejects it with `no matches for kind`
   - D. The scheduler stops

4. What does an Operator do?
   - A. Scales the API Server
   - B. Runs a reconciliation loop for a custom resource
   - C. Backs up the cluster
   - D. Writes manifests to GitHub

5. Which CRD example best teaches the API Server a new "noun"?
   - A. `kind: CronTab` under a custom group
   - B. `kind: ConfigMap`
   - C. `kind: Secret`
   - D. `kind: Deployment`

Answers: 1-B, 2-A, 3-C, 4-B, 5-A.

## Revision

One-minute revision:

- CRD = the dictionary definition.
- CR = the sentence that uses the word.
- Operator = the worker that does the job.
- Install the CRD before the CR.
- Operators encode operational knowledge.

Memory trick:

- **CRD:** the dictionary entry. ("A CronTab is a word that means a scheduled job.")
- **CR:** the sentence using the word. ("I have a CronTab that runs at 5 AM.")
- **Operator:** the worker reading the sentence and actually doing the job.

Key facts:

- CRDs are valid in the apiExtension API. CRs are stored in etcd.
- The API Server validates CRs against the CRD's OpenAPI schema.
- Operators run a reconciliation loop, not a one-time rendering.
- Deleting a CR can delete backing resources; use finalizers.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl get crd` | Lists all Custom Resource Definitions |
| `kubectl get <custom-plural-name>` | Lists instances of a Custom Resource (e.g., `kubectl get crontabs`) |
| `kubectl describe crd <name>` | Shows the CRD's schema and served versions |
| `kubectl get cr <name>` | Inspects a specific Custom Resource |

## References

- [Kubernetes Documentation: Custom Resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)
- [Kubernetes Documentation: Custom Resource Definitions](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/)
- [Kubernetes Documentation: Operator Pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
- [OperatorHub](https://operatorhub.io/)

## Related Lessons

- [Lesson 07 - Worker Node Architecture](../02-architecture/lesson-07-worker-node-architecture.md) - the API Server and control plane that hosts CRDs.
- [Lesson 27 - RBAC and Service Accounts](../07-security/lesson-27-rbac-and-service-accounts.md) - RBAC is what grants an Operator Pod the permissions it needs.
- [Lesson 31 - Locking Down the Container (Security Contexts)](../07-security/lesson-31-locking-down-the-container-security-contexts.md) - hardening a user's Operator pods.

## Coming Next

In the next lesson, you continue the GitOps module and apply operators and CRDs to a deployment workflow, seeing how the Operator's control loop compares to GitOps reconcilers.