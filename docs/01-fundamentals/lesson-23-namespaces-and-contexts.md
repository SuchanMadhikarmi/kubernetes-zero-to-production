---
title: Lesson 23 - Namespaces and Contexts
module: 01 Fundamentals
lesson: 23
status: Complete
tags: [kubernetes, fundamentals, namespaces, contexts, resourcequotas, limitrange, kubeconfig, multi-tenancy]
---

# Lesson 23 - Namespaces and Contexts

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

- Explain what a Namespace is and how it provides logical isolation.
- Use ResourceQuotas to prevent teams from consuming all cluster resources.
- Describe what a Context is and how to use kubeconfig to switch between Namespaces effortlessly.
- Explain how the API Server's Admission Controller enforces quotas.

## Prerequisites

- Completion of Lessons 1 through 22.
- A running kind cluster.
- kubectl installed and configured.

## Real-world Motivation

### The Noisy Neighbor & The Messy Desk

Imagine a cluster with 100 microservices, all deployed to the default namespace.

- When you run `kubectl get pods`, you see a massive list of 100 pods. You can't tell which belongs to the frontend team and which belongs to the billing team.
- The data-science team deploys a massive machine learning job that accidentally consumes 100% of the cluster's CPU. The frontend team's web servers crash because there are no resources left.

### Why This Exists

Kubernetes needed a way to support multi-tenancy within a single cluster. Namespaces allow you to group resources logically. ResourceQuotas ensure that one team cannot starve another team of resources. Contexts allow engineers to switch their focus to a specific namespace so they don't accidentally run a command in the wrong environment.

### Real Company Examples

**SaaS Companies:** Many SaaS companies provide a dedicated Namespace to each of their enterprise customers. Customer A gets namespace `tenant-a`, Customer B gets `tenant-b`. They apply a ResourceQuota so Customer A can only use 10 CPUs. They apply strict RBAC so Customer A's users can't even view `tenant-b`. This allows them to run 100 customers on one large cluster cheaply, instead of buying 100 small clusters.

## Core Concepts

### Explain Like I'm 12

Imagine a big office building. The building is the Cluster. A Namespace is a floor in the building. The frontend team gets the 1st floor, the backend team gets the 2nd floor. They can't see each other's desks (Pods). A ResourceQuota is the building manager telling each floor, "You are only allowed to use 100 amps of electricity. If you try to plug in too many computers, your circuit breaker trips." A Context is your keycard. It is programmed to take the elevator straight to your floor automatically, so you don't have to press the button every morning.

### Explain Like I'm a Junior Engineer

A Namespace is a way to group resources in Kubernetes. You can have a Pod named `api-server` in the `dev` namespace, and another Pod named `api-server` in the `prod` namespace, and they won't conflict.

A ResourceQuota is a policy applied to a Namespace that limits the total amount of CPU or RAM.

A Context is a setting in your kubeconfig file that changes your default namespace, so you don't have to type `-n dev` on every single command.

### Explain Technically

- **Namespace:** A core Kubernetes object. When you run `kubectl get pods`, the API Server filters by the namespace in your current context.
- **ResourceQuota:** Enforced by the ResourceQuota admission controller. When a Pod is created, the API Server intercepts it and checks if adding its requests would exceed the namespace's quota. If so, the API Server rejects the request with a 403 Forbidden.
- **Context:** A tuple of (Cluster, User, Namespace) stored in the kubeconfig file. `kubectl config use-context <name>` changes the current tuple.

### How Kubernetes Implements It Internally

Namespaces are just a string in the `metadata.namespace` field. The ResourceQuotaController runs in the background, continuously checking resource usage against quotas, but the hard enforcement happens synchronously at the API Server's admission phase during object creation.

### Why Kubernetes Was Designed That Way

Kubernetes was designed to support multi-tenancy. Namespaces allow multiple teams or environments to share a single cluster. ResourceQuotas ensure fair resource allocation. Contexts make it easy for engineers to work in the correct namespace without accidental cross-namespace operations.

## Architecture

```
[ Cluster ]
   |
   +---> [ Namespace: team-a ] (Quota: 2 CPU)
   |       +-> [ Pod 1 (Req: 1 CPU) ]
   |       +-> [ Pod 2 (Req: 1 CPU) ]
   |       +-> [ Pod 3 (Req: 1 CPU) ] ---> API Server: "Forbidden! Quota Exceeded!"
   |
   +---> [ Namespace: team-b ] (Quota: 5 CPU)
           +-> [ Pod 1 (Req: 2 CPU) ]
```

### Terminology

| Term | Definition |
|------|------------|
| Namespace | A logical cluster partition used to group and isolate resources. |
| ResourceQuota | An object that limits the total resource consumption in a namespace. |
| LimitRange | An object that sets min/max/default resource limits for individual pods. |
| Context | A kubeconfig entry linking a user to a cluster and namespace. |

### How It Works Internally

1. You create a Namespace named `team-alpha`.
2. You create a ResourceQuota in `team-alpha` limiting CPU to 1 core.
3. You run `kubectl create namespace team-alpha` and `kubectl apply -f quota.yaml`.
4. You create a Pod in `team-alpha` requesting 500m CPU.
5. The API Server's Admission Controller checks the quota: 500m (existing) + 500m (new) = 1000m (1 core). This is exactly the limit. The Pod is allowed.
6. You create a second Pod requesting 1 CPU.
7. The Admission Controller checks: 500m (existing) + 1000m (new) = 1500m. This exceeds the 1000m limit.
8. The API Server instantly returns 403 Forbidden: exceeded quota. The Pod is never saved to etcd.

### Step-by-Step Workflow

1. Admin creates a Namespace.
2. Admin creates a ResourceQuota for that Namespace.
3. Admin creates a Context pointing to that Namespace.
4. Developer switches to the Context.
5. Developer deploys Pods. If they exceed the quota, the API Server rejects them.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | Namespace is created. It exists forever until explicitly deleted. |
| Deletion | Deleting a namespace deletes all resources inside it. This is extremely dangerous. |
| Quota Enforcement | Active continuously. If a quota is lowered below current usage, existing pods are not killed, but no new pods can be created. |

### Resource Namespacing

| Resource Type | Namespaced? | Example |
|---------------|-------------|---------|
| Pods | Yes | `kubectl get pods -n default` |
| Services | Yes | `kubectl get svc -n kube-system` |
| Deployments | Yes | `kubectl get deploy -n prod` |
| Nodes | No | `kubectl get nodes` (Cluster-scoped) |
| PersistentVolumes | No | `kubectl get pv` (Cluster-scoped) |
| StorageClasses | No | `kubectl get sc` (Cluster-scoped) |

### Common Myths

| Myth | Fact |
|------|------|
| "Namespaces provide network isolation." | False. Namespaces are a logical grouping, not a network boundary. By default, Pod A in Namespace X can ping Pod B in Namespace Y. You need a NetworkPolicy to create a network boundary. |
| "ResourceQuotas limit how much CPU a Pod can use." | False. Quotas limit the sum of requests in a namespace. To limit an individual Pod's CPU usage, you use `resources.limits`. |

## ASCII Diagrams

Mental Model: A Namespace is a room in a house. A ResourceQuota is the circuit breaker for that room. A Context is your habit of always walking into the living room first when you get home.

```
[ kubectl config use-context alpha-context ]
      |
      v (Sets default namespace to team-alpha)
[ kubectl get pods ] -> (Queries API Server for team-alpha pods only)
```

## Hands-on

### Objective

Create a Namespace, lock it down with a ResourceQuota, set up a Context, and then try to exceed the quota.

### Step 1: Create a Namespace and Context

```bash
kubectl create namespace team-alpha

kubectl config set-context alpha-context --namespace=team-alpha --cluster=kind-$(kind get clusters) --user=kind-$(kind get clusters)
kubectl config use-context alpha-context
```

Verify it worked:

```bash
kubectl config current-context
kubectl get pods
```

(It should say `alpha-context` and `No resources found in team-alpha namespace.`)

### Step 2: Apply a ResourceQuota

Create `quota.yaml`:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: team-alpha
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 1Gi
    limits.cpu: "2"
    limits.memory: 2Gi
```

**Field Explanation:**

- `hard`: The hard limits for the namespace.
- `requests.cpu`: The sum of all Pod CPU requests in this namespace cannot exceed 1 core.

Apply it:

```bash
kubectl apply -f quota.yaml
```

### Step 3: Test the Quota (The Good)

Deploy a Pod that requests 500m (half a CPU):

```bash
kubectl run good-pod --image=nginx:alpine --requests="cpu=500m,memory=256Mi" --limits="cpu=1,memory=512Mi"
```

Verify it's running:

```bash
kubectl get pods
```

### Step 4: Break Things on Purpose

Try to deploy a second Pod that requests 1 full CPU:

```bash
kubectl run bad-pod --image=nginx:alpine --requests="cpu=1,memory=256Mi" --limits="cpu=1,memory=512Mi"
```

**Your Task:**

- What happened when you tried to run the `bad-pod` command? Did it give you an error in the terminal immediately, or did it hang?
- Run `kubectl get pods`. Does `bad-pod` exist in the namespace?
- Based on the theory of Admission Controllers, at what exact point did Kubernetes reject this Pod, and why?

(Answer: 1. It gave an error immediately: `Error from server (Forbidden): pods "bad-pod" is forbidden: exceeded quota`. 2. No, it does not exist. 3. It was rejected at the API Server's Admission Control phase. The request was never saved to etcd, so the Scheduler and Kubelet never saw it).

### Step 5: Cleanup

```bash
kubectl config use-context kind-$(kind get clusters)
kubectl delete namespace team-alpha
kubectl config delete-context alpha-context
```

## Commands

```bash
# Creates a namespace
kubectl create namespace <name>

# Creates a context
kubectl config set-context <name> --namespace=<ns> --cluster=<cluster> --user=<user>

# Switches active context
kubectl config use-context <name>

# Shows current context
kubectl config current-context

# Shows resource usage vs limits for a namespace
kubectl describe quota -n <ns>

# Lists all namespaces
kubectl get ns

# Lists all contexts
kubectl config get-contexts
```

## YAML Explanation

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: team-alpha
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 1Gi
    limits.cpu: "2"
    limits.memory: 2Gi
```

### Field-by-Field Explanation

- `metadata.namespace`: The namespace this quota applies to.
- `spec.hard`: The hard limits for the namespace.
- `requests.cpu`: Maximum total CPU requests across all Pods.
- `requests.memory`: Maximum total memory requests across all Pods.
- `limits.cpu`: Maximum total CPU limits across all Pods.
- `limits.memory`: Maximum total memory limits across all Pods.

## Production Notes

- **Never use `default`:** Always create specific namespaces for applications and teams.
- **Always use ResourceQuotas:** In a multi-tenant cluster, never leave a namespace without a quota. One runaway pod can crash the cluster.
- **Use LimitRanges:** If a namespace has a ResourceQuota, Pods must specify CPU/Memory requests. A LimitRange can automatically inject default requests so developers don't have to specify them on every single Pod.
- **Protect the Namespace:** Use RBAC to prevent developers from deleting namespaces.

### When to Use / When NOT to Use

**Use Namespaces when:**

- To separate environments (Dev, Staging, Prod) in the same cluster.
- To separate teams (Frontend, Backend, Data).
- To apply different ResourceQuotas and RBAC policies to different groups.

**Avoid Namespaces when:**

- Do not use Namespaces to separate different customers if they require strict physical isolation. Use separate clusters.
- Do not use Namespaces for applications that need to talk to each other with zero network policy friction (though NetworkPolicies can allow cross-namespace traffic, it adds complexity).

### Performance and Security Considerations

**Performance:** Namespaces have negligible performance impact. They are just string prefixes in etcd. However, having 5,000+ namespaces can slightly slow down API Server list operations if not filtered properly.

**Security:** Namespaces are the primary boundary for RBAC. You can restrict a user to only see resources in their namespace. However, they are not a network security boundary by default.

## Best Practices

- Always create specific namespaces.
- Always use ResourceQuotas.
- Use LimitRanges for default requests.
- Protect namespaces with RBAC.
- Use Contexts to switch namespaces.
- Never delete production namespaces.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| `kubectl delete namespace prod` | Accidental deletion | Always double-check your context before destructive commands |
| Forgetting `-n` | Not in correct context | Use Contexts to set default namespace |
| Assuming network isolation | Namespaces don't isolate network | Use Network Policies for network isolation |
| Not using ResourceQuotas | One team starves others | Always apply ResourceQuotas in multi-tenant clusters |

## Troubleshooting

**Symptom: `Error from server (Forbidden): exceeded quota`**

Cause: Pod requests exceed namespace quota.

```bash
kubectl describe quota -n <namespace>
```

Fix: Either increase the namespace quota, or lower the requests on your new Deployment.

**Symptom: Pod not showing up in `kubectl get pods`**

Cause: Wrong context or namespace.

```bash
kubectl config current-context
kubectl get pods -n <namespace>
```

Fix: Switch to the correct context with `kubectl config use-context <name>`.

**Symptom: Namespace deletion hangs**

Cause: Resources still exist in the namespace.

```bash
kubectl get all -n <namespace>
```

Fix: Delete all resources in the namespace first, then delete the namespace.

## Interview Questions

**Q: What is a Kubernetes Namespace?**

A: A logical partition within a Kubernetes cluster used to group and isolate resources. It allows multiple teams or environments to share a single cluster without interfering with each other.

**Q: Name three Kubernetes resources that are NOT namespaced.**

A: Nodes, PersistentVolumes, and StorageClasses. These are cluster-scoped.

**Q: At what phase does Kubernetes enforce ResourceQuotas?**

A: At the API Server's Admission Control phase. The request is rejected before it is saved to etcd, ensuring the cluster state never exceeds the quota.

**Q: What happens if you create a Pod in a namespace with a ResourceQuota, but you don't specify `resources.requests`?**

A: The API Server rejects it. If a quota is active, all pods in that namespace must explicitly specify requests so the quota controller can calculate the total usage.

**Q: You want to give a developer access to a cluster, but you only want them to see the dev namespace. How do you achieve this?**

A: I would use a combination of Namespaces, Contexts, and RBAC. I would create a dev namespace. I would create a Role scoped to the dev namespace allowing them to get, list, create resources. I would create a RoleBinding attaching that Role to the developer's user account. Finally, I would provide them a kubeconfig with a Context defaulting to the dev namespace.

**Q: Namespaces provide network isolation by default. True or False?**

A: False. Use Network Policies for network isolation.

**Q: Deleting a namespace deletes all resources inside it. True or False?**

A: True.

## Scenario Questions

**Scenario 1:** You need to separate Dev, Staging, and Prod environments in the same cluster. How do you structure this?

A: I would create three namespaces: `dev`, `staging`, and `prod`. I would apply ResourceQuotas to each namespace. I would create Contexts for each namespace. I would use RBAC to restrict access (developers can only access `dev`, SREs can access all).

**Scenario 2:** A developer says their Pod is being rejected with "exceeded quota". How do you diagnose?

A: I would run `kubectl describe quota -n <namespace>` to see the Used vs Hard columns. I would check if the Used CPU is equal to the Hard limit. I would then check the Pod's resource requests.

**Scenario 3 (Mini Project - The LimitRange):**

Create a namespace named `limits-test`. Create a LimitRange object that sets a default CPU request of 100m and a default CPU limit of 500m for any Pod that doesn't specify resources. Deploy an Nginx Pod without specifying any resources. Run `kubectl describe pod <name>` and verify that Kubernetes automatically injected the default CPU request and limit.

## Quiz

1. What is a Namespace?
   - A. A physical cluster
   - B. A logical partition within a cluster
   - C. A type of Pod
   - D. A network policy

2. What does a ResourceQuota limit?
   - A. Individual Pod CPU usage
   - B. Total resource consumption in a namespace
   - C. Network traffic
   - D. Storage usage

3. What is a Context?
   - A. A Pod configuration
   - B. A kubeconfig entry linking user, cluster, and namespace
   - C. A NetworkPolicy
   - D. A Service

4. When are ResourceQuotas enforced?
   - A. At the Scheduler
   - B. At the API Server's Admission Control phase
   - C. At the Kubelet
   - D. At the Controller Manager

5. Which resource is NOT namespaced?
   - A. Pods
   - B. Services
   - C. Nodes
   - D. Deployments

Answers: 1-B, 2-B, 3-B, 4-B, 5-C.

## Revision

One-minute revision:

- Namespace = Logical group.
- Context = Default namespace switch.
- ResourceQuota = Total resource limit.
- Exceeded Quota = 403 Forbidden at Admission.

Memory trick:

- **Namespace:** A floor in an office building.
- **ResourceQuota:** The circuit breaker for that floor. Plug in too many heaters, and the breaker trips before the house burns down.
- **Context:** Your keycard. It automatically takes the elevator to your floor.

Key facts:

- Namespace = Logical isolation.
- ResourceQuota = Total limits.
- Context = Namespace switch.
- Admission Controller = Enforcement.
- 403 Forbidden = Quota exceeded.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl create namespace <name>` | Creates a namespace |
| `kubectl config set-context <name> --namespace=<ns> ...` | Creates a context |
| `kubectl config use-context <name>` | Switches active context |
| `kubectl describe quota -n <ns>` | Shows resource usage vs limits for a namespace |
| `kubectl get ns` | Lists all namespaces |

## References

- [Kubernetes Documentation: Namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
- [Kubernetes Documentation: Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Kubernetes Documentation: LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [Kubernetes Documentation: Configure Access to Multiple Clusters](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/)

## Related Lessons

- [Lesson 1 - The Anatomy of a Container](lesson-01-anatomy-of-a-container.md) - containers, namespaces, and cgroups.
- [Lesson 27 - RBAC and Service Accounts](../07-security/lesson-27-rbac-and-service-accounts.md) - API Server security.
- [Lesson 19 - Network Policies](../04-networking/lesson-19-network-policies.md) - network isolation.

## Coming Next

Now that you understand Namespaces and Contexts, the next lesson covers core Kubernetes concepts and vocabulary.
