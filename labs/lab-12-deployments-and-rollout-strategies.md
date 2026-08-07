# Lab 12 - Deployments and Rollout Strategies

## Prerequisite

- Completion of [Lesson 12 - Deployments and Rollout Strategies](../docs/03-workloads/lesson-12-deployments-and-rollout-strategies.md).
- A running kind cluster.
- kubectl installed and configured.

## Objective

Deploy an app, perform a zero-downtime update, and then simulate a bad deploy and roll it back.

## Estimated Time

15 minutes.

---

## Step 1: Create the Deployment

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

Apply it:

```bash
kubectl apply -f rollout-deploy.yaml
```

Wait for all 4 to be running:

```bash
kubectl get pods -l app=rollout
```

## Step 2: Perform a Zero-Downtime Update (v2)

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

## Step 3: Break Things on Purpose

Update to an image tag that doesn't exist:

```bash
kubectl set image deployment/rollout-app app=nginx:broken-tag
```

Watch the status:

```bash
kubectl rollout status deployment/rollout-app
```

(Press Ctrl+C after a few seconds to stop watching. It will hang, waiting for the broken pods to become ready).

## Step 4: Investigate the Stuck Rollout

```bash
kubectl get pods -l app=rollout
```

**Your Task:**

- What states are the Pods in? (You should see a mix of Running and ImagePullBackOff).
- How many Pods are Running vs ImagePullBackOff?
- Why didn't Kubernetes kill all the v2 (1.26) pods? Based on the `maxUnavailable` setting, how is Kubernetes protecting your users right now?

(Answer: 1. Mix of Running and ImagePullBackOff. 2. 3 Running, 2 ImagePullBackOff (because maxSurge=1). 3. maxUnavailable is 1. K8s is not allowed to drop below 3 healthy pods. It scaled v2 down to 3, and tried to scale v3 up to 2. Because v3 is broken, it froze the rollout. Users are still being served by the 3 healthy v2 pods).

## Step 5: The Instant Rollback

```bash
kubectl rollout undo deployment/rollout-app
```

## Step 6: Verify the Recovery

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

## Step 7: Cleanup

```bash
kubectl delete deployment rollout-app
```

---

## What You Learned

- A RollingUpdate strategy deploys new Pods gradually, ensuring there are always enough healthy Pods to serve traffic.
- `maxSurge`: How many extra new Pods can be created (allows bursting).
- `maxUnavailable`: How many Pods can be down (limits risk).
- When an update fails (e.g., ImagePullBackOff), Kubernetes freezes the rollout. It will not violate `maxUnavailable`, so your old, healthy Pods stay running.
- `kubectl rollout undo` instantly reverts the Deployment to the previous ReplicaSet.

## Next Steps

Proceed to [Lesson 13 - StatefulSets](../docs/03-workloads/lesson-13-statefulsets.md) to learn about running stateful applications.

---

[Back to Labs](README.md)
