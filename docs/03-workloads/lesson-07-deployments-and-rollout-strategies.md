---
title: Lesson 7 - Deployments and Rollout Strategies
module: 03 Workloads
lesson: 7
status: Complete
tags: [kubernetes, workloads, deployments, rolling-updates, rollbacks, maxsurge, maxunavailable, replicaset]
---

# Lesson 7 - Deployments and Rollout Strategies

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

- Explain how Kubernetes updates applications without causing downtime.
- Describe the RollingUpdate strategy and the `maxSurge` / `maxUnavailable` parameters.
- Explain how Deployments manage multiple ReplicaSets during an update.
- Perform a zero-downtime update.
- Use `kubectl rollout undo` to instantly revert a failed deployment.

## Prerequisites

- Completion of Lessons 1 through 20.
- A running kind cluster.
- kubectl installed and configured.

## Real-world Motivation

### The Downtime Window

Imagine you need to update your web application from version 1.0 to 2.0. In traditional environments, you shut down the old version, start the new version, and wait for it to boot. During those 2 minutes, users see a 503 Service Unavailable error. If the new version (2.0) has a critical bug and crashes on startup, your app is completely offline until you manually revert the code and restart the old version.

### Why This Exists

Kubernetes was designed for High Availability. To ensure zero downtime during updates, it uses the RollingUpdate strategy. Instead of killing all old Pods at once, it starts one new Pod. If that new Pod is healthy, it kills one old Pod. It repeats this until all Pods are running the new version. If the new Pods fail to start, Kubernetes can automatically pause the rollout, leaving the old Pods running to serve traffic.

### Real Company Examples

**Shopify:** Shopify deploys hundreds of times a day. They use strict `maxSurge: 1` and `maxUnavailable: 0`. This means Kubernetes can create 1 extra new Pod, but it is never allowed to kill an old Pod below the desired count. This guarantees zero capacity loss during deployments, ensuring traffic spikes during a deploy don't overload the remaining Pods.

## Core Concepts

### Explain Like I'm 12

Imagine you are changing the tires on a moving car. You can't take all 4 tires off at once, or the car crashes. Instead, you put on one new tire, make sure it holds, take off an old one, and repeat. If the new tire explodes, you quickly put the old tire back on.

### Explain Like I'm a Junior Engineer

When you change the image tag in a Deployment, Kubernetes doesn't kill all the old Pods at once. It starts one new Pod. If that new Pod is healthy, it kills one old Pod. It repeats this until all Pods are running the new version. If the new Pods fail to start, Kubernetes can automatically pause the rollout, leaving the old Pods running to serve traffic.

### Explain Technically

- The Deployment resource has a `strategy` field. The default is `RollingUpdate`.
- The DeploymentController calculates the math. If `replicas=4`, `maxSurge=1`, `maxUnavailable=1`:
  1. Scale v2 up by 1. (Total: 5 pods. v1=4, v2=1).
  2. Scale v1 down by 1. (Total: 4 pods. v1=3, v2=1).
  3. Scale v2 up by 1. (Total: 5 pods. v1=3, v2=2).
  4. Scale v1 down by 1. (Total: 4 pods. v1=2, v2=2).
  5. ... repeats until v1=0, v2=4.
- The old ReplicaSet (v1) is kept scaled to 0, not deleted. This is what allows for instant rollbacks!

### How Kubernetes Implements It Internally

The DeploymentController runs in the kube-controller-manager. When you update the `spec.template` (e.g., change the image), the controller creates a new ReplicaSet with a new hash label. It continuously reconciles the state: scaling up the new RS and scaling down the old RS, respecting the `maxSurge` and `maxUnavailable` boundaries. Crucially, it checks the Readiness Probes of the new Pods before proceeding with the next batch.

### Why Kubernetes Was Designed That Way

Kubernetes was designed for High Availability. The RollingUpdate strategy ensures that applications are always available during updates. By keeping old ReplicaSets, Kubernetes allows instant rollbacks without re-deploying from scratch.

## Architecture

```
Time 1: [ ReplicaSet v1: Pod1, Pod2, Pod3, Pod4 ] (Desired: 4)
Time 2: [ ReplicaSet v1: Pod1, Pod2, Pod3, Pod4 ] + [ ReplicaSet v2: Pod5 ] (maxSurge=1)
Time 3: [ ReplicaSet v1: Pod2, Pod3, Pod4 ] + [ ReplicaSet v2: Pod5 ] (maxUnavailable=1)
Time 4: [ ReplicaSet v1: Pod2, Pod3, Pod4 ] + [ ReplicaSet v2: Pod5, Pod6 ]
Time 5: [ ReplicaSet v1: Pod3, Pod4 ] + [ ReplicaSet v2: Pod5, Pod6 ]
...Final:  [ ReplicaSet v1: (0 Pods) ] + [ ReplicaSet v2: Pod5, Pod6, Pod7, Pod8 ]
```

### Terminology

| Term | Definition |
|------|------------|
| RollingUpdate | A deployment strategy that gradually replaces old Pods with new ones. |
| maxSurge | The maximum number of extra Pods that can be created above the desired count. |
| maxUnavailable | The maximum number of Pods that can be unavailable below the desired count. |
| Recreate | A deployment strategy that kills ALL old Pods before starting new ones (causes downtime). |
| Revision History | The list of previous ReplicaSets kept by a Deployment for rollback purposes. |

### How It Works Internally

1. You apply a new Deployment YAML with `image: nginx:1.26`.
2. The DeploymentController creates ReplicaSet v2 (hash: d8f765).
3. ReplicaSet v2 creates 1 Pod (Pod-5).
4. The Scheduler assigns Pod-5 to a node. Kubelet starts it.
5. Kubelet checks the Readiness Probe. If it fails, the rollout pauses. v1 is untouched.
6. If Readiness passes, the DeploymentController scales ReplicaSet v1 down by 1 (Pod-1 is deleted).
7. The loop repeats until ReplicaSet v1 has 0 replicas and ReplicaSet v2 has 4 replicas.

### Step-by-Step Workflow

1. Developer updates the Deployment YAML (e.g., new image tag).
2. `kubectl apply` sends it to the API Server.
3. DeploymentController creates a new ReplicaSet (Revision 2).
4. New ReplicaSet creates 1 Pod.
5. Pod passes Readiness Probe.
6. Old ReplicaSet (Revision 1) scales down by 1 Pod.
7. Process repeats until all Pods are on Revision 2.

### Lifecycle

| State | Description |
|-------|-------------|
| Scaling | A Deployment can be scaled up or down instantly without a rolling update. |
| Updating | Changing the Pod template triggers a Rolling Update. |
| Pausing | A rollout can be manually paused (`kubectl rollout pause`). |
| Rollback | Reverting to a previous revision (`kubectl rollout undo`). |
| Deletion | Deleting a Deployment cascades to delete all ReplicaSets and Pods. |

### Strategy Comparison

| Strategy | Behavior | Downtime | Use Case |
|----------|----------|----------|----------|
| RollingUpdate | Gradually replaces Pods (default) | None | Standard web apps, APIs |
| Recreate | Kills ALL old Pods, then starts new ones | Yes | Apps that cannot run two versions at once |

### Common Myths

| Myth | Fact |
|------|------|
| "A rolling update modifies the existing Pods in place." | False. Kubernetes creates brand new Pods with a new ReplicaSet. The old Pods are deleted. The containers are never "updated" in place. |
| "If a rollout fails, Kubernetes automatically rolls it back." | False. Kubernetes pauses the rollout (leaving old Pods running), but it does NOT roll back automatically. You must run `kubectl rollout undo` manually. |

## ASCII Diagrams

Mental Model: A baton pass in a relay race. The new runner (v2 ReplicaSet) starts running. The old runner (v1 ReplicaSet) hands off the baton (traffic) and then steps off the track. If the new runner trips (crashes), the old runner is still there to keep running.

```
[ v2 ReplicaSet ] (Pod 5 starts, passes Readiness Probe)
      |
      v
[ Deployment Controller ] (Scales v1 down by 1)
      |
      v
[ v1 ReplicaSet ] (Pod 1 is killed)
```

## Hands-on

### Objective

Deploy an app, perform a zero-downtime update, and then simulate a bad deploy and roll it back.

### Step 1: Create the Deployment

Create `rollout-deploy.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rollout-app
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  selector:
    matchLabels:
      app: rollout
  template:
    metadata:
      labels:
        app: rollout
    spec:
      containers:
      - name: app
        image: nginx:1.25-alpine
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 2
          periodSeconds: 2
```

**Field Explanation:**

- `strategy.type: RollingUpdate`: The default, but explicitly stated.
- `maxSurge: 1`: Kubernetes can burst to 5 Pods.
- `maxUnavailable: 1`: Kubernetes can drop to 3 Pods.
- `readinessProbe`: Ensures traffic isn't routed to the new Pod until Nginx is actually ready.

Apply it:

```bash
kubectl apply -f rollout-deploy.yaml
```

Wait for all 4 to be running.

### Step 2: Perform a Zero-Downtime Update (v2)

Update the image to version 1.26:

```bash
kubectl set image deployment/rollout-app app=nginx:1.26-alpine
```

Watch the rollout happen in real-time:

```bash
kubectl rollout status deployment/rollout-app
```

(It should say "deployment successfully rolled out").

Check the ReplicaSets:

```bash
kubectl get replicasets -l app=rollout
```

(You will see two ReplicaSets! v1 will have 0 desired/ready pods. v2 will have 4).

### Step 3: Break Things on Purpose

Update to an image tag that doesn't exist:

```bash
kubectl set image deployment/rollout-app app=nginx:broken-tag
```

Watch the status:

```bash
kubectl rollout status deployment/rollout-app
```

(Press Ctrl+C after a few seconds to stop watching. It will hang, waiting for the broken pods to become ready).

### Step 4: Investigate the Stuck Rollout

```bash
kubectl get pods -l app=rollout
```

**Your Task:**

- What states are the Pods in? (You should see a mix of Running and ImagePullBackOff).
- How many Pods are Running vs ImagePullBackOff?
- Why didn't Kubernetes kill all the v2 (1.26) pods? Based on the `maxUnavailable` setting, how is Kubernetes protecting your users right now?

(Answer: 1. Mix of Running and ImagePullBackOff. 2. 3 Running, 2 ImagePullBackOff (because maxSurge=1). 3. maxUnavailable is 1. K8s is not allowed to drop below 3 healthy pods. It scaled v2 down to 3, and tried to scale v3 up to 2. Because v3 is broken, it froze the rollout. Users are still being served by the 3 healthy v2 pods).

### Step 5: The Instant Rollback

```bash
kubectl rollout undo deployment/rollout-app
```

### Step 6: Verify the Recovery

Wait about 10 seconds, then run:

```bash
kubectl get pods -l app=rollout
kubectl get replicasets -l app=rollout
```

**Your Task:**

- After the rollback, what happened to the ImagePullBackOff pods?
- How many healthy Running pods do you have now?
- Look at the ReplicaSets. Did the DESIRED count of the healthy ReplicaSet (v2) go back up to 4?

(Answer: 1. They were deleted. 2. 4. 3. Yes, v2 scaled back up to 4, and v3 scaled down to 0).

### Step 7: Cleanup

```bash
kubectl delete deployment rollout-app
```

## Commands

```bash
# Imperatively updates a Deployment image
kubectl set image deployment/<name> <container>=<new-image>

# Watches the rollout progress in real-time
kubectl rollout status deployment/<name>

# Reverts to the previous ReplicaSet version
kubectl rollout undo deployment/<name>

# Shows the revision history
kubectl rollout history deployment/<name>

# Pauses a rollout
kubectl rollout pause deployment/<name>

# Resumes a paused rollout
kubectl rollout resume deployment/<name>
```

## YAML Explanation

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rollout-app
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  selector:
    matchLabels:
      app: rollout
  template:
    metadata:
      labels:
        app: rollout
    spec:
      containers:
      - name: app
        image: nginx:1.25-alpine
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 2
          periodSeconds: 2
```

### Field-by-Field Explanation

- `strategy.type`: `RollingUpdate` (default) or `Recreate`.
- `rollingUpdate.maxSurge`: Maximum extra Pods above desired count.
- `rollingUpdate.maxUnavailable`: Maximum Pods below desired count.
- `readinessProbe`: Ensures new Pods are ready before old Pods are killed.

## Production Notes

- **Always use Readiness Probes:** Without a Readiness Probe, Kubernetes assumes the new Pod is ready instantly and routes traffic to it, causing 502 errors while the app boots.
- **Use `maxUnavailable: 0`:** If you absolutely cannot lose any capacity during a deploy, set `maxUnavailable: 0` and `maxSurge: 1`. Kubernetes will create the new Pod first, wait for it to be ready, and only then kill the old one.
- **Keep Revision History:** Set `revisionHistoryLimit` (e.g., to 10) so you can roll back if a bug is discovered days later.

### When to Use / When NOT to Use

**Use RollingUpdate when:**

- 99% of stateless web applications.
- When you need zero downtime and your app supports multiple versions running simultaneously.

**Avoid RollingUpdate when:**

- If your app requires a database schema migration before the new code can run. (v2 code will crash if v1 DB schema is present). Use Recreate or pause the rollout manually.

### Performance and Security Considerations

**Performance:** Rolling updates take time. If you have 100 replicas, updating them 1 by 1 is slow. Increase `maxSurge` to allow faster rollouts (if your cluster has the capacity).

**Security:** During a rolling update, two versions of your app are running simultaneously. Ensure your database schema is backward-compatible, or the new version will crash when it tries to read the old schema.

## Best Practices

- Always use Readiness Probes.
- Use `maxUnavailable: 0` for critical services.
- Keep revision history for rollbacks.
- Never use `latest` image tags.
- Test rollbacks in staging.
- Monitor rollouts with `kubectl rollout status`.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Using `latest` tags | String doesn't change, no update triggered | Always use specific version tags or Git SHAs |
| Changing labels/selectors | Breaks the tracking mechanism | Never change the selector field on a Deployment |
| Forgetting to undo a rollback | Accidentally triggering another rollback | Ensure you fix the code before rolling forward |
| Not using Readiness Probes | Kubernetes routes traffic to unready Pods | Always configure Readiness Probes |

## Troubleshooting

**Symptom: Rollout hangs forever**

Cause: New Pods failing Readiness Probe.

```bash
kubectl get pods -l app=<name>
kubectl describe pod <name>
```

Fix: Check Readiness Probe configuration and fix the underlying issue.

**Symptom: ImagePullBackOff during rollout**

Cause: Image tag doesn't exist.

```bash
kubectl rollout undo deployment/<name>
```

Fix: Use `kubectl rollout undo` to revert to the previous version.

**Symptom: Rollback not working**

Cause: No previous ReplicaSet history.

```bash
kubectl rollout history deployment/<name>
```

Fix: Ensure `revisionHistoryLimit` is set (default is 10).

## Interview Questions

**Q: How do you safely update an application in Kubernetes without downtime?**

A: I use the default RollingUpdate strategy. I ensure a Readiness Probe is configured so Kubernetes only routes traffic to the new Pods once they are actually ready. I set `maxSurge` and `maxUnavailable` to control the rollout speed. If the new version is broken, I use `kubectl rollout undo` to instantly revert to the previous version.

**Q: What is the difference between `maxSurge` and `maxUnavailable`?**

A: `maxSurge` is how many extra new Pods can be created above the desired count. `maxUnavailable` is how many old Pods can be taken down below the desired count.

**Q: If a Deployment update results in ImagePullBackOff, what happens to the old Pods?**

A: They keep running. Kubernetes freezes the rollout based on `maxUnavailable` to ensure no downtime. The old Pods continue to serve traffic until the issue is resolved or a rollback is initiated.

**Q: How does Kubernetes roll back a Deployment so quickly?**

A: It doesn't delete the old ReplicaSet; it scales it to 0. To roll back, it simply scales the old ReplicaSet back up and the broken one down.

**Q: A rolling update modifies the existing Pods in place. True or False?**

A: False. Kubernetes creates brand new Pods with a new ReplicaSet. The old Pods are deleted.

**Q: You must manually delete old ReplicaSets after a rolling update. True or False?**

A: False. Deployment manages them for rollbacks.

## Scenario Questions

**Scenario 1:** You deployed a new version of your app. It passes the Readiness Probe, but users are complaining that the app is broken. How do you revert it?

A: First, I revert immediately using `kubectl rollout undo deployment <name>`. Then, I investigate the failed Pods. Because the old ReplicaSet was scaled up, the broken Pods might be terminating. I need to check the logs of the broken Pods before they disappear, or look at monitoring tools to see what errors users were receiving.

**Scenario 2:** You need to update an app that requires a database schema migration. How do you handle this?

A: I would use the Recreate strategy or pause the rollout manually. The old version must be completely stopped before the new version starts, because the new version requires the new schema.

**Scenario 3 (Mini Project - The Strict Capacity Test):**

Deploy an app with 4 replicas, `maxSurge: 1`, and `maxUnavailable: 0`. Update the image to a bad tag. Observe that Kubernetes creates 1 broken Pod, but refuses to kill ANY of the 4 healthy Pods (because `maxUnavailable` is 0). Run `kubectl get pods` and verify you still have exactly 4 Running pods and 1 ImagePullBackOff pod.

## Quiz

1. What is the default Deployment strategy?
   - A. Recreate
   - B. RollingUpdate
   - C. Blue/Green
   - D. Canary

2. What does `maxSurge` control?
   - A. Maximum extra new Pods
   - B. Maximum unavailable old Pods
   - C. Maximum total Pods
   - D. Maximum restart count

3. What happens to old ReplicaSets after a rolling update?
   - A. They are deleted
   - B. They are scaled to 0 and kept for rollback
   - C. They keep running
   - D. They are archived

4. How do you instantly revert a failed deployment?
   - A. `kubectl delete deployment <name>`
   - B. `kubectl rollout undo deployment/<name>`
   - C. `kubectl scale deployment/<name> --replicas=0`
   - D. `kubectl rollout restart deployment/<name>`

5. What is required for zero-downtime rolling updates?
   - A. Liveness Probe
   - B. Readiness Probe
   - C. Startup Probe
   - D. All of the above

Answers: 1-B, 2-A, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- RollingUpdate = Gradual shift.
- maxSurge = Extra new Pods.
- maxUnavailable = Missing old Pods.
- Readiness Probe = Required for zero-downtime.
- `rollout undo` = Instant revert.

Memory trick:

- **Rolling Update:** Changing the tires on a moving car. You never let the car drop to the ground (0 tires).
- **Old ReplicaSet:** A safety net. When the new acrobat (v3) falls, the net (v2) is still there to catch the traffic.
- **`rollout undo`:** The "Ctrl+Z" for your cluster.

Key facts:

- RollingUpdate = Gradual replacement.
- maxSurge = How many extra.
- maxUnavailable = How many missing.
- Readiness = Gatekeeper.
- Old RS = Rollback source.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl set image deployment/<name> <container>=<new-image>` | Imperatively updates a Deployment image |
| `kubectl rollout status deployment/<name>` | Watches the rollout progress in real-time |
| `kubectl rollout undo deployment/<name>` | Reverts to the previous ReplicaSet version |
| `kubectl rollout history deployment/<name>` | Shows the revision history |

## References

- [Kubernetes Documentation: Deployment Strategy](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)
- [Kubernetes Documentation: Rolling Update](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update-deployment)
- [Kubernetes Documentation: Rollback](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rollback)

## Related Lessons

- [Lesson 6 - Pods, ReplicaSets, and Deployments](lesson-06-pods-replicasets-and-deployments.md) - how Pods and Deployments work.
- [Lesson 36 - Probes and Health Checks](../08-observability/lesson-26-probes-and-health-checks.md) - Readiness Probes for zero-downtime.
- [Lesson 31 - GitOps Principles and Practices](../10-gitops/lesson-31-gitops-principles-and-practices.md) - Git-based deployments.

## Coming Next

Now that you understand how to update applications safely, the next lesson covers StatefulSets — how to run stateful applications like databases on Kubernetes.
