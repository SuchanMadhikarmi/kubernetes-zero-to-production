---
title: Lesson 10 - Pods, ReplicaSets, and Deployments
module: 03 Workloads
lesson: 10
status: Complete
tags: [kubernetes, pods, replicasets, deployments, workloads, labels, selectors]
---

# Lesson 10 - Pods, ReplicaSets, and Deployments

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

- Explain why Kubernetes runs Pods instead of containers directly.
- Describe how ReplicaSets provide self-healing by guaranteeing a desired Pod count.
- Explain how Deployments manage ReplicaSets for rolling updates and rollbacks.
- Understand how Labels and Selectors link these resources together.
- Deploy, scale, and debug a Deployment using kubectl.
- Recognize when to use Deployments versus StatefulSets or bare Pods.

## Prerequisites

- Completion of Lesson 1 (understanding of containers, namespaces, and cgroups).
- A running Kubernetes cluster (see setup instructions below).
- kubectl installed and configured.

### Setting Up a Local Cluster with kind

[kind](https://kind.sigs.k8s.io/) (Kubernetes IN Docker) runs a Kubernetes cluster inside Docker containers. It is the fastest way to get a local cluster for these lessons.

**Install kind:**

```bash
# Linux (amd64)
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# macOS (Apple Silicon)
brew install kind

# macOS (Intel)
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-darwin-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

**Create a cluster:**

```bash
kind create cluster --name learning
```

**Verify it works:**

```bash
kubectl cluster-info --context kind-learning
kubectl get nodes
```

You should see one node in `Ready` state.

**Clean up when done:**

```bash
kind delete cluster --name learning
```

### Alternative: minikube

```bash
# Install
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube /usr/local/bin/minikube

# Start
minikube start

# Stop
minikube stop

# Delete
minikube delete
```

## Real-world Motivation

### The Single Point of Failure

Imagine you deploy a container running your core API. During a traffic spike, the application crashes due to a memory leak (OOMKilled, as seen in Lesson 1). Because you only had one container, your application is now completely offline. Users see 502 Bad Gateway errors until you manually SSH into the server and restart the container.

### The Configuration Drift

If you run 10 containers manually and need to update the software version, you must manually log into 10 servers and restart them one by one. This does not scale.

### Why This Exists

Kubernetes was designed to be a declarative system. Instead of saying "start 3 containers," you say "I want 3 identical application instances to always be running."

- Pods exist to group containers that need to share resources.
- ReplicaSets exist to count Pods and replace them if they die (self-healing).
- Deployments exist to safely update those Pods to a new version without downtime.

### Real Company Examples

**Spotify:** Spotify uses Deployments extensively for their backend microservices. When they release a new version of their playlist service, they update the Deployment. Kubernetes performs a rolling update, ensuring that at least 80% of their capacity is always online, meaning users never experience downtime during a release.

**Shopify:** Shopify handles massive traffic spikes during Black Friday. They pre-scale their Deployments to massive replica counts to handle the load, and the ReplicaSet controller ensures that if any node fails under pressure, the Pods are instantly rescheduled elsewhere.

## Core Concepts

### Explain Like I'm 12

Imagine a lemonade stand.

- The **Container** is the actual lemonade drink.
- The **Pod** is the cup holding the lemonade.
- The **ReplicaSet** is the tray. You want exactly 3 cups on the tray at all times. If a cup falls and spills, the ReplicaSet instantly puts a new cup on the tray.
- The **Deployment** is the recipe book. If you decide to change from regular lemonade to pink lemonade, the Deployment slowly replaces the old cups one by one until the whole tray is pink lemonade.

### Explain Like I'm a Junior Engineer

You don't deploy containers; you deploy Pods. A Pod gives the container a stable IP address and hostname. However, Pods are mortal. If a node crashes, the Pod is gone forever.

To ensure your app stays online, you use a Deployment. The Deployment creates a ReplicaSet. The ReplicaSet uses a Label Selector (e.g., `app=frontend`) to constantly scan the cluster. If it sees only 2 Pods with the frontend label when it expects 3, it asks the API server to create a 3rd.

### Explain Technically

- **Deployment:** A high-level controller object. When you update the `spec.template` (e.g., changing the image tag), the Deployment controller creates a new ReplicaSet. It scales up the new ReplicaSet and scales down the old one, performing a rolling update.
- **ReplicaSet:** A controller that ensures a specified number of Pod replicas are running at any given time. It relies heavily on the `spec.selector.matchLabels` field to map to its Pods.
- **Pod:** A logical host. Containers inside the same Pod share the same Network namespace (same IP, same ports) and IPC namespace, meaning they can talk to each other via localhost.

### How Kubernetes Implements It Internally

The `kube-controller-manager` runs a `DeploymentController` and a `ReplicaSetController`.

When you apply a Deployment YAML, the API Server saves it to etcd. The DeploymentController notices it, creates a ReplicaSet, and saves that to etcd. The ReplicaSetController notices the new ReplicaSet, looks at its selector, counts existing Pods, and asks the API Server to create the missing Pods. The kube-scheduler then assigns those Pods to nodes, and the kubelet on those nodes starts the containers.

### Why Kubernetes Was Designed That Way

Kubernetes uses a "Russian Nesting Doll" architecture for workloads. You never interact with containers directly in production. This layered approach provides:

- **Separation of concerns:** Each layer handles one thing well.
- **Extensibility:** You can swap controllers without changing the Pod spec.
- **Safety:** The reconciliation loop at each layer ensures desired state is always met.

## Architecture

```
┌─────────────────────────────────────────┐
│ Deployment (The Manager)                │
│  - Defines: Image version, Replicas: 3  │
│  - Handles: Rolling Updates, Rollbacks  │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │ ReplicaSet (The Supervisor)       │  │
│  │  - Uses Labels to track Pods      │  │
│  │  - Replaces dead Pods             │  │
│  │                                   │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │ Pod 1 (app=web)             │  │  │
│  │  │  ┌───────────────────────┐  │  │  │
│  │  │  │ Container (nginx)     │  │  │  │
│  │  │  └───────────────────────┘  │  │  │
│  │  └─────────────────────────────┘  │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │ Pod 2 (app=web)             │  │  │
│  │  │  ┌───────────────────────┐  │  │  │
│  │  │  │ Container (nginx)     │  │  │  │
│  │  │  └───────────────────────┘  │  │  │
│  │  └─────────────────────────────┘  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### Terminology

| Term | Definition |
|------|------------|
| Pod | The smallest, simplest deployable Kubernetes object. A group of one or more containers. |
| ReplicaSet (RS) | A controller that ensures a specified number of pod replicas are running at any given time. |
| Deployment | A controller that manages ReplicaSets, providing declarative updates to Pods. |
| Labels | Key/value pairs attached to objects (like Pods) used for organizing and selecting subsets. |
| Selectors | The query used by controllers to find objects with specific labels. |
| Desired State | The configuration you declare (e.g., "I want 3 Pods"). |
| Actual State | What is currently running in the cluster. |
| Reconciliation Loop | The continuous background process of checking Actual state against Desired state and fixing differences. |

### How It Works Internally

Kubernetes relies on the concept of a Reconciliation Loop.

1. The ReplicaSet controller polls the API Server every few seconds.
2. It asks: "How many Pods currently exist with the label `app=web`?"
3. It compares this Actual State to the Desired State (e.g., `replicas: 3`).
4. If Actual < Desired, it creates Pods.
5. If Actual > Desired, it deletes Pods.

This loop ensures that if a node crashes (removing 2 Pods), the controller instantly detects the discrepancy and creates 2 new Pods on healthy nodes.

### Step-by-Step Workflow

1. Developer writes a Deployment YAML declaring `replicas: 3` and `image: nginx:1.25`.
2. `kubectl apply` sends this to the API Server.
3. API Server validates the YAML and stores it in etcd.
4. DeploymentController creates a ReplicaSet (version 1).
5. ReplicaSetController sees it wants 3 Pods, finds 0, and creates 3 Pods.
6. Scheduler assigns those Pods to nodes.
7. Kubelet on the nodes pulls the image and starts the containers.
8. Developer updates the YAML to `image: nginx:1.26`.
9. DeploymentController creates ReplicaSet (version 2).
10. RS v2 creates 1 Pod (`nginx:1.26`). RS v1 deletes 1 Pod (`nginx:1.25`).
11. Process repeats until RS v2 has 3 Pods and RS v1 has 0.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | YAML is applied. Pods are scheduled and started. |
| Scaling | `replicas` field is changed. Controller creates/deletes Pods to match. |
| Updating | Pod template is changed. A new ReplicaSet is created, and traffic is gradually shifted. |
| Rolling Back | A previous Deployment revision is restored. The old ReplicaSet is scaled back up. |
| Deletion | Deployment is deleted. The cascading deletion removes the ReplicaSet and all its Pods. |

### Pods vs ReplicaSets vs Deployments

| Feature | Pod | ReplicaSet | Deployment |
|---------|-----|------------|------------|
| Self-Healing | No | Yes | Yes |
| Scaling | No | Yes | Yes |
| Rolling Updates | No | No | Yes |
| Rollbacks | No | No | Yes |
| Production Use | Rare (debugging) | Rare (managed by Deploy) | Yes (Standard) |

### Common Myths

| Myth | Fact |
|------|------|
| "A Pod can contain multiple different applications." | While technically true (a Pod can have multiple containers), you should not put a frontend and a backend in the same Pod. Multi-container Pods are strictly for tightly coupled helpers, like a "sidecar" that ships logs or a proxy that handles mTLS. |
| "You should use ReplicaSets directly." | ReplicaSets are managed by Deployments. Create a Deployment and let it manage the ReplicaSet for you. |
| "Pods are persistent." | Pods are mortal. If they die, they are gone forever. Use StatefulSets for stateful workloads that need stable identity. |

## ASCII Diagrams

```
[ User: kubectl apply -f deploy.yaml ]
      |
      v
[ API Server ] --> [ etcd ] (Desired: 3 Pods)
      |
      v
[ Deployment Controller ] (Creates ReplicaSet)
      |
      v
[ ReplicaSet Controller ] (Counts Pods: 0. Creates 3 Pods)
      |
      v
[ Scheduler ] -> [ Kubelet on Node A ] -> Starts Container 1
[ Scheduler ] -> [ Kubelet on Node B ] -> Starts Container 2
[ Scheduler ] -> [ Kubelet on Node B ] -> Starts Container 3
```

### Rolling Update Flow

```
Before Update:
  RS v1 (nginx:1.25) --> Pod 1, Pod 2, Pod 3

After kubectl set image deployment/nginx nginx=1.26:
  RS v1 (nginx:1.25) --> Pod 1, Pod 2
  RS v2 (nginx:1.26) --> Pod 3

After reconciliation completes:
  RS v1 (nginx:1.25) --> (scaled to 0)
  RS v2 (nginx:1.26) --> Pod 1, Pod 2, Pod 3
```

## Hands-on

### Objective

Deploy an application using a declarative YAML Deployment. Scale it, watch it self-heal, and debug a broken YAML.

### Step 1: Create the Deployment

Create `nginx-deploy.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deploy
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
```

### Step 2: Deploy

```bash
kubectl apply -f nginx-deploy.yaml
```

### Step 3: Verify the Hierarchy

```bash
kubectl get deployments
kubectl get replicasets
kubectl get pods -l app=web
```

Expected: 1 Deployment, 1 ReplicaSet, 3 Pods.

### Step 4: Test Self-Healing

Delete one Pod and watch it come back:

```bash
kubectl delete pod <POD_NAME>
kubectl get pods -l app=web --watch
```

The deleted Pod terminates, and a new one is created to maintain the count of 3.

### Step 5: Test Scaling

```bash
kubectl scale deployment nginx-deploy --replicas=5
kubectl get pods -l app=web
```

### Step 6: Test Rolling Update

```bash
kubectl set image deployment/nginx-deploy nginx=nginx:1.26-alpine
kubectl get replicasets
kubectl get pods -l app=web --watch
```

### Step 7: Test Rollback

```bash
kubectl rollout undo deployment/nginx-deploy
kubectl get pods -l app=web --watch
```

### Step 8: Cleanup

```bash
kubectl delete deployment nginx-deploy
```

## Commands

```bash
# Deploy
kubectl apply -f nginx-deploy.yaml

# List resources
kubectl get deployments
kubectl get replicasets
kubectl get pods -l app=web

# Scale
kubectl scale deployment nginx-deploy --replicas=5

# Update image
kubectl set image deployment/nginx-deploy nginx=nginx:1.26-alpine

# Rollback
kubectl rollout undo deployment/nginx-deploy

# View rollout history
kubectl rollout history deployment/nginx-deploy

# Describe for debugging
kubectl describe deployment nginx-deploy
kubectl describe replicaset <RS_NAME>
kubectl describe pod <POD_NAME>

# Delete
kubectl delete deployment nginx-deploy
```

## YAML Explanation

```yaml
apiVersion: apps/v1            # The API group for Deployments
kind: Deployment               # The object type
metadata:
  name: nginx-deploy           # The name of the Deployment
  labels:
    app: nginx                 # Label for the Deployment itself
spec:
  replicas: 3                  # DESIRED STATE: We want 3 Pods
  selector:
    matchLabels:
      app: web                 # CRITICAL: The RS will look for Pods with this label
  template:                    # The blueprint for the Pods
    metadata:
      labels:
        app: web               # The Pods will be created with THIS label
    spec:
      containers:
      - name: nginx            # Name of the container
        image: nginx:1.25-alpine # The exact image to run
        ports:
        - containerPort: 80    # The port the app listens on
```

### Field-by-Field Explanation

- `apiVersion: apps/v1`: The Kubernetes API endpoint for workload resources.
- `spec.replicas`: The number of Pods the ReplicaSet should maintain.
- `spec.selector.matchLabels`: This tells the ReplicaSet which Pods it is allowed to manage. It MUST match `spec.template.metadata.labels`.
- `spec.template`: This is essentially a Pod definition nested inside the Deployment.
- `spec.template.spec.containers`: The list of containers to run in each Pod.

## Production Notes

- **Always use Deployments** for stateless applications. Never run raw Pods in production.
- **Selectors must be immutable.** Never change the selector field on a Deployment after creation. It will break the tracking mechanism and leave "orphaned" Pods running forever.
- **Define Readiness Probes** so the Deployment knows when a new Pod is actually ready to serve traffic before killing old Pods.
- **Use structured labels** (e.g., `app: billing`, `tier: backend`, `env: prod`) to make selecting and debugging easier.
- **Set resource requests and limits** on every container to prevent resource starvation.
- **Use Pod Disruption Budgets (PDBs)** to ensure a minimum number of Pods remain available during voluntary disruptions (node drains, cluster upgrades).

### When to Use / When NOT to Use

**Use a Deployment when:**

- Running stateless web applications (Nginx, Node.js APIs).
- Running background workers that can be safely replaced.
- Any application where temporary data loss (on Pod crash) is acceptable.

**Do NOT use a Deployment when:**

- Running databases (PostgreSQL, MySQL). If a Pod dies and is recreated on another node, it needs its exact disk attached. Deployments don't guarantee stable disk mappings. Use a StatefulSet instead.
- The application requires a stable, predictable hostname (e.g., `db-0`, `db-1`).

### Performance and Security Considerations

**Performance:** Deployments are very lightweight. The controller can handle thousands of Deployments easily. However, rapid scaling (e.g., 1 to 1000 replicas instantly) can overwhelm the API Server, Scheduler, and network. Use the Job resource for massive batch scaling.

**Security:** Ensure the ServiceAccount attached to the Pod has strict RBAC permissions. Do not use the default ServiceAccount if the app doesn't need to talk to the Kubernetes API. Run containers as non-root and use read-only root filesystems where possible.

## Best Practices

- Always use Deployments for stateless workloads.
- Set resource requests and limits on every container.
- Use structured labels for easy selection and debugging.
- Keep selectors immutable after creation.
- Define Readiness Probes to control traffic routing during updates.
- Use Pod Disruption Budgets for high-availability applications.
- Pin image tags to specific versions, never `latest`.
- Set `maxSurge` and `maxUnavailable` explicitly for critical workloads.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Selector/Label Mismatch | The Deployment's `selector.matchLabels` does not match the template's `metadata.labels` | Always ensure they match; the API Server rejects this immediately |
| Using `latest` tags | If you use `image: nginx:latest`, Kubernetes might not detect a change | Always use specific version tags |
| Scaling to 0 to "pause" | Thinking it saves state | It kills all Pods; it does not save state |
| Changing selectors after creation | Trying to relabel a Deployment | Selectors are immutable; create a new Deployment instead |
| Not setting resource limits | Oversight or fear of throttling | Always set `resources.limits`; start from observed baselines |

## Troubleshooting

**Symptom: `selector does not match template labels`**

Cause: The `spec.selector.matchLabels` does not match `spec.template.metadata.labels`.

Fix: Ensure both fields have identical key-value pairs.

```bash
kubectl describe deployment <name>
```

**Symptom: Pods stuck in `Pending`**

Cause: Insufficient resources on nodes, or node selectors/affinity rules preventing scheduling.

```bash
kubectl describe pod <pod-name> | grep -A 5 Events
kubectl get events
```

**Symptom: Pods in `CrashLoopBackOff`**

Cause: Application is failing to start or crashing immediately.

```bash
kubectl logs <pod-name> --previous
kubectl describe pod <pod-name>
```

**Symptom: Rolling update stuck**

Cause: New Pods not becoming ready, or `maxUnavailable` set too aggressively.

```bash
kubectl rollout status deployment/<name>
kubectl describe replicaset <new-rs-name>
```

## Interview Questions

**Q: Why do we need Pods? Why can't Kubernetes just manage containers directly?**

A: Containers in the same Pod share the same network namespace (IP and ports) and can communicate via localhost. They also share storage volumes. Kubernetes needs this grouping abstraction to support multi-container patterns (like sidecars) and to provide a stable IP for the application.

**Q: What happens if a node in your cluster fails, taking down 3 Pods managed by a Deployment?**

A: The ReplicaSet controller, running in the control plane, notices that the Actual State (0 Pods) no longer matches the Desired State (3 Pods). It immediately instructs the API Server to create 3 new Pods, which the Scheduler then places on healthy, available nodes.

**Q: Explain the relationship between a Deployment and a ReplicaSet.**

A: A Deployment is a higher-level abstraction that manages ReplicaSets. When you update a Deployment's Pod template (e.g., changing the image tag), the Deployment creates a new ReplicaSet. It gradually scales up the new ReplicaSet while scaling down the old one, enabling rolling updates.

**Q: You applied a YAML file but got the error `selector does not match template labels`. Why does Kubernetes enforce this?**

A: Kubernetes enforces this to prevent infinite loops. The ReplicaSet uses the selector to find Pods to manage. If the template created Pods with a different label, the ReplicaSet would ignore them, see that 0 Pods match its selector, and create more Pods endlessly. The API Server rejects this configuration to protect the cluster.

**Q: What is the difference between `replicas` and `replicas` in a Deployment?**

A: There is only one `replicas` field. It lives in `spec.replicas` and tells the ReplicaSet how many Pods to maintain. If you scale manually with `kubectl scale`, it updates this field.

**Q: How does a rolling update work internally?**

A: The Deployment controller creates a new ReplicaSet with the updated Pod template. It scales up the new ReplicaSet while scaling down the old one, controlled by `maxSurge` and `maxUnavailable` parameters. The old ReplicaSet is retained (scaled to 0) for potential rollbacks.

## Scenario Questions

**Scenario 1:** You have a Deployment with 5 replicas. You update the image tag, but the new Pods keep crashing. What happens?

A: The Deployment's RolloutHistory keeps the old ReplicaSet. If the new Pods fail to become Ready, the Deployment will eventually time out (default `progressDeadlineSeconds: 600s`). You can then roll back with `kubectl rollout undo deployment/<name>`.

**Scenario 2:** You need to update a Deployment but cannot afford any downtime. What configuration ensures this?

A: Set `spec.strategy.rollingUpdate.maxUnavailable: 0` and `maxSurge: 1`. This ensures the new Pod is fully ready before any old Pod is terminated, guaranteeing zero downtime.

**Scenario 3 (Mini Project - The Self-Healing Test):**

Deploy an Nginx Deployment with 4 replicas. Write a script that continuously deletes one of the Pods every 2 seconds. Watch the `kubectl get pods` output. Observe how Kubernetes instantly reacts to maintain the desired state of 4 replicas. Notice that the Pod names change every time (e.g., `web-abc` dies, `web-xyz` is created). Stop the script. Clean up the Deployment.

```bash
#!/bin/bash
while true; do
  kubectl delete pod $(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
  sleep 2
done
```

## Quiz

1. What is the smallest deployable unit in Kubernetes?
   - A. Container
   - B. Pod
   - C. ReplicaSet
   - D. Deployment

2. What does a ReplicaSet use to find Pods it manages?
   - A. Pod names
   - B. Labels and Selectors
   - C. IP addresses
   - D. Node names

3. What happens when you update a Deployment's image tag?
   - A. All Pods are deleted and recreated instantly
   - B. A new ReplicaSet is created and a rolling update begins
   - C. The Deployment is deleted and recreated
   - D. Nothing changes

4. Can you change a Deployment's selector after creation?
   - A. Yes, at any time
   - B. No, selectors are immutable
   - C. Only during a rolling update
   - D. Only with `kubectl edit`

5. What is the purpose of `spec.replicas` in a Deployment?
   - A. Defines the number of containers per Pod
   - B. Defines the number of Pods the ReplicaSet should maintain
   - C. Defines the number of nodes in the cluster
   - D. Defines the number of Deployments

Answers: 1-B, 2-B, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- Kubernetes runs Pods, not containers directly.
- Pods are mortal. If they die, they are gone forever.
- ReplicaSets use Label Selectors to count Pods and guarantee a desired number are always running (Self-Healing).
- Deployments manage ReplicaSets to provide zero-downtime rolling updates and instant rollbacks.
- Kubernetes is declarative: you declare the Desired State, and the Reconciliation Loop ensures the Actual State matches it.

Memory trick:

- Deployment: The Manager (handles the recipe).
- ReplicaSet: The Supervisor (counts heads).
- Pod: The Worker (does the job).

Key facts:

- Deployment -> ReplicaSet -> Pod -> Container.
- Selectors link ReplicaSets to Pods.
- Reconciliation loop fixes Actual state to match Desired state.
- `maxSurge` and `maxUnavailable` control rolling update behavior.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl apply -f deploy.yaml` | Creates/updates a Deployment |
| `kubectl get deploy,rs,pods` | Lists Deployments, ReplicaSets, and Pods |
| `kubectl scale deploy <name> --replicas=5` | Imperatively scales the Deployment |
| `kubectl delete pod <name>` | Kills a Pod (RS will recreate it) |
| `kubectl rollout undo deploy <name>` | Rolls back to previous version |
| `kubectl rollout status deploy <name>` | Shows rollout progress |
| `kubectl rollout history deploy <name>` | Shows rollout history |
| `kubectl set image deploy <name> <c>=<img>` | Updates container image |

## References

- [Kubernetes Documentation: Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [Kubernetes Documentation: Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes Documentation: ReplicaSets](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [Kubernetes Documentation: Labels and Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [Kubernetes Documentation: Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)

## Related Lessons

- [Lesson 01 - The Anatomy of a Container](../01-fundamentals/lesson-01-anatomy-of-a-container.md) - containers, namespaces, and cgroups.
- [Lesson 13 - StatefulSets](lesson-13-statefulsets.md) - for stateful workloads that need stable identity.
- [Lesson 14 - DaemonSets](lesson-14-daemonsets.md) - for cluster-wide agents.
- [Lesson 15 - Jobs and CronJobs](lesson-15-jobs-and-cronjobs.md) - for batch workloads.
- [Module 06 - Configuration](../06-configuration/README.md) - ConfigMaps and Secrets for workload configuration.
- [Module 07 - Security](../07-security/README.md) - RBAC and Pod Security Standards.

## Coming Next

Now that you understand Pods, ReplicaSets, and Deployments, the next lesson dives deeper into ReplicaSets and how they interact with the control plane. You will also learn about ReplicaSet garbage collection and orphaned Pod handling.
