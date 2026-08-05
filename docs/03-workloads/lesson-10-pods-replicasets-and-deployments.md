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

- Explain why Kubernetes runs Pods, not containers directly.
- Describe how ReplicaSets provide self-healing by guaranteeing a desired number of Pods.
- Explain how Deployments manage ReplicaSets to provide rolling updates and rollbacks.
- Understand how Labels and Selectors link these resources together.
- Deploy, scale, and roll back an application using declarative YAML.
- Recognize the reconciliation loop that keeps your actual state matching your desired state.

## Prerequisites

- Completion of Lesson 01 (understanding of containers, namespaces, and cgroups).
- A running kind (Kubernetes IN Docker) cluster or equivalent (minikube, k3s).
- kubectl installed and configured.

## Real-world Motivation

**The Single Point of Failure:** Imagine you deploy a container running your core API. During a traffic spike, the application crashes due to a memory leak (OOMKilled, as seen in Lesson 01). Because you only had one container, your application is now completely offline. Users see 502 Bad Gateway errors until you manually SSH into the server and restart the container.

**The Configuration Drift:** If you run 10 containers manually and need to update the software version, you must manually log into 10 servers and restart them one by one. This does not scale.

### Why This Exists

Kubernetes was designed to be a declarative system. Instead of saying "start 3 containers," you say "I want 3 identical application instances to always be running."

- **Pods** exist to group containers that need to share resources.
- **ReplicaSets** exist to count Pods and replace them if they die (self-healing).
- **Deployments** exist to safely update those Pods to a new version without downtime.

In production, you never interact with containers directly. You work with these higher-level abstractions.

## Core Concepts

### Pod: The Smallest Deployable Unit

A Pod is the smallest, simplest deployable Kubernetes object. It wraps one or more containers, giving them a shared network IP and shared storage volumes. Containers in the same Pod share the same Network namespace (same IP, same ports) and IPC namespace, meaning they can talk to each other via localhost.

Pods are mortal. If a node crashes, the Pod is gone forever. Kubernetes does not reschedule the same Pod; it creates a new one with a different name.

### Labels and Selectors: The Glue

Labels are key-value pairs (e.g., `app: web`) attached to Pods and other Kubernetes objects. They are how you organize and select subsets of objects.

Selectors are the query used by controllers to find objects with specific labels. A ReplicaSet uses a selector like `app=web` to count and manage Pods. This is the fundamental mechanism that links controllers to the workloads they manage.

### Desired State vs. Actual State

You declare you want 3 Pods (Desired). The ReplicaSet counts 2 running Pods (Actual). It creates 1 more to match the Desired state. This is the core of Kubernetes: you declare what you want, and the system works to make it real.

### Reconciliation Loop

The reconciliation loop is the continuous background process of checking Actual state against Desired state and fixing differences. The ReplicaSet controller polls the API Server every few seconds, counts matching Pods, and creates or deletes Pods to match the desired count. This loop ensures that if a node crashes (removing Pods), the controller instantly detects the discrepancy and creates new Pods on healthy nodes.

### ReplicaSet: The Supervisor

A ReplicaSet ensures a specified number of Pod replicas are running at any given time. It relies on `spec.selector.matchLabels` to find its Pods. If the count drops below the desired number, it creates new Pods. If it rises above, it deletes extras.

### Deployment: The Manager

A Deployment is a higher-level controller that manages ReplicaSets. When you update a Deployment's Pod template (e.g., changing the image tag), the Deployment creates a new ReplicaSet. It gradually scales up the new ReplicaSet while scaling down the old one, performing a rolling update. This provides zero-downtime deployments and instant rollbacks.

### Explain Like I'm 12

Imagine a lemonade stand.

- The **Container** is the actual lemonade drink.
- The **Pod** is the cup holding the lemonade.
- The **ReplicaSet** is the tray. You want exactly 3 cups on the tray at all times. If a cup falls and spills, the ReplicaSet instantly puts a new cup on the tray.
- The **Deployment** is the recipe book. If you decide to change from regular lemonade to pink lemonade, the Deployment slowly replaces the old cups one by one until the whole tray is pink lemonade.

### Explain Like I'm a Junior Engineer

You do not deploy containers; you deploy Pods. A Pod gives the container a stable IP address and hostname. However, Pods are mortal. If a node crashes, the Pod is gone forever.

To ensure your app stays online, you use a Deployment. The Deployment creates a ReplicaSet. The ReplicaSet uses a Label Selector (e.g., `app=frontend`) to constantly scan the cluster. If it sees only 2 Pods with the `frontend` label when it expects 3, it asks the API server to create a 3rd.

### Explain Technically

- **Deployment**: A high-level controller object. When you update `spec.template` (e.g., changing the image tag), the Deployment controller creates a new ReplicaSet. It scales up the new ReplicaSet and scales down the old one, performing a rolling update.
- **ReplicaSet**: A controller that ensures a specified number of Pod replicas are running at any given time. It relies on `spec.selector.matchLabels` to map to its Pods.
- **Pod**: A logical host. Containers inside the same Pod share the same Network namespace (same IP, same ports) and IPC namespace, meaning they can talk to each other via localhost.

### How Kubernetes Implements It Internally

The `kube-controller-manager` runs a DeploymentController and a ReplicaSetController. When you apply a Deployment YAML, the API Server saves it to etcd. The DeploymentController notices it, creates a ReplicaSet, and saves that to etcd. The ReplicaSetController notices the new ReplicaSet, looks at its selector, counts existing Pods, and asks the API Server to create the missing Pods. The kube-scheduler then assigns those Pods to nodes, and the kubelet on those nodes starts the containers.

## Architecture

Kubernetes uses a "Russian Nesting Doll" architecture for workloads:

```
Deployment (The Manager)
  -> ReplicaSet (The Supervisor)
    -> Pod (The Worker)
      -> Container (The actual process)
```

You never interact with containers directly in production. You declare a Deployment, and the controllers handle everything else.

### Step-by-Step Workflow

1. Developer writes a Deployment YAML declaring `replicas: 3` and `image: nginx:1.25`.
2. `kubectl apply` sends this to the API Server.
3. API Server validates the YAML and stores it in etcd.
4. DeploymentController creates a ReplicaSet (version 1).
5. ReplicaSetController sees it wants 3 Pods, finds 0, and creates 3 Pods.
6. Scheduler assigns those Pods to nodes.
7. Kubelet on the nodes pulls the image and starts the containers.

When the developer updates the YAML to `image: nginx:1.26`:

8. DeploymentController creates ReplicaSet (version 2).
9. RS v2 creates 1 Pod (nginx:1.26). RS v1 deletes 1 Pod (nginx:1.25).
10. Process repeats until RS v2 has 3 Pods and RS v1 has 0.

This is the rolling update in action.

### Container Lifecycle

| State | Description |
|-------|-------------|
| Pending | The Pod has been accepted by the API Server but containers are not yet running. Common reasons: waiting for scheduling, pulling images. |
| Running | At least one container is still running, or is in the process of starting or restarting. |
| Succeeded | All containers terminated successfully (exit code 0) and will not be restarted. |
| Failed | All containers terminated, and at least one terminated with a non-zero exit code. |
| Unknown | The Pod status cannot be obtained, usually due to a communication error with the node. |

Understanding the lifecycle matters for debugging. A Pod stuck in `Pending` usually means scheduling constraints (resource shortage, node affinity, or unbound PVCs). A Pod in `CrashLoopBackOff` means the container starts, crashes, and Kubernetes keeps retrying with exponential backoff.

### Containers vs Virtual Machines

| Feature | Virtual Machine (VM) | Container in a Pod |
|---------|---------------------|-------------------|
| OS Kernel | Has its own full guest kernel | Shares the host kernel |
| Isolation | Hardware-level (Hypervisor) | OS-level (Namespaces) |
| Size | Gigabytes (GB) | Megabytes (MB) |
| Boot Time | Minutes | Seconds |
| Resource Overhead | High | Low |
| Startup via Kubernetes | No (VMs are not Pod-native) | Yes (Pods are the unit of deployment) |

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
  Deployment (nginx:1.25)
    ReplicaSet v1 (3 Pods running nginx:1.25)

After Update:
  Deployment (nginx:1.26)
    ReplicaSet v2 (3 Pods running nginx:1.26)
    ReplicaSet v1 (0 Pods - scaled down)

During Update (gradual shift):
  ReplicaSet v2: [Pod] [Pod] [Pod]
  ReplicaSet v1: [Pod] [   ] [   ]
                 ^-- being removed one by one
```

## Hands-on

Objective: Deploy an application using a declarative YAML Deployment. Scale it, watch it self-heal, and debug a broken YAML.

A matching lab lives at [labs/lab-10-pods-replicasets-and-deployments.md](../../labs/lab-10-pods-replicasets-and-deployments.md).

### Step 1 - Deploy the application

```bash
kubectl apply -f nginx-deploy.yaml
```

### Step 2 - Verify the hierarchy

```bash
kubectl get deployments
kubectl get replicasets
kubectl get pods -l app=web
```

Expected: 1 Deployment, 1 ReplicaSet, and 3 Pods.

### Step 3 - Test self-healing

```bash
kubectl delete pod <POD_NAME>
kubectl get pods -l app=web
```

The deleted Pod terminates, and a brand new Pod is created to maintain the count of 3.

### Step 4 - Test scaling

```bash
kubectl scale deployment nginx-deploy --replicas=5
kubectl get pods -l app=web
```

Now 5 Pods are running.

### Step 5 - Test rolling update

```bash
kubectl set image deployment/nginx-deploy nginx=nginx:1.26-alpine
kubectl rollout status deployment/nginx-deploy
kubectl get replicasets
```

A new ReplicaSet appears and scales up while the old one scales down.

### Step 6 - Test rollback

```bash
kubectl rollout undo deployment/nginx-deploy
kubectl rollout status deployment/nginx-deploy
```

Traffic shifts back to the previous version.

### Step 7 - Cleanup

```bash
kubectl delete deployment nginx-deploy
```

## Commands

```bash
# Deploy
kubectl apply -f nginx-deploy.yaml

# Inspect the hierarchy
kubectl get deployments
kubectl get replicasets
kubectl get pods -l app=web

# Scale
kubectl scale deployment nginx-deploy --replicas=5

# Update image
kubectl set image deployment/nginx-deploy nginx=nginx:1.26-alpine

# Watch rollout progress
kubectl rollout status deployment/nginx-deploy

# Roll back
kubectl rollout undo deployment/nginx-deploy

# Delete
kubectl delete deployment nginx-deploy

# Describe for debugging
kubectl describe deployment nginx-deploy
kubectl describe pod <POD_NAME>

# Get events
kubectl get events --sort-by=.metadata.creationTimestamp
```

## YAML Explanation

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

Field-by-field explanation:

- `apiVersion: apps/v1`: The API group for workload resources. Deployments live in the `apps` group.
- `kind: Deployment`: Declares this is a Deployment resource.
- `metadata.name`: The name of the Deployment. Must be unique within the namespace.
- `metadata.labels`: Labels attached to the Deployment object itself (not the Pods).
- `spec.replicas`: The desired number of Pod replicas. The ReplicaSet will maintain this count.
- `spec.selector.matchLabels`: Tells the ReplicaSet which Pods it is allowed to manage. This MUST match `spec.template.metadata.labels`.
- `spec.template`: The Pod template. This is essentially a Pod definition nested inside the Deployment.
- `spec.template.metadata.labels`: Labels applied to the Pods created by this Deployment. These MUST match `spec.selector.matchLabels`.
- `spec.template.spec.containers`: The container definitions. Each Pod created from this template will run these containers.

The critical rule: `spec.selector.matchLabels` must equal a subset of `spec.template.metadata.labels`. If they do not match, the API Server rejects the Deployment to prevent infinite loops.

## Production Notes

From listing in an image, to operating at scale, some things change:

- **Always use Deployments for stateless apps.** Never use raw Pods or ReplicaSets in production. Deployments give you rolling updates, rollbacks, and self-healing.
- **Selectors must be immutable.** Never change the selector field on a Deployment after creation. It will break the tracking mechanism and leave "orphaned" Pods running forever.
- **Define Readiness Probes.** So the Deployment knows when a new Pod is actually ready to serve traffic before killing old Pods. Without a readiness probe, traffic may be sent to a Pod that is not yet ready.
- **Use structured labels.** Labels like `app: billing`, `tier: backend`, `env: prod` make selecting and debugging easier. Avoid generic labels.
- **Set resource requests and limits.** The scheduler uses requests to place Pods, and limits prevent runaway processes. Without them, a single Pod can starve the node.
- **Use Pod Disruption Budgets.** For production workloads, define a PDB to ensure a minimum number of Pods remain available during voluntary disruptions (node drains, upgrades).

### When to Use / When NOT to Use

Use a Deployment when:

- Running stateless web applications (Nginx, Node.js APIs).
- Running background workers that can be safely replaced.
- Any application where temporary data loss (on Pod crash) is acceptable.

Do NOT use a Deployment when:

- Running databases (PostgreSQL, MySQL). If a Pod dies and is recreated on another node, it needs its exact disk attached. Deployments do not guarantee stable disk mappings. Use a StatefulSet instead.
- Running applications that require a stable, predictable hostname (e.g., `db-0`, `db-1`). Use a StatefulSet.
- Running cluster-wide agents that must run on every node. Use a DaemonSet.

### Performance and Security Considerations

**Performance:** Deployments are lightweight. The controller can handle thousands of Deployments easily. However, rapid scaling (e.g., 1 to 1000 replicas instantly) can overwhelm the API Server, Scheduler, and network. Use gradual scaling or the Job resource for massive batch workloads.

**Security:** Ensure the ServiceAccount attached to the Pod has strict RBAC permissions. Do not use the default ServiceAccount if the app does not need to talk to the Kubernetes API. Run containers as non-root and drop unnecessary Linux capabilities.

## Best Practices

- Always use Deployments for stateless workloads; never use raw Pods or ReplicaSets.
- Keep selectors immutable after creation.
- Define Readiness Probes so traffic is only sent to ready Pods.
- Set resource requests and limits on every container.
- Use structured, meaningful labels (app, tier, env, version).
- Define Pod Disruption Budgets for production workloads.
- Use specific image tags, never `latest`.
- Run containers as non-root with minimal capabilities.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Selector/Label mismatch | Typo in YAML; selector does not match template labels | The API Server rejects this immediately. Always verify `matchLabels` equals `template.metadata.labels`. |
| Using `latest` tags | Convenience | Use specific version tags. Kubernetes might not detect a change when the string did not change. |
| Scaling to 0 to "pause" | Misunderstanding | Scaling to 0 kills all Pods. It does not save state. |
| No Readiness Probe | Oversight | Without a probe, traffic is sent to Pods that are not ready yet. Define a readiness probe. |
| Changing selector after creation | Attempting to reassign Pods | This breaks the tracking mechanism. Create a new Deployment instead. |
| No resource limits | Fear of throttling | Without limits, a single Pod can starve the entire node. |

## Troubleshooting

**Symptom: Pod stuck in `Pending`.**
Cause: The scheduler cannot find a suitable node. Common reasons: insufficient resources, node affinity/anti-affinity constraints, or unbound PersistentVolumeClaims.
Fix: Check `kubectl describe pod <pod-name>` and look at the Events section.

**Symptom: Pod in `CrashLoopBackOff`.**
Cause: The container starts, crashes, and Kubernetes retries with exponential backoff. Usually indicates a bug, missing config, or failed readiness/liveness probe.
Fix: Check logs with `kubectl logs <pod-name>`. Inspect the previous container's logs with `kubectl logs <pod-name> --previous`.

**Symptom: Deployment does not update.**
Cause: The image tag did not change (e.g., using `latest`). Kubernetes only triggers a rollout when the Pod template actually changes.
Fix: Use specific image tags like `nginx:1.26-alpine`.

**Symptom: `selector does not match template labels` error.**
Cause: The `spec.selector.matchLabels` does not match `spec.template.metadata.labels`.
Fix: Ensure the selector is a subset of the template labels. The API Server rejects this to prevent infinite loops where the ReplicaSet creates Pods it immediately ignores.

**Symptom: Old Pods still running after update.**
Cause: The Deployment's `strategy.rollingUpdate.maxSurge` or `maxUnavailable` may be set conservatively, or the new Pods are failing readiness checks.
Fix: Check rollout status with `kubectl rollout status deployment/<name>`. Inspect new Pods for readiness failures.

## Interview Questions

**Q: Why do we need Pods? Why cannot Kubernetes just manage containers directly?**
A: Containers in the same Pod share the same network namespace (IP and ports) and can communicate via localhost. They also share storage volumes. Kubernetes needs this grouping abstraction to support multi-container patterns (like sidecars) and to provide a stable IP for the application.

**Q: What happens if a node in your cluster fails, taking down 3 Pods managed by a Deployment?**
A: The ReplicaSet controller, running in the control plane, notices that the Actual State (0 Pods) no longer matches the Desired State (3 Pods). It immediately instructs the API Server to create 3 new Pods, which the Scheduler then places on healthy, available nodes.

**Q: Explain the relationship between a Deployment and a ReplicaSet.**
A: A Deployment is a higher-level abstraction that manages ReplicaSets. When you update a Deployment's Pod template (e.g., changing the image tag), the Deployment creates a new ReplicaSet. It gradually scales up the new ReplicaSet while scaling down the old one, enabling rolling updates.

**Q: What is the reconciliation loop?**
A: The reconciliation loop is the continuous background process where a controller checks the Actual state against the Desired state and fixes differences. For example, the ReplicaSet controller counts matching Pods and creates or deletes Pods to match the desired count.

**Q: What happens if you delete a Pod managed by a ReplicaSet?**
A: The ReplicaSet controller detects that the Actual count dropped below the Desired count and immediately creates a new Pod to replace it. The new Pod will have a different name but identical configuration.

**Q: Can you change a Deployment's selector after creation?**
A: No. Selectors are immutable after creation. Changing them would break the tracking mechanism and leave orphaned Pods running indefinitely. If you need different selectors, create a new Deployment.

## Scenario Questions

**Scenario 1: The Broken Selector**
You apply a YAML file but get the error `selector does not match template labels`. Why does Kubernetes enforce this?

A: Kubernetes enforces this to prevent infinite loops. The ReplicaSet uses the selector to find Pods to manage. If the template created Pods with a different label, the ReplicaSet would ignore them, see that 0 Pods match its selector, and create more Pods endlessly. The API Server rejects this configuration to protect the cluster.

**Scenario 2: Rolling Update Stuck**
You update your Deployment image, but `kubectl rollout status` shows it is stuck. What do you check?

A: Check the new ReplicaSet's Pods. They may be failing readiness probes, which prevents the Deployment from killing old Pods. Use `kubectl describe pod <new-pod>` to check events and `kubectl logs <new-pod>` to inspect the container.

**Scenario 3: Mini Project - The Self-Healing Test**

```bash
# Deploy with 4 replicas
kubectl apply -f nginx-deploy.yaml

# Write a script that continuously deletes one Pod every 2 seconds
while true; do kubectl delete pod $(kubectl get pods -l app=web -o name | head -1); sleep 2; done
```

Observe how Kubernetes instantly reacts to maintain the desired state of 4 replicas. Notice that the Pod names change every time (e.g., `web-abc` dies, `web-xyz` is created). Stop the script and clean up the Deployment.

## Quiz

1. What is the smallest deployable unit in Kubernetes?
   - A. Container
   - B. Pod
   - C. ReplicaSet
   - D. Deployment

2. What does a ReplicaSet ensure?
   - A. Pods are updated to the latest version
   - B. A specified number of Pod replicas are running at any given time
   - C. Pods are scheduled on specific nodes
   - D. Pods have a stable network IP

3. What happens when you update a Deployment's image tag?
   - A. All Pods are killed and replaced instantly
   - B. A new ReplicaSet is created and traffic is gradually shifted
   - C. The existing Pods are updated in place
   - D. Nothing changes until you manually restart

4. What must match for a Deployment to work correctly?
   - A. `spec.selector.matchLabels` must equal `spec.template.metadata.labels`
   - B. `metadata.name` must equal `spec.replicas`
   - C. `spec.template.spec.containers` must equal `spec.selector`
   - D. `metadata.labels` must equal `spec.template.spec.containers`

5. What is the reconciliation loop?
   - A. A one-time check when a Deployment is created
   - B. A continuous background process of checking Actual state against Desired state and fixing differences
   - C. A manual process where the administrator verifies Pod health
   - D. A network protocol for controller communication

Answers: 1-B, 2-B, 3-B, 4-A, 5-B.

## Revision

One-minute revision:

- Kubernetes runs Pods, not containers directly.
- Pods are mortal. If they die, they are gone forever.
- ReplicaSets use Label Selectors to count Pods and guarantee a desired number are always running (self-healing).
- Deployments manage ReplicaSets to provide zero-downtime rolling updates and instant rollbacks.
- Kubernetes is declarative: you declare the Desired State, and the Reconciliation Loop ensures the Actual State matches it.

Memory trick:

- Deployment: The Manager (handles the recipe).
- ReplicaSet: The Supervisor (counts heads).
- Pod: The Worker (does the job).

Key facts:

- `Deployment -> ReplicaSet -> Pod -> Container`.
- Selectors link ReplicaSets to Pods.
- Reconciliation loop fixes Actual state to match Desired state.
- The selector must match the template labels or the API Server rejects the Deployment.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl apply -f deploy.yaml` | Creates or updates a Deployment |
| `kubectl get deploy,rs,pods` | Lists Deployments, ReplicaSets, and Pods |
| `kubectl scale deploy <name> --replicas=5` | Imperatively scales the Deployment |
| `kubectl delete pod <name>` | Kills a Pod (ReplicaSet will recreate it) |
| `kubectl set image deploy <name> nginx=nginx:1.26` | Updates the container image |
| `kubectl rollout status deploy <name>` | Watches the rollout progress |
| `kubectl rollout undo deploy <name>` | Rolls back to previous version |
| `kubectl rollout history deploy <name>` | Shows revision history |

## References

- [Kubernetes Documentation: Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [Kubernetes Documentation: Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes Documentation: ReplicaSets](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [Kubernetes Documentation: Labels and Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [Kubernetes Documentation: Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)

## Related Lessons

- [Lesson 01 - The Anatomy of a Container](../01-fundamentals/lesson-01-anatomy-of-a-container.md) - the Linux primitives (namespaces, cgroups) that make Pods possible.
- [Module 03 - Workloads](../03-workloads/README.md) - the full workloads module covering StatefulSets, DaemonSets, and Jobs.
- [Module 06 - Configuration](../06-configuration/README.md) - ConfigMaps and Secrets referenced by Pod specs.

## Coming Next

Now that you understand the core workload objects (Pod, ReplicaSet, Deployment), the next lesson dives deeper into Pod internals: init containers, sidecar patterns, resource requests and limits, and how to structure multi-container Pods effectively.