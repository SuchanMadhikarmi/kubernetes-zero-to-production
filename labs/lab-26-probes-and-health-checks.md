# Lab 26 - Probes and Health Checks

## Prerequisite

- Completion of [Lesson 26 - Probes and Health Checks](../docs/08-observability/lesson-26-probes-and-health-checks.md).
- A running kind cluster.
- kubectl installed and configured.

## Objective

Deploy an app with a Liveness probe pointing to a bad path. Watch Kubernetes kill and restart it. Understand the difference between Liveness and Readiness probes.

## Estimated Time

15 minutes.

---

## Step 1: Create the Liveness Pod

Create `liveness-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: liveness-demo
spec:
  containers:
  - name: app
    image: nginx:alpine
    livenessProbe:
      httpGet:
        path: /bad-path
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 5
      failureThreshold: 3
```

Apply it:

```bash
kubectl apply -f liveness-pod.yaml
```

Expected output:

```
pod/liveness-demo created
```

## Step 2: Observe the Crash

Wait about 30 seconds, then run:

```bash
kubectl get pod liveness-demo
```

Expected output: The `RESTARTS` column will increment.

```
NAME            READY   STATUS    RESTARTS   AGE
liveness-demo   1/1     Running   3          45s
```

## Step 3: Investigate the Failure

```bash
kubectl describe pod liveness-demo
```

Scroll to the Events section.

**Your Task:**

What is the exact warning message in the Events?

(Answer: `Warning: Liveness probe failed: HTTP probe failed with statuscode: 404` and `Normal: Killing container with id ... Container liveness probe failed...`)

## Step 4: Explanation

The kubelet makes an `httpGet` request. It expects HTTP status 200-399. Because we pointed to `/bad-path`, Nginx returned a 404. After 3 failures, the kubelet killed the container.

## Step 5: Cleanup

```bash
kubectl delete pod liveness-demo
```

---

## What You Learned

- Liveness Probes check if the app is alive. If they fail, Kubernetes restarts the container.
- Readiness Probes check if the app is ready for traffic. If they fail, the Pod's IP is removed from Service Endpoints.
- Startup Probes are for slow-booting apps. They disable Liveness/Readiness until they pass.
- The kubelet expects HTTP codes 200-399 for a successful probe. A 404 or 500 fails it.

## Next Steps

Proceed to [Lesson 29 - Helm](../docs/09-packaging/lesson-29-helm.md) to learn about packaging Kubernetes applications with Helm.

---

[Back to Labs](README.md)
