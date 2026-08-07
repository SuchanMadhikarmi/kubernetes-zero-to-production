---
title: Lesson 36 - Multi-Cluster Kubernetes
module: 12 Production
lesson: 36
status: Complete
tags: [kubernetes, multi-cluster, gitops, argocd, applicationset, active-active, active-passive, global-dns, cluster-api, production]
---

# Lesson 36 - Multi-Cluster Kubernetes

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

- Explain the limitations of a single-cluster architecture.
- Compare common multi-cluster patterns: Active-Active, Active-Passive, Multi-Region.
- Manage deployments across multiple clusters using GitOps (ArgoCD ApplicationSets).
- Explain how global traffic routing works (Route53, Cloudflare).
- Switch between multiple clusters using `kubectl` contexts.

## Prerequisites

- Completion of Lessons 1 through 35.
- Docker running, because we will create multiple kind clusters.
- `kubectl` installed and configured.
- Understanding of ArgoCD and GitOps from Module 10.

## Real-world Motivation

### The Single Point of Failure

Imagine you run a global e-commerce platform on a single Kubernetes cluster in AWS `us-east-1`.

- An engineer applies a bad Network Policy that blocks all traffic. The cluster goes dark.
- AWS has a major outage in `us-east-1`. Your cluster is gone.

Because all your microservices live in that one cluster, your entire business is offline. The blast radius of the failure is 100%.

### Why This Exists

To reduce the blast radius and achieve global scale. By distributing applications across multiple clusters or cloud providers, you isolate failures: if Cluster A goes down, Cluster B takes over. Placing clusters in different geographic regions also reduces latency for users in those regions.

### Real Company Examples

**Netflix:** Netflix runs a multi-region active-active architecture. They deploy microservices to Kubernetes clusters in multiple AWS regions. If an entire AWS region goes down, the global load balancer routes traffic to the other region, keeping users streaming.

**Uber:** Uber runs multiple clusters per city to handle ride-sharing data locally. This keeps latency low for drivers and riders and isolates failures: a bug in the Paris cluster does not affect drivers in New York.

## Core Concepts

### Explain Like I'm 12

Imagine you have one giant store. If the power goes out there, nobody can buy anything. Now imagine several smaller stores in different cities. If power goes out in one city, customers go to another store. Each store serves local customers, and if one burns down, the others survive.

### Explain Like I'm a Junior Engineer

Running a single cluster is risky. If the control plane crashes or an entire cloud region goes down, the app is offline. Multi-cluster solves this by running the same application in multiple clusters. You use a Global Load Balancer to route traffic and a tool like ArgoCD to deploy the application identically everywhere.

### Explain Technically

- **Fleet Management:** ArgoCD ApplicationSets define a single YAML that automatically deploys an application to multiple target clusters based on a list or a Git directory generator.
- **Cluster API:** Uses Kubernetes CRDs to provision cloud infrastructure (AWS VPCs, EC2 instances) and create new Kubernetes clusters.
- **Federation (KubeFed):** An older, largely deprecated project that tried to sync standard resources (like ConfigMaps) across clusters. Modern architectures use GitOps instead.
- **Service Mesh Multi-Cluster:** Tools like Istio let Pods in Cluster A securely communicate with Pods in Cluster B as if they were on the same network.

### How Kubernetes Implements It Internally

Kubernetes is single-cluster by design. etcd does not sync across clusters. Multi-cluster is achieved by running multiple independent control planes and using external tools (ArgoCD, Cluster API, Istio) to coordinate them. Git becomes the single source of truth that ties the clusters together.

### Why Kubernetes Was Designed That Way

A single control plane that owns its etcd state is simpler to reason about, secure, and fast. Cross-cluster coordination is deliberately left to external tools so each cluster stays independent and failure-isolated. This is a feature, not a gap: it is what makes blast radius reduction possible.

## Architecture

A multi-cluster architecture typically has a centralized control plane (ArgoCD) deploying to multiple target clusters, with a Global Load Balancer routing users to the nearest healthy cluster.

```
[ Global Load Balancer (Route53 / Cloudflare) ]
      |
      +---> 10% Traffic ---> [ Cluster 1 (US) ] (ArgoCD managed)
      |
      +---> 90% Traffic ---> [ Cluster 2 (EU) ] (ArgoCD managed)

(If EU goes down, the LB sends 100% to US)
```

### Terminology

| Term | Definition |
|------|------------|
| Hub-and-Spoke | A multi-cluster architecture where one central cluster manages the others. |
| Active-Active | Multiple clusters serve traffic simultaneously; on failure, the rest take the load. |
| Active-Passive | One cluster serves traffic, another is on standby for failover (Disaster Recovery). |
| Cluster API | A Kubernetes sub-project for managing cluster lifecycles using CRDs. |
| ApplicationSet | An ArgoCD CRD that deploys applications to multiple clusters automatically. |
| Global DNS | Services like AWS Route53 or Cloudflare that monitor cluster health and route users to the closest healthy cluster. |

### How It Works Internally

1. Admin provisions multiple clusters (for example, `cluster-us`, `cluster-eu`).
2. Admin installs ArgoCD on a central management cluster (the Hub).
3. Admin registers `cluster-us` and `cluster-eu` as target clusters in ArgoCD.
4. Admin creates an ApplicationSet YAML in Git.
5. ArgoCD reads the ApplicationSet and creates two Application objects, one per cluster.
6. ArgoCD pulls the Helm chart from Git and deploys it to both clusters.
7. A global DNS provider monitors the Ingress IP of both clusters. If `cluster-us` fails health checks, DNS routes 100% of traffic to `cluster-eu`.

### Step-by-Step Workflow

1. Provision two Kubernetes clusters.
2. Install ArgoCD on the first cluster (Hub).
3. Register the second cluster with ArgoCD using `argocd cluster add`.
4. Define an ApplicationSet in Git targeting both clusters.
5. ArgoCD deploys the application to both clusters.
6. Configure a Global Load Balancer to route traffic.

### Lifecycle

| State | Description |
|-------|-------------|
| Provisioning | Clusters are created (via Cluster API or the cloud provider). |
| Registration | Clusters are registered to the central ArgoCD Hub. |
| Deployment | An ApplicationSet is pushed to Git; apps are deployed. |
| Failover | If a cluster goes down, the Global LB stops routing traffic to it. |
| Decommissioning | A cluster is removed from ArgoCD and deleted. |

### Communication Patterns

| Communication | Mechanism | Example |
|---------------|-----------|---------|
| ArgoCD Hub -> Target cluster | Sync applications | Kubeconfig/ServiceAccount token to `https://<cluster>:6443` |
| Global LB -> Ingress | Health checks + routing | Route53 latency routing / Cloudflare load balancing |
| Users -> Cluster | HTTP via Ingress | `https://app.example.com` |

### Common Myths

| Myth | Fact |
|------|------|
| "Kubernetes natively syncs resources across clusters." | False. etcd is strictly single-cluster. Use external tools like ArgoCD or Cluster API. |
| "Multi-cluster means you don't need backups." | False. A bad deployment pushed via GitOps to all clusters crashes all of them. You still need Velero. |

## ASCII Diagrams

Mental Model: A franchise business. Each cluster is an independent store. The Git repository is the corporate recipe book. ArgoCD is the regional manager ensuring every store follows the recipe.

```text
+-----------------------------------------------------------+
|                  Global Load Balancer                      |
|                 (Route53 / Cloudflare)                     |
+-------+-----------+------------------+------------+-------+
        |           |                  |            |
   +----+----+ +----+----+       +-----+----+ +----+----+
   | Region  | | Region  |       |  Region  | | Region  |
   |   US    | |   EU    |       |  Asia    | |   AU    |
   +----+----+ +----+----+       +-----+----+ +----+----+
        |           |                  |            |
   +----+----+ +----+----+       +-----+----+ +----+----+
   |Ingress  | |Ingress  |       | Ingress  | |Ingress  |
   |Controll | |Controll |       | Controll | |Controll |
   |  er     | |  er     |       |   er     | |  er     |
   +----+----+ +----+----+       +-----+----+ +----+----+
        |           |                  |            |
   +----+----+ +----+----+       +-----+----+ +----+----+
   | Pods    | | Pods    |       |  Pods    | | Pods    |
   |US Pods  | |EU Pods  |       | Asia Pods| |AU Pods  |
   +---------+ +---------+       +----------+ +---------+
```

## Hands-on

### Objective

Simulate a multi-cluster environment by creating two kind clusters, switching contexts between them, and deploying an app to both.

### Step 1: Create Two Clusters

```bash
kind create cluster --name cluster-us
kind create cluster --name cluster-eu
```

### Step 2: List Contexts

```bash
kubectl config get-contexts
```

Expected Output: You should see `kind-cluster-us` and `kind-cluster-eu`.

### Step 3: Deploy to the US Cluster

```bash
kubectl config use-context kind-cluster-us
kubectl create deployment web-app --image=nginx:alpine --replicas=2
kubectl get pods
```

You should see 2 Nginx Pods running in the US cluster.

### Step 4: Deploy to the EU Cluster

```bash
kubectl config use-context kind-cluster-eu
kubectl get pods
```

You should see `No resources found` because the context switched.

Now deploy the same app:

```bash
kubectl create deployment web-app --image=nginx:alpine --replicas=2
kubectl get pods
```

You should now see 2 Nginx Pods in the EU cluster.

### Step 5: The GitOps Way

In production you would not run `kubectl create` manually. You would define an ApplicationSet in ArgoCD to deploy to both clusters simultaneously:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: multi-cluster-app
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: https://cluster-us-api.example.com
        name: us
      - cluster: https://cluster-eu-api.example.com
        name: eu
  template:
    metadata:
      name: 'web-app-{{name}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/example/my-app
        targetRevision: HEAD
        path: manifests
      destination:
        server: '{{cluster}}'
        namespace: default
      syncPolicy:
        automated: {}
```

### Cleanup

```bash
kind delete cluster --name cluster-us
kind delete cluster --name cluster-eu
```

## Commands

```bash
# List all clusters in your kubeconfig
kubectl config get-contexts

# Switch to a specific cluster
kubectl config use-context <name>

# Register a cluster with ArgoCD
argocd cluster add <name>

# List ArgoCD clusters
argocd cluster list
```

## YAML Explanation

The ApplicationSet is the key object for multi-cluster GitOps.

### Field-by-Field Explanation

- `generators.list.elements`: the list of target clusters. Each element can interpolate into the template.
- `template.metadata.name: 'web-app-{{name}}'`: renders one Application per element (`web-app-us`, `web-app-eu`).
- `template.spec.source`: the Git repository, revision, and path that all clusters share.
- `template.spec.destination.server: '{{cluster}}'`: the API server of the target cluster.
- `syncPolicy.automated: {}`: ArgoCD keeps the target clusters automatically in sync with Git.

## Production Notes

- Start with one cluster. Do not jump to multi-cluster prematurely; master single-cluster operations first.
- Use GitOps. Managing several clusters manually with `kubectl` is impossible; ArgoCD or Flux ensures consistency.
- Separate config repos: keep a central app-code repo and separate config repos per environment or cluster.
- Avoid KubeFed: it is largely deprecated. Use GitOps for config sync and Service Meshes for network sync.
- Each cluster needs its own RBAC and TLS. Keep the ArgoCD Hub's RBAC strict so a compromised Hub cannot reach all target clusters.
- Cross-cluster traffic adds latency; place communicating workloads in the same cluster or region where possible.

### When to Use / When NOT to Use

**Use Multi-Cluster when:**

- You need high availability across cloud regions (Disaster Recovery).
- You need to serve global users with low latency.
- Compliance requires data to reside in specific geographic regions.
- You want Dev/QA/Prod on completely isolated control planes.

**Avoid Multi-Cluster when:**

- You are a small team (fewer than 5 engineers).
- You have a single region and low traffic.
- You do not have a GitOps pipeline yet; managing multi-cluster manually is a nightmare.

### Performance and Security Considerations

**Performance:** Multi-cluster adds network latency for cross-cluster communication (a Pod in the US talking to a Pod in the EU). Design for locality.

**Security:** Each cluster needs its own RBAC and TLS certificates. Ensure the ArgoCD Hub has strict RBAC so a compromised Hub cannot grant access to all target clusters.

## Best Practices

- Adopt GitOps (ArgoCD or Flux) before scaling to multiple clusters.
- Use ApplicationSets to keep cluster configurations declarative.
- Run health checks from the Global LB to fail over automatically.
- Keep a staging cluster to test the exact version that will roll out to all clusters.
- Document blast radius and DR runbooks per cluster.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| No network connectivity | The ArgoCD Hub cannot reach target clusters, so sync fails | Verify API Server reachability and credentials |
| Inconsistent configurations | Drift between cluster versions causes app differences | Centralize config in Git via ApplicationSets |
| Cost explosion | Each control plane carries baseline system Pod overhead | Right-size clusters and consolidate where possible |
| Managing clusters manually | Many clusters with `kubectl` drift fast | Use GitOps from day one |

## Troubleshooting

**Symptom: ArgoCD cannot sync to a target cluster**

The app is stuck in `Unknown` or `Error` state.

Check connectivity from the ArgoCD Pod to the target API Server:

```bash
kubectl exec -it deploy/argocd-server -n argocd -- curl -k https://<target-cluster-ip>:6443
```

Check credentials: ArgoCD uses ServiceAccount tokens. If a token was revoked, the sync fails.

Check ArgoCD logs:

```bash
kubectl logs -n argocd deploy/argocd-application-controller
```

**Symptom: Traffic not failing over between clusters**

Verify the Global LB health checks point at the Ingress/Service of each cluster, and that DNS records are configured for failover.

## Comparison Table

| Feature | Single Cluster | Multi-Cluster |
|---------|----------------|---------------|
| Blast Radius | Entire app down if the cluster fails | Isolated to one region/cluster |
| Cost | Low | High (multiple control planes) |
| Complexity | Low | High (GitOps + Global LB) |
| Latency | High for global users | Low (clusters near users) |

## Interview Questions

**Q: Why would you run multiple Kubernetes clusters?**

A: To reduce the blast radius of failures. If one cluster or cloud region goes down, the application stays available in another. It also lowers latency for global users by placing clusters closer to them.

**Q: How do you manage deployments across multiple clusters?**

A: I use a GitOps tool like ArgoCD. I set up a central ArgoCD Hub and use ApplicationSets to deploy the same application to multiple target clusters simultaneously, keeping configuration consistent.

**Q: What is the difference between Active-Active and Active-Passive?**

A: Active-Active means all clusters serve live traffic simultaneously (scaling and HA). Active-Passive means one cluster serves traffic while another is on standby (primarily Disaster Recovery).

**Q: Is KubeFed still recommended for multi-cluster?**

A: No. KubeFed is largely deprecated. The modern standard is GitOps (ArgoCD/Flux) for config sync and Service Meshes (Istio) for cross-cluster networking.

**Q: True or False: etcd natively syncs across clusters.**

A: False. etcd is single-cluster; coordination requires external tools.

## Scenario Questions

**Scenario 1:** You have a cluster in the US and a cluster in the EU. Users in the EU complain about high latency. How do you fix it?

A: Configure a Global Load Balancer (like AWS Route53 with latency-based routing). Route53 detects the user's location and routes them to the EU cluster, significantly reducing latency.

**Scenario 2 (Mini Project - The ArgoCD Multi-Cluster Setup):**

1. Create two kind clusters (`cluster-us`, `cluster-eu`).
2. Install ArgoCD on `cluster-us`.
3. Register the EU cluster with `argocd cluster add kind-cluster-eu`.
4. Create an ApplicationSet that deploys a simple Nginx app to both clusters.
5. Verify the app appears in both clusters.

## Quiz

1. Which pattern runs all clusters serving live traffic simultaneously?
   - A. Active-Passive
   - B. Active-Active
   - C. Single cluster
   - D. Hub-and-Spoke

2. Which tool defines a single YAML to deploy to multiple clusters?
   - A. KubeFed
   - B. ArgoCD ApplicationSet
   - C. Helm
   - D. Cluster API

3. What is the primary goal of multi-cluster architecture?
   - A. More complexity
   - B. Reduce blast radius of failures
   - C. Remove backups
   - D. Remove RBAC

4. How do you switch between clusters in kubectl?
   - A. kubectl cluster switch
   - B. kubectl config use-context <name>
   - C. kubectl change cluster
   - D. kubectl set-context

5. True or False: etcd natively syncs across multiple clusters.
   - A. True
   - B. False

Answers: 1-B, 2-B, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- Multi-cluster = multiple control planes.
- GitOps = single source of truth.
- Active-Active = all serve traffic.
- Active-Passive = one standby.
- ArgoCD ApplicationSet = deploy to all clusters.

Memory trick:

- Multi-Cluster = a franchise: multiple independent stores.
- GitOps = the corporate recipe book.
- Global LB = the customer routing system.

Key facts:

- etcd does not sync across clusters.
- Kubernetes is single-cluster by design.
- Use GitOps instead of KubeFed.
- Global DNS routes to the nearest healthy cluster.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl config get-contexts` | Lists all available clusters |
| `kubectl config use-context <name>` | Switches to a specific cluster |
| `argocd cluster add <name>` | Registers a cluster with ArgoCD |
| `argocd cluster list` | Lists registered ArgoCD clusters |

## References

- [ArgoCD Documentation: ApplicationSets](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [Cluster API Book](https://cluster-api.sigs.k8s.io/)
- [AWS Route53 Documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/Welcome.html)
- [Kubernetes Documentation: Multicluster](https://kubernetes.io/docs/concepts/)

## Related Lessons

- [Lesson 32 - Extending Kubernetes (CRDs and Operators)](../11-operators/lesson-32-extending-kubernetes-crds-and-operators.md) - CRDs underpin ApplicationSets and Cluster API.
- [Lesson 35 - Backups and Disaster Recovery with Velero](lesson-35-backups-and-disaster-recovery-with-velero.md) - backups still required in a multi-cluster world.
- [Lesson 35 (GitOps) - GitOps Principles](../10-gitops/lesson-35-gitops-principles-and-practices.md) - the GitOps model that ties clusters together.

## Coming Next

In the next lesson we continue with the Capacity Planning and Cost Optimization lesson: rightsizing requests and limits, node scaling, and FinOps practices to control Kubernetes spend.