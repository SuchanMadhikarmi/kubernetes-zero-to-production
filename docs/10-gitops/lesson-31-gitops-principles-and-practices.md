---
title: Lesson 31 - GitOps Principles and Practices
module: 10 GitOps
lesson: 31
status: Complete
tags: [kubernetes, gitops, argocd, continuous-deployment, reconciliation, self-heal, drift, pull-based-cd]
---

# Lesson 35 - GitOps Principles and Practices

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

- Explain the philosophy of GitOps and why it is the industry standard for deployments.
- Describe the difference between Push-based and Pull-based CI/CD.
- Explain what ArgoCD is and how it uses the Kubernetes reconciliation pattern.
- Install ArgoCD and deploy an app directly from Git.
- Explain how selfHeal automatically fixes "configuration drift".

## Prerequisites

- Completion of Lessons 1 through 15.
- A running kind cluster.
- kubectl installed and configured.

## Real-world Motivation

### The Snowflake Cluster

Imagine an engineer gets paged at 2 AM because the production API is latency-spiking. They SSH into the cluster (or use `kubectl edit`) and change the CPU limit from 500m to 1000m. The crisis is averted. However, they forget to update the Git repository. Two weeks later, a different engineer redeploys the application from Git. The CPU limit reverts to 500m, and the latency spike happens again. The cluster state was "hidden" and untraceable.

### Why This Exists

To prevent untraceable manual changes, the industry adopted GitOps. The rule is simple: Git is the single source of truth. If you want to change the cluster, you make a Git commit. If someone makes a manual change via `kubectl`, ArgoCD immediately sees the cluster "drifted" from Git and overwrites the manual change. Every change is now auditable, reversible, and secure.

### Real Company Examples

**BlackRock:** At BlackRock, engineers do not have `kubectl` access to production clusters. They write YAML, open a Pull Request. A CI pipeline runs tests. When the PR is merged, ArgoCD detects the new commit and deploys it. If an outage occurs, they can literally `git revert` the commit, and ArgoCD instantly rolls back the entire cluster state.

## Core Concepts

### Explain Like I'm 12

Imagine you have a recipe book (Git). You give the recipe book to a robot chef (ArgoCD). The chef cooks the meal exactly as the book says. If you want more salt, you don't run into the kitchen and sprinkle salt on the food (that's manual `kubectl edit`). You rewrite the recipe book. The chef sees the new recipe, throws away the old food, and cooks a fresh, correct batch. If a mischievous kid sneaks into the kitchen and adds hot sauce, the chef instantly notices it doesn't match the recipe book, throws it away, and cooks a fresh, correct batch.

### Explain Like I'm a Junior Engineer

GitOps means your entire Kubernetes YAML state lives in a Git repository. ArgoCD is a tool that runs inside your Kubernetes cluster. It continuously polls your Git repository. It compares the YAML in Git (Desired State) with the YAML running in the cluster (Live State). If they don't match, ArgoCD can automatically sync them (making Git win).

### Explain Technically

- ArgoCD is implemented as a Kubernetes controller. It introduces a new Custom Resource Definition (CRD) called an `Application`.
- An `Application` object specifies a Git repo, a path in that repo, and a destination cluster/namespace.
- The ArgoCD controller watches these `Application` objects. It fetches the Git repo, renders the YAML (it natively supports Helm and Kustomize), and compares it against the live cluster resources using the Kubernetes API.
- If auto-sync is enabled, it sends PATCH requests to align the cluster with Git.

### How Kubernetes Implements It Internally

By using Custom Resource Definitions (CRDs), ArgoCD integrates natively with Kubernetes. An "Application" is just another Kubernetes object stored in etcd. This means you can use `kubectl get applications` to see what ArgoCD is managing, and you can even manage ArgoCD itself using GitOps!

### Why Kubernetes Was Designed That Way

Kubernetes was designed to be declarative. You declare the desired state, and the controller reconciles the actual state to match. ArgoCD extends this pattern to Git. Git becomes the source of desired state, and ArgoCD becomes the controller that reconciles the cluster to match.

## Architecture

```
[ Engineer commits YAML to GitHub ]
      |
      v
[ Git Repository (Source of Truth) ]
      |
      v (ArgoCD polls Git continuously)
[ ArgoCD Controller (inside K8s) ]
      |
      v (Compares Git Desired State vs Live Cluster State)
[ If Different -> Applies YAML to API Server ]
```

### Terminology

| Term | Definition |
|------|------------|
| GitOps | A framework where Git is the single source of truth for infrastructure. |
| ArgoCD | A declarative, GitOps continuous delivery tool for Kubernetes. |
| Application (CRD) | An ArgoCD object that defines the relationship between a Git repo and a K8s namespace. |
| Drift | When the live cluster state differs from the Git repository. |
| Sync | The act of ArgoCD applying the Git state to the cluster. |

### How It Works Internally

1. You install ArgoCD into the `argocd` namespace.
2. You create an `Application` YAML pointing to `https://github.com/my-repo/my-app`.
3. The ArgoCD controller notices the new `Application`.
4. The ArgoCD Repo Server clones the Git repository and renders the YAML.
5. The controller queries the K8s API Server for the live resources.
6. It diffs the two. If they match, the app is `Healthy` and `Synced`.
7. If they differ, the app is `OutOfSync`. If auto-sync is on, ArgoCD sends the apply/patch requests.

### Step-by-Step Workflow

1. Developer writes YAML (or Helm chart) and pushes it to GitHub.
2. ArgoCD polls GitHub and detects the new commit.
3. ArgoCD detects the Live Cluster is now `OutOfSync` with Git.
4. Because Auto-Sync is enabled, ArgoCD applies the new YAML to the API Server.
5. The cluster updates (e.g., new Pods are created).
6. A rogue admin runs `kubectl scale deploy my-app --replicas=5` (but Git says 3).
7. ArgoCD detects the drift. `selfHeal` triggers.
8. ArgoCD scales the Deployment back to 3 to match Git.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | `Application` CRD is applied. ArgoCD begins tracking. |
| Synced | Live state matches Git. |
| OutOfSync | Git changed, or cluster changed. Live state does not match Git. |
| Degraded | The application is deployed but failing (e.g., CrashLoopBackOff). |
| Deletion | Application is deleted. ArgoCD can optionally cascade delete the resources. |

### Feature Comparison

| Feature | Traditional CI/CD (Jenkins) | GitOps (ArgoCD) |
|---------|----------------------------|-----------------|
| Trigger | Jenkins pushes to cluster | ArgoCD pulls from Git |
| Source of Truth | Jenkins job config | Git Repository |
| Cluster Access | Needs kubeconfig credentials | Needs none (runs inside) |
| Manual Changes | Allowed (causes drift) | Overwritten (self-heal) |
| Rollback | Re-run old Jenkins job | `git revert` |

### Common Myths

| Myth | Fact |
|------|------|
| "ArgoCD replaces GitHub Actions or Jenkins." | False. ArgoCD is for Continuous Deployment (CD). It deploys YAML to Kubernetes. You still need a Continuous Integration (CI) tool (like GitHub Actions) to compile code, run unit tests, and build Docker images. The CI tool updates the Git repo; ArgoCD deploys it. |
| "GitOps means you can't use Helm." | False. ArgoCD natively supports Helm. You point ArgoCD at a Git repo containing a `Chart.yaml` and `values.yaml`, and ArgoCD renders it and deploys it. |

## ASCII Diagrams

Mental Model: Git is the "Brain". ArgoCD is the "Hands". The Hands constantly check what the Brain is thinking, and physically reshape the cluster to match the Brain.

```
[ Git Repo (Desired State) ] <--- (Engineer commits here)
      |
      | (ArgoCD polls every 3 mins)
      v
[ ArgoCD Application Controller ]
      |
      +---> Compares Git vs Live Cluster
      |
      v
[ Kubernetes API Server ] (Applies changes to Pods, Services, etc.)
```

## Hands-on

### Objective

Install ArgoCD, deploy an app from a public Git repository, and then try to manually break it to watch ArgoCD self-heal.

### Step 1: Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for all the ArgoCD pods to be running:

```bash
kubectl get pods -n argocd
```

### Step 2: Access the ArgoCD UI

Get the admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

Open a second terminal window and run this to port-forward the UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open your web browser and go to: `https://localhost:8080`

(Your browser will warn you about a self-signed certificate. Click "Advanced" -> "Proceed to localhost").

- Username: `admin`
- Password: (Paste the password from above)

### Step 3: Create an ArgoCD Application via YAML

Create `argo-app.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Field Explanation:**

- `source.repoURL`: The Git repo to watch.
- `source.path`: The folder in the repo containing the YAML.
- `destination.namespace`: Where to deploy the app in our cluster.
- `syncPolicy.automated.selfHeal: true`: CRITICAL. Tells ArgoCD to overwrite manual changes.

Apply it:

```bash
kubectl apply -f argo-app.yaml
```

### Step 4: Watch it Deploy

Go back to your browser UI. Click on the guestbook application. You will see a visual tree of the Deployment and Service. It should turn green and say "Healthy" and "Synced".

Verify in your terminal:

```bash
kubectl get pods -n default
```

### Step 5: Self-Heal Test (Breaking Things on Purpose)

Scale the deployment:

```bash
kubectl scale deployment guestbook-ui --replicas=5
```

Verify it scaled up:

```bash
kubectl get pods -l app=guestbook-ui
```

(You should temporarily see 5 pods).

Wait for ArgoCD to react (about 10-20 seconds), then run the command again:

```bash
kubectl get pods -l app=guestbook-ui
```

**Your Task:**

- After waiting, how many pods are running now?
- Look at the ArgoCD UI in your browser. Did the UI color or status change temporarily when you scaled it?
- Based on the theory of `selfHeal: true`, explain exactly what ArgoCD did to your manual change.

(Answer: 1. 1 pod. 2. It likely flashed "OutOfSync" briefly. 3. ArgoCD noticed the live cluster had 5 replicas, but Git desired state had 1. Because `selfHeal` was true, it sent a PATCH to scale it back to 1).

### Step 6: Cleanup

```bash
kubectl delete application guestbook -n argocd
kubectl delete namespace argocd
kubectl delete deployment guestbook-ui
kubectl delete svc guestbook-ui
```

## Commands

```bash
# Lists ArgoCD Applications
kubectl get applications -n argocd

# Access the ArgoCD Web UI locally
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Manually trigger a sync (if auto-sync is off)
argocd app sync <name>

# Get the admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

# Check ArgoCD pod status
kubectl get pods -n argocd
```

## YAML Explanation

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Field-by-Field Explanation

- `apiVersion: argoproj.io/v1alpha1`: The ArgoCD API group.
- `kind: Application`: An ArgoCD CRD that defines what to deploy.
- `metadata.namespace: argocd`: The Application must live in the `argocd` namespace.
- `source.repoURL`: The Git repository to watch.
- `source.path`: The directory in the repo containing the manifests.
- `destination.server`: The Kubernetes API Server URL.
- `destination.namespace`: The target namespace for deployment.
- `syncPolicy.automated.prune: true`: Automatically delete resources removed from Git.
- `syncPolicy.automated.selfHeal: true`: Automatically revert manual changes.

## Production Notes

- **Separate App and Config Repos:** Developers commit code to an App repo. CI builds the Docker image and updates the Helm `values.yaml` in a separate Config repo. ArgoCD only watches the Config repo.
- **Use Webhooks:** ArgoCD polls Git every 3 minutes by default. For fast deployments, configure a GitHub webhook to instantly notify ArgoCD of a commit.
- **Enable Auto-Sync with Caution:** If an engineer deletes a critical YAML file in Git by accident, ArgoCD will instantly delete it from the cluster. Use branch protection (Pull Request reviews) on Git!

### When to Use / When NOT to Use

**Use ArgoCD when:**

- Managing production, staging, and dev environments.
- When you need strict auditability for cluster changes.
- When deploying Helm charts or Kustomize overlays.

**Avoid ArgoCD when:**

- For local development on your laptop. Just use `kubectl apply`.
- If your team is not mature enough to use Pull Requests for infrastructure changes.

### Performance and Security Considerations

**Performance:** ArgoCD polls Git every 3 minutes by default. In massive clusters with hundreds of apps, this can cause API Server load. Use webhooks to replace polling.

**Security:** ArgoCD has its own RBAC system. You can restrict which teams can sync which apps. Also, ensure your Git repositories are private and ArgoCD uses SSH keys to access them.

## Best Practices

- Separate App and Config repos.
- Use webhooks for faster sync.
- Enable branch protection on Git.
- Use specific image tags (never `latest`).
- Enable `selfHeal` in production.
- Monitor ArgoCD with its built-in UI.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Forgetting to commit to Git | Engineers run `kubectl apply` manually | Enforce GitOps workflow with branch protection |
| Using `latest` image tags | ArgoCD won't detect changes | Always use specific version tags or Git SHAs |
| Enabling Auto-Prune carelessly | Deleting a file from Git deletes it from the cluster | Use Pull Request reviews before merging |
| Not using webhooks | ArgoCD polls every 3 minutes | Configure GitHub webhooks for instant sync |

## Troubleshooting

**Symptom: Application shows "OutOfSync" but not syncing**

Cause: Auto-sync is not enabled.

```bash
kubectl get application <name> -n argocd -o yaml | grep automated
```

Fix: Enable `syncPolicy.automated` in the Application YAML.

**Symptom: Application shows "Degraded"**

Cause: The application is deployed but failing (e.g., CrashLoopBackOff).

```bash
kubectl get pods -n <namespace>
kubectl describe pod <name>
```

Fix: Check the application logs and fix the underlying issue.

**Symptom: ArgoCD not detecting Git changes**

Cause: Polling interval or webhook not configured.

```bash
kubectl get pods -n argocd
```

Fix: Wait for the polling interval (3 minutes) or configure a webhook.

## Interview Questions

**Q: What is GitOps?**

A: GitOps is an operational framework where Git is the single source of truth for infrastructure and application deployment. All changes are made via Git commits, and a tool (like ArgoCD) automatically synchronizes those changes to the cluster.

**Q: What is the difference between Push-based and Pull-based CD?**

A: Push-based (like Jenkins) requires the CI server to have credentials to push code to the cluster. Pull-based (like ArgoCD) runs an agent inside the cluster that pulls changes from Git. Pull-based is more secure because you don't need to expose cluster credentials externally.

**Q: What is Configuration Drift, and how does ArgoCD handle it?**

A: Drift occurs when the live state of the cluster differs from the desired state in Git (often caused by manual `kubectl edit`). ArgoCD detects this drift. If `selfHeal` is enabled, ArgoCD automatically sends PATCH requests to revert the cluster back to the Git state.

**Q: A developer merged a bad YAML file to Git. ArgoCD deployed it, and now production is down. How do you fix it?**

A: Because ArgoCD is GitOps, the fix is simple. I run `git revert <commit-sha>` to undo the bad commit. ArgoCD detects the revert, syncs the cluster back to the previous working state, and production recovers. No `kubectl rollout undo` required.

**Q: Does ArgoCD need inbound firewall rules to receive webhooks from GitHub?**

A: No. ArgoCD can use outbound polling, though webhooks are faster.

**Q: Can ArgoCD deploy Helm charts?**

A: Yes. ArgoCD natively supports Helm. You point ArgoCD at a Git repo containing a `Chart.yaml` and `values.yaml`, and ArgoCD renders it and deploys it.

## Scenario Questions

**Scenario 1:** You need to deploy the same application to three environments. How do you structure your Git repos?

A: I would create a Config repo with three directories: `dev/`, `staging/`, and `prod/`. Each directory contains the environment-specific `values.yaml`. I would create three ArgoCD Applications, each pointing to its respective directory.

**Scenario 2:** An engineer manually scales a Deployment to 10 replicas. ArgoCD reverts it. The engineer complains. How do you explain this?

A: This is expected behavior. ArgoCD's `selfHeal` ensures the cluster matches Git. If you need 10 replicas, update the `replicaCount` in Git and commit. ArgoCD will then scale to 10.

**Scenario 3 (Mini Project - The Drift Detector):**

Deploy an app using ArgoCD with `selfHeal: true`. Use `kubectl edit deployment <name>` to change the image tag to something else. Watch the ArgoCD UI. It should flash "OutOfSync". Wait 10 seconds. ArgoCD should automatically revert your change back to the Git state. Now, change `selfHeal: false` in the ArgoCD Application YAML. `kubectl edit` the deployment again. Observe that ArgoCD shows "OutOfSync" but does NOT fix it automatically.

## Quiz

1. What is GitOps?
   - A. A CI/CD tool
   - B. An operational framework where Git is the source of truth
   - C. A Kubernetes controller
   - D. A package manager

2. What is the difference between Push and Pull CD?
   - A. Push is more secure
   - B. Pull is more secure
   - C. They are the same
   - D. Push is for Kubernetes, Pull is for VMs

3. What happens when `selfHeal` is enabled?
   - A. ArgoCD ignores manual changes
   - B. ArgoCD automatically reverts manual changes
   - C. ArgoCD deletes the application
   - D. ArgoCD restarts all Pods

4. What is Configuration Drift?
   - A. Git repository changes
   - B. Live cluster state differs from Git
   - C. ArgoCD crashes
   - D. Pod crashes

5. How does ArgoCD detect changes in Git?
   - A. Webhooks only
   - B. Polling only
   - C. Both polling and webhooks
   - D. Manual refresh

Answers: 1-B, 2-B, 3-B, 4-B, 5-C.

## Revision

One-minute revision:

- Git = Source of truth.
- ArgoCD = Pulls from Git.
- Drift = Cluster != Git.
- Self-Heal = Overwrites manual changes.
- Push CI (Jenkins) vs Pull CD (ArgoCD).

Memory trick:

- **Git:** The blueprint for a house.
- **ArgoCD:** The strict building inspector. If someone paints a wall red manually, the inspector looks at the blueprint, sees it should be blue, and immediately repaints it blue.

Key facts:

- GitOps = Git is source of truth.
- ArgoCD = Pull-based CD.
- Drift = Cluster != Git.
- Self-Heal = Revert manual changes.
- CRD = Application object.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl get applications -n argocd` | Lists ArgoCD Applications |
| `kubectl port-forward svc/argocd-server -n argocd 8080:443` | Access the ArgoCD Web UI locally |
| `argocd app sync <name>` | Manually trigger a sync (if auto-sync is off) |

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [GitOps Principles](https://opengitops.dev/)
- [Kubernetes Documentation: CRDs](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)
- [ArgoCD Example Apps](https://github.com/argoproj/argocd-example-apps)

## Related Lessons

- [Lesson 42 - Helm](../09-packaging/lesson-29-helm.md) - packaging applications with Helm.
- [Helm Deep Dive](../09-packaging/lesson-30-helm-deep-dive-writing-production-charts.md) - Kubernetes-native configuration management.
- [ArgoCD Pipelines](lesson-32-cicd-pipelines-github-actions-and-argocd.md) - comparing GitOps tools.

## Coming Next

Now that you understand GitOps with ArgoCD, the next lesson covers the Operator pattern — how to extend Kubernetes with Custom Resource Definitions and custom controllers.
