---
title: Lesson 47 - The Capstone (Architecture, Career and Interview Mastery)
module: 14 Certifications
lesson: 47
status: Complete
tags: [capstone, architecture, career, interview, platform-engineer, sre, gitops, argo-cd, istio]
---

# Lesson 47 - The Capstone (Architecture, Career and Interview Mastery)

## Table of Contents

- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Real-world Motivation](#real-world-motivation)
- [Core Concepts](#core-concepts)
- [Architecture](#architecture)
- [ASCII Diagrams](#ascii-diagrams)
- [Deep Explanation](#deep-explanation)
- [Terminology](#terminology)
- [How It Works Internally (The Interview Mindset)](#how-it-works-internally-the-interview-mindset)
- [Step-by-Step Workflow (Career Strategy)](#step-by-step-workflow-career-strategy)
- [Lifecycle](#lifecycle)
- [Hands-on (Final Capstone Assessment)](#hands-on-final-capstone-assessment)
- [Commands](#commands)
- [YAML Explanation](#yaml-explanation)
- [Production Best Practices](#production-best-practices)
- [Best Practices](#best-practices)
- [Common Mistakes](#common-mistakes)
- [Troubleshooting (Interview Scenarios)](#troubleshooting-interview-scenarios)
- [Comparison Tables](#comparison-tables)
- [When to Use / When Not to Use](#when-to-use--when-not-to-use)
- [Performance and Security Considerations](#performance-and-security-considerations)
- [Real Company Examples](#real-company-examples)
- [Common Myths](#common-myths)
- [Quiz](#quiz)
- [Revision Notes and Cheat Sheet](#revision-notes-and-cheat-sheet)
- [Interview Preparation (The Ultimate Guide)](#interview-preparation-the-ultimate-guide)
- [Scenario Questions](#scenario-questions)
- [Mini Project](#mini-project)
- [Homework and Additional Reading](#homework-and-additional-reading)
- [References](#references)
- [Related Lessons](#related-lessons)
- [Coming Next](#coming-next)

---

## Learning Objectives

By the end of this lesson, you will understand:

- The complete architecture of a Fortune 500 Kubernetes platform.
- How to map the tools we built (Prometheus, ArgoCD, Istio) to real-world business problems.
- The three types of Kubernetes interview questions and how to dominate them.
- The "STAR" method for behavioral incident scenarios.
- How to position yourself for six-figure Platform Engineering roles.

## Prerequisites

- Completion of Lessons 1 through 46.
- A mindset ready for production architecture and career strategy.

## Real-world Motivation

### From Lesson

The "Siloed Engineer" Problem: Many engineers know how to run `kubectl apply` or how to write a Deployment YAML. However, when an interviewer asks, "Walk me through how a request reaches a Pod, and how you would debug it if it failed," they freeze. They know the pieces, but they do not understand the system as a whole. Furthermore, they cannot translate technical knowledge into business value (for example, "I implemented Argo Rollouts to reduce deployment rollback time by 95%").

### From Lesson

Knowing Kubernetes is only half the battle. You must be able to architect systems that survive real-world traffic, and you must be able to articulate your value to non-technical hiring managers and highly technical interview panels. This capstone bridges the gap between "knowing Kubernetes" and "being a Kubernetes Engineer."

### Additional Production Knowledge

Every tool in this course is a business lever. In an interview, translate each skill into an outcome: Argo Rollouts reduces rollback time, the Horizontal Pod Autoscaler lowers infrastructure cost, Network Policies shrink compliance scope, and GitOps with ArgoCD turns every deployment into a reversible git commit. Hiring managers fund outcomes, not YAML.

## Core Concepts

### From Lesson

- The Reconciliation Loop: A senior engineer sees Kubernetes as a collection of loops trying to make Actual State match Desired State.
- Defense in Depth: Security is not just RBAC. It is RBAC + Network Policies + Security Contexts + Kyverno admission controllers.
- Progressive Delivery: No human should ever type `kubectl apply` in production. Everything is automated via GitOps and safely rolled out using Argo Rollouts.
- The STAR Method: (Situation, Task, Action, Result) - the framework for answering behavioral interview questions.

## Architecture

### From Lesson (Architecture Overview)

If you walk into a company like Stripe or Shopify, this is what their platform looks like. Every component here is something you learned to build in this course.

```text
[ Developer Laptops / CI (GitHub Actions) ]
             |
             | Git Push: Code + Helm Chart
             v
[ Git Repository (Source of Truth) ]
             |
             +------------------------------+
             |                              |
             v                              v
[ ArgoCD (CD) ]                     [ Image Registry ]
  Reconciles Git -> Cluster           (Docker Images)
             |
             v
============== [ The Kubernetes Cluster ] ==============
[ Control Plane ]
    - API Server (Admission Webhooks / Kyverno)
    - etcd (Backed up via Velero)

[ Worker Nodes (Kubelet + Containerd + CNI/Cilium) ]
             |
             +--> [ Argo Rollouts ] (Progressive Delivery / Canary)
             +--> [ Ingress Controller (NGINX) ] (External Traffic L7)
             +--> [ Service Mesh (Istio Sidecars) ] (mTLS, Internal Traffic L7)
             +--> [ CoreDNS ] (Service Discovery)
             |
             +--> [ Application Pods ] (Probes, Requests/Limits, SecurityContext)
             +--> [ StatefulSets / Operators ] (Databases / RabbitMQ)
             |
             +--> [ Observability Stack ]
                   - Promtail (DaemonSet: ships logs to Loki)
                   - Node Exporter (DaemonSet: exposes metrics)
                   - Prometheus (Scrapes metrics, evaluates Alertmanager rules)
                   - Grafana (Visualizes Prometheus + Loki)
```

### Additional Production Knowledge

A platform team treats this diagram as a contract. The dashed lane between ArgoCD and the cluster is a pull-based reconcile loop, not a push. The mesh handles east-west (service-to-service) traffic with mTLS, while the Ingress handles north-south (external) traffic. Keeping those two planes separate is what lets you shift canary weight safely.

## ASCII Diagrams

### From Lesson (Visual Explanation - Mental Model)

Mental Model of a Senior Engineer: everything is a control loop.

```text
[ Git (Desired State) ]
      |
      v
[ ArgoCD Controller ] (Reconciles Cluster to Git)
[ HPA Controller ] (Reconciles Pod count to CPU metrics)
[ Argo Rollouts Controller ] (Reconciles traffic weights to error rates)
[ ReplicaSet Controller ] (Reconciles running Pod count)
```

### Additional Production Knowledge

Every controller is an instance of the same pattern: watch, diff, act, repeat. Pay attention inside the algorithm: a cache (or informer in client-go) holds a local copy of state so the controller does not hammer the API Server; rate limiting and retries prevent controller storms. Killing a reconciliation loop by abusing the API Server during an incident is a classic way to make things worse.

## Deep Explanation

### From Lesson

**1. Explain like I am 12**

Imagine a city. The Control Plane is the city government. The Worker Nodes are the factories. The Ingress is the highways. The Service Mesh is the secure courier service. The Observability stack is the traffic cameras and weather forecasters. To run the city, you do not just need to know how to build a road; you need to know how traffic flows, where the bottlenecks are, and how to respond when a bridge collapses.

**2. Explain like I am a junior engineer**

To pass a senior interview, stop thinking about individual resources (a Pod or a ConfigMap) and start thinking about systems. How does a code commit get to production? How do you know if the production app is healthy? How do you secure it? The architecture diagram above maps out that entire flow.

**3. Explain technically**

GitOps Flow: CI builds the image and updates the Git repo. ArgoCD detects the drift and applies it. Argo Rollouts intercepts the Deployment and turns it into a canary release, shifting 10% of traffic to the new version while querying Prometheus for error rates.

Data Path Flow: User -> Cloud LB -> NGINX Ingress -> Service IP (kube-proxy iptables DNAT) -> Pod IP (Istio sidecar intercepts for mTLS) -> Container.

Failure Domain: If a node dies, the Node Controller marks it `Unknown` after 40 seconds. The ReplicaSet controller notices missing Pods and schedules new ones on healthy nodes. The EndpointsController removes the dead Pod IPs from the Service, ensuring traffic routes only to healthy Pods.

**4. How Kubernetes implements it internally**

Kubernetes is an ecosystem of controllers. Everything you do - scheduling, networking, storage, deployments - is just a controller watching the API Server and taking action to align reality with your YAML.

## Terminology

| Term | Definition |
|------|------------|
| Platform Engineering | The discipline of building internal developer platforms. |
| SRE | Site Reliability Engineering. Focused on reliability, metrics, and incident response. |
| STAR Method | Situation, Task, Action, Result. A structured way to answer behavioral questions. |
| GitOps | Operating paradigm in which Git is the single source of truth. |

## How It Works Internally (The Interview Mindset)

### From Lesson

In an interview, you will be tested on three gates. You must pass all three to get an offer.

- **Core Knowledge**: Rapid-fire conceptual questions. For example, "What happens when you run `kubectl run`?"
- **Production Troubleshooting**: Scenario-based debugging. For example, "Users are getting 502s. Walk me through your steps."
- **Behavioral / Incident**: "Tell me about a time you handled an outage."

### Additional Production Knowledge

Interview panels are not looking for rote recall at the senior level; they look for structure. When given an open-ended debugging question, keep one funnel: symptoms -> surfaces -> data -> hypothesis -> action -> verify. It shows a disciplined engineering mindset, not just a vocabulary.

## Step-by-Step Workflow (Career Strategy)

### From Lesson

1. **Build a Portfolio**: Put your GitHub Actions pipeline, Helm charts, and ArgoCD configs in a public GitHub repo. This is your new resume.
2. **Get Certified**: Schedule the CKA exam within the next 3 months while this knowledge is fresh.
3. **Update LinkedIn**: Add "Kubernetes", "ArgoCD", "Prometheus", "Helm", and "GitOps" to your skills.
4. **Apply**: Target Platform Engineering and SRE roles. Use your portfolio to bypass HR filters.

## Lifecycle

### From Lesson

The lifecycle of your career transition:

- **Learning** (Done): You have completed this course.
- **Building**: You build your portfolio.
- **Certifying**: You pass the CKA.
- **Interviewing**: You apply and interview.
- **Operating**: You get the job and run production clusters.

## Hands-on (Final Capstone Assessment)

### From Lesson

Answer these 5 questions without looking at previous lessons. If you can answer them, you are ready for senior interviews.

1. A Pod is in `CrashLoopBackOff`. You run `kubectl logs <pod>` and see the app started fine. Why do you need to run `kubectl logs <pod> --previous`?
2. You deploy an HPA, but it shows `<unknown>/50%` for the target. What are the two most likely reasons?
3. You delete a PVC, but it stays in a `Terminating` status forever. Why is this happening, and how do you fix it?
4. How does ArgoCD detect and fix "Configuration Drift" if an engineer manually runs `kubectl edit`?
5. Why do we use a Headless Service (`clusterIP: None`) for a StatefulSet instead of a normal ClusterIP Service?

**Capstone Answer Key**

1. `kubectl logs` shows the current container's logs. Since it just restarted, those logs are fresh. `--previous` reads the logs of the crashed container instance that existed before the restart, which contains the actual stack trace or the `OOMKilled` event.
2. (a) The Metrics Server is not installed, or the HPA cannot reach it. (b) The Pod template is missing `resources.requests.cpu`, and the HPA needs a baseline to calculate percentages.
3. The PVC has a `kubernetes.io/pvc-protection` finalizer. It is waiting for a Pod that is actively using the PVC to terminate, OR the underlying PV has a Reclaim Policy of `Retain` and the cloud provider disk is stuck. You can fix it by removing the finalizer: `kubectl patch pvc <name> -p '{"metadata":{"finalizers":null}}'`.
4. ArgoCD continuously polls Git and compares it to the Live State in the cluster. If `selfHealing` is enabled, it detects the change as "Out of Sync" and sends a PATCH/PUT request to the API Server to overwrite the manual change back to the Git state.
5. A normal ClusterIP Service load-balances traffic randomly. Databases (StatefulSets) require specific peers to communicate (for example, `db-0` talking to `db-1`). A Headless Service does not load balance; it creates specific DNS A-records for each Pod IP, allowing direct routing to a specific database node.

## Commands

### Additional Production Knowledge

A short review of the commands that bind the capstone architecture together:

```bash
# Observe the cluster and its workloads
kubectl get nodes
kubectl get pods -o wide
kubectl describe pod <name>
kubectl logs <name> --previous

# GitOps: sync and diff with ArgoCD
argocd app get <app>
argocd app sync <app>
argocd app diff <app>

# Rollback and progressive delivery
kubectl rollout undo deployment/<name>
kubectl argo rollouts get rollout <name> --watch

# Insight: metrics, logs, and reconciliation
kubectl top nodes
kubectl top pods
kubectl get events --sort-by='.lastTimestamp'
```

## YAML Explanation

### Additional Production Knowledge

Most of the YAML in the capstone diagram is the same you have already written. The single most important pattern is the interplay between Pod template metadata and controllers:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
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
      - name: web
        image: nginx:1.25-alpine
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
```

- The `label` under `.spec.template.metadata` must match the `labelSelector` in the Deployment, and the Service uses the same labels so the EndpointsController wires traffic to the right Pods.
- The `requests` baseline feeds the HPA and enables percentage-based autoscaling; the `limits` enforce CPU and memory and prevent a noisy neighbor from starving a node.
- Deleting or changing the image in the template triggers a new ReplicaSet, which is exactly the hook Argo Rollouts and ArgoCD operate on for gradual and Git-driven delivery.

Adding a PodSecurityContext and SecurityContext is the counterpart: it runs the container as a non-root user with no extra capabilities, which is the baseline hardening already covered in Module 07.

## Troubleshooting (Interview Scenarios)

### From Lesson

**Scenario 1 - The 502 Bad Gateway**

Interviewer: "Users are getting 502 errors on your web app. Walk me through your debugging steps."

Ideal Answer:

1. Check the Ingress Controller logs to confirm the 502 is coming from NGINX, not the app.
2. Run `kubectl get endpoints <web-svc>`. If empty, the Service selector does not match Pod labels, or Pods are failing Readiness probes.
3. If Endpoints exist, check `kubectl describe pod` to ensure the container is Running.
4. If Running, exec into a utility Pod and `curl <pod-ip>:<containerPort>` to verify the app is actually listening on the port the Service targets.

**Scenario 2: The Node Failure**

Interviewer: "A node in your cluster goes offline. What happens to the Pods running on it?"

Ideal Answer:
- The node controller marks the node as `NotReady`. After a grace period (default 5 minutes), the node is evicted.
- The Pods on that node stay in `Terminating` state for a grace period (default 5 minutes).
- The ReplicaSet controller notices the Pods are gone and schedules new Pods on healthy nodes.
- The EndpointsController removes the dead Pod IPs from the Service, so traffic routes only to the new, healthy Pods.

### Additional Production Knowledge

For the 502 answer, always start from the cheapest data and work inward: load balancer/Ingress logs, then Service endpoints, then Pod status, then direct container probe. This "funnel" proves you debug from outside-in and never guess. For the node scenario, name the exact timers - `node-monitor-grace-period` (40s) and `pod-eviction-timeout` (5m) - to show command-level detail.

## Comparison Tables

### From Lesson

| Role | Focus | Key Tools |
|------|-------|-----------|
| DevOps Engineer | CI/CD pipelines, automation | Jenkins, GitHub Actions, Terraform |
| SRE | Reliability, metrics, incidents | Prometheus, Grafana, Argo Rollouts |
| Platform Engineer | Internal Developer Platform (IDP) | Kubernetes, ArgoCD, Helm, Crossplane |

## When to Use / When Not to Use

### From Lesson

Apply for Senior Roles **When**:

- You understood the concepts in this course and can build the architecture diagram above.
- You have 3+ years of general infrastructure or software experience.

Do **Not** apply for Senior Roles When:

- You are completely new to IT/Linux. Start with Junior DevOps or Cloud Support roles and work your way up.

## Performance and Security Considerations

### From Lesson

- **Performance**: In interviews, speed of thought matters. Use the mental models (for example, the "Troubleshooting Funnel") to structure your answers quickly.
- **Security**: Never share your company's proprietary Kubernetes manifests or code in an interview. Use open-source examples or sanitized versions.

## Real Company Examples

### From Lesson

**BlackRock**: At BlackRock, engineers do not have direct `kubectl` access to production clusters. They write YAML, open a Pull Request, and a CI pipeline runs tests. When the PR is merged, ArgoCD detects the new commit and deploys it. If an outage occurs, they can literally `git revert` the commit, and ArgoCD instantly rolls back the entire cluster state.

## Common Myths

### From Lesson

- Myth: "I need to know Go to be a Kubernetes Engineer." Fact: False. While Go is used to write Kubernetes operators, most Kubernetes engineering is YAML, Helm charts, and configuring infrastructure.
- Myth: "You need a CS degree." Fact: False. The best Platform Engineers often come from a systems administration or self-taught DevOps background.

## Quiz

### From Lesson (True/False and Rapid Fire)

1. True/False: Taints repel Pods, while Tolerations allow Pods to bypass Taints. (Answer: True)
2. True/False: The Kubernetes Metrics Server stores historical data in etcd. (Answer: False - it is in-memory only.)
3. Rapid Fire: What port does etcd listen on? (2379)
4. Rapid Fire: What QoS class requires Requests == Limits? (Guaranteed)
5. Rapid Fire: What CNI uses eBPF to bypass iptables? (Cilium)
6. Rapid Fire: What command shows the history of a Helm release? (`helm history <name>`)

### Additional Production Knowledge

7. Which controller reconciles the running number of Pods toward the desired state? (The ReplicaSet controller.)
8. A Pod is scheduled but never starts; `kubectl describe pod` shows `Events` with `FailedScheduling`. Which workload binding the Pod to a node? (kube-scheduler, and it was blocked by scheduling constraints.)
9. True or False: A canary of 10% traffic, with no AnalysisTemplate, is safer than a blind rolling update. (Partially True: only if a metric or manual pause gates the promotion; without a gate it is still blind.)
10. Which component provides the initial metrics that the HPA uses for autoscaling? (kubelet/cAdvisor surfaced via the Metrics API, not etcd.)

## Revision Notes and Cheat Sheet

### One-Minute Revision

- **Architecture**: CI -> Git -> ArgoCD -> K8s -> Ingress -> Pod.
- **Debugging**: get -> describe -> logs -> endpoints.
- **Security**: RBAC + NetworkPolicy + SecurityContext + Kyverno.
- **Career**: Build a portfolio, get CKA, use the STAR method.

### Golden Rules of Kubernetes Engineering

- Declarative over Imperative: GitOps is king.
- Probes are Mandatory: Liveness and Readiness save lives.
- Least Privilege: Drop all capabilities, run as a non-root.
- Automate Everything: If you do it twice, script it. If you do it three times, automate it with an Operator.
- Observe Everything: Metrics tell you what, Logs tell you why.

### Cheat Sheet

| Concept | Tool / Command |
|---------|----------------|
| CI/CD | GitHub Actions + ArgoCD |
| Package Mgmt | Helm |
| Monitoring | Prometheus + Grafana |
| Logging | Loki + Promtail |
| Progressive Delivery | Argo Rollouts |
| Security | Kyverno + SecurityContext + NetworkPolicy |
| CKA Speed | `alias k=kubectl`, `export do='--dry-run=client -o yaml'` |

## Interview Preparation (The Ultimate Guide)

### Beginner Questions

Q: What is the difference between a Pod and a Container?

A: A container is a Linux process isolated by namespaces and cgroups. A Pod is a Kubernetes abstraction that wraps one or more containers, giving them a shared network IP and shared volumes.

### Intermediate Questions

Q: What happens when you run `kubectl run nginx --image=nginx`?

A:
1. kubectl sends a POST request to the API Server with a Pod manifest.
2. The API Server authenticates and authorizes the request (RBAC).
3. The request passes the admission controllers (for example, Kyverno).
4. The Pod is saved to etcd.
5. The kube-scheduler notices the Pod is Pending, filters nodes (taints, affinity) and scores them, then binds the Pod to a node.
6. The kubelet on that node notices the new Pod.
7. The kubelet calls the CRI (containerd) to pull the image and start the container via runc.
8. The kubelet reports the Pod status back to the API Server.

### Advanced / Scenario Questions

Q: You deployed a new version of your app. It passes Readiness probes, but users say the app is broken. How do you fix it, and how could Argo Rollouts have prevented it?

A: First, I revert immediately using `kubectl rollout undo`. To prevent it, I would use Argo Rollouts with a Canary strategy, sending 10% of traffic to the new version. An AnalysisTemplate would query Prometheus for 5xx error rates. If errors spiked, Argo would automatically abort and revert the traffic to the stable version.

## Scenario Questions

### Additional Production Knowledge

1. Q: A database StatefulSet reports that a single replica cannot connect to its quorum. The Service is a normal ClusterIP. What is the likely cable and the fix? A: The replica talks to peers by DNS name; a headless Service is required to expose per-Pod DNS A records so the replicas can address each other directly. Change the Service to `clusterIP: None`.
2. Q: You configure ArgoCD to sync a new image, but the rollout never leaves the Ingress. What do you check? A: Verify the Rollout reached a `pause` step or the AnalysisRun reported failures, then check the Rollout's status and the canary Service endpoints for the target Pods.
3. Q: A rollout to a new image is progressing, but users report slow responses. Where do you look? A: Follow the troubleshooting funnel: Ingress logs, then the target Service endpoints, then the Pod status and container Health probes.

## Mini Project

### From Lesson

Project: The Portfolio Repository.

1. Create a new public GitHub repository.
2. Add your Helm chart from Lesson 39.
3. Add your GitHub Actions workflow from Lesson 45.
4. Add a README.md explaining the architecture (use the diagram from this lesson).
5. Put the link to this repository on your LinkedIn profile and resume.

## Homework and Additional Reading

### From Lesson

- **Homework**: Schedule your CKA exam. Having a date on the calendar forces you to review and practice.
- **Additional Reading**: The Kubernetes Book, Site Reliability Engineering (Google), ArgoCD Documentation.

## References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Argo Rollouts Documentation](https://argoproj.github.io/argo-rollouts/)
- [The Kubernetes Book](https://www.amazon.com/Kubernetes-Book-Nigel-Poulton-books/dp/1538987359/)
- [Site Reliability Engineering (Google)](https://sre.google/sre-book/table-of-contents/)

## Related Lessons

- [Lesson 39 - Helm Deep Dive](../09-packaging/lesson-39-helm-deep-dive-writing-production-charts.md) - the charts you put into the portfolio project.
- [Lesson 45 - CI/CD Pipelines (GitHub Actions and ArgoCD)](../10-gitops/lesson-45-cicd-pipelines-github-actions-and-argocd.md) - the CI/CD you reference in the portfolio.
- [Lesson 46 - Progressive Delivery (Argo Rollouts)](../12-production/lesson-46-progressive-delivery-argo-rollouts.md) - the rollouts that make the canary safe.

## Coming Next

Congratulations. You have reached the end of the course. You started by learning what a Linux namespace is, and you ended by designing a multi-cluster, GitOps-driven, auto-scaling, self-healing, zero-trust platform with progressive delivery and centralized observability. You are no longer someone who only "uses Kubernetes." You understand how it works under the hood, how to break it, and how to fix it under pressure.

Keep building the portfolio, schedule your CKA, and go earn the role. This repository is now your reference, your interview guide, and your proof of skill.