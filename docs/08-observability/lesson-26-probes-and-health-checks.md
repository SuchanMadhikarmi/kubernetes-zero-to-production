---
title: Lesson 26 - Probes and Health Checks
module: 08 Observability
lesson: 26
status: Complete
tags: [kubernetes, observability, probes, liveness, readiness, startup, health-checks, kubelet]
---

# Lesson 32 - Probes and Health Checks

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

- Explain the difference between a process being "Running" and an application being "Ready".
- Describe what Liveness Probes are (when to restart).
- Describe what Readiness Probes are (when to route traffic).
- Describe what Startup Probes are (for slow-booting apps).
- Configure probes and debug a failing application.

## Prerequisites

- Completion of Lessons 1 through 13.
- A running kind cluster.
- kubectl installed and configured.

## Real-world Motivation

### The Silent Deadlock

Imagine you deploy a Java Spring Boot application. The JVM process is running perfectly (PID 1 is alive). However, a bug in the code causes the internal HTTP thread pool to deadlock. The application can no longer process HTTP requests. Because the container process is still running, Kubernetes thinks everything is fine. Users send traffic to the Pod, but they get 504 Gateway Timeouts. The Pod never restarts because Kubernetes doesn't know the app is broken.

### The Premature Traffic

You deploy a database that needs 60 seconds to load a massive index into RAM. Kubernetes sees the container start and instantly routes user traffic to it. Users get "Connection Refused" errors for 60 seconds until the database finishes booting.

### Why This Exists

Kubernetes cannot see inside your code. It needed a standardized way for the platform to ask the application, "Are you okay?" without guessing. Probes allow the application to expose an endpoint that reports its own internal health, allowing Kubernetes to make smart decisions about restarting containers and routing traffic.

### Real Company Examples

**Netflix:** Netflix uses a dedicated `/health` endpoint for Readiness that checks if the internal thread pools are exhausted. If thread pools hit 100%, the Readiness probe fails, Netflix's load balancer stops sending traffic to that Pod, but the Pod is not restarted. It is given time to drain and process existing requests.

## Core Concepts

### Explain Like I'm 12

Imagine a lifeguard at a pool.

- **Liveness:** The lifeguard throws a ball at you every 10 seconds. If you catch it and throw it back, you are "Alive". If you miss it 3 times in a row, the lifeguard thinks you are drowning, pulls you out of the water, and throws a new, fresh kid into the pool (Restart).
- **Readiness:** The lifeguard checks if you have your swimming goggles on. If you don't, they put a rope across your lane. No one can swim in your lane (No traffic). Once you put your goggles on, they remove the rope (Traffic resumes).
- **Startup:** For the first 5 minutes you are in the pool, the lifeguard ignores you, letting you stretch and get ready, before they start throwing the ball (Liveness checks).

### Explain Like I'm a Junior Engineer

- **Liveness Probe:** "Is my app hung?" If it fails, Kubernetes kills the container and restarts it.
- **Readiness Probe:** "Is my app ready to handle users?" If it fails, Kubernetes removes the Pod's IP from the Service's Endpoints. The Pod stays running, but no traffic is sent to it.
- **Startup Probe:** "Is my app still booting up?" Disables Liveness and Readiness checks until it passes once.

### Explain Technically

The kubelet has a ProbeManager. It runs goroutines for each configured probe.

- For `httpGet`, it uses Go's HTTP client to hit the Pod's IP and path.
- For `exec`, it uses the CRI (Container Runtime Interface) to exec into the container.
- The results are updated on the Pod's `.status.containerStatuses` and `.status.conditions` (e.g., `Ready=False`).
- The EndpointController (in the control plane) watches the Pod's Ready condition. If False, it removes the Pod IP from the Endpoints object.

### How Kubernetes Implements It Internally

The kubelet starts the container. It waits for `initialDelaySeconds` (e.g., 5s). It begins hitting the `httpGet` path every `periodSeconds` (e.g., 5s). If the app returns 200, the probe passes. If the app returns 500, the probe fails. The `failureThreshold` counter increments. If the counter reaches 3, the kubelet sends a SIGTERM to the container process (Liveness) or updates the Pod status to `Ready=False` (Readiness).

### Why Kubernetes Was Designed That Way

Kubernetes separates "process running" from "application healthy". A container process can be alive but the application inside it can be broken. Probes give Kubernetes a way to ask the application about its internal state without needing to understand the application's code.

## Architecture

```
[ Kubelet (on Node) ]
      |
      +---> 1. Liveness Probe: "Are you alive?" -> If fail, KILL & RESTART container.
      |
      +---> 2. Readiness Probe: "Are you ready for users?" -> If fail, REMOVE from Service Endpoints.
      |
      +---> 3. Startup Probe: "Are you still booting?" -> If pass, Liveness/Readiness take over.
```

### Terminology

| Term | Definition |
|------|------------|
| Liveness Probe | A diagnostic that indicates the container needs to be restarted. |
| Readiness Probe | A diagnostic that indicates the container is ready to service requests. |
| Startup Probe | A diagnostic that indicates the container has started successfully. |
| initialDelaySeconds | Time to wait after the container starts before probing. |
| periodSeconds | How often to perform the probe. |
| failureThreshold | How many consecutive failures trigger an action. |

### How It Works Internally

1. The kubelet starts the container.
2. It waits for `initialDelaySeconds` (e.g., 5s).
3. It begins hitting the `httpGet` path every `periodSeconds` (e.g., 5s).
4. If the app returns 200, the probe passes.
5. If the app returns 500, the probe fails. The `failureThreshold` counter increments.
6. If the counter reaches 3, the kubelet sends a SIGTERM to the container process (Liveness) or updates the Pod status to `Ready=False` (Readiness).

### Step-by-Step Workflow

1. Developer writes a `/health` endpoint in their app.
2. Developer creates a Deployment YAML with a Liveness probe hitting `/health`.
3. `kubectl apply` sends it to the API Server.
4. Scheduler places the Pod on a Node.
5. Kubelet starts the container.
6. Kubelet waits 5 seconds, then hits `http://<pod-ip>:8080/health`.
7. If the app is frozen and times out, Kubelet retries 3 times.
8. Kubelet kills the container and creates a new one.

### Lifecycle

| State | Description |
|-------|-------------|
| Container Starts | Probes are initialized. |
| Startup Phase | (If configured) Startup probe runs. Liveness/Readiness are paused. |
| Running Phase | Liveness and Readiness probes run on their intervals. |
| Failure | Liveness failure -> restart. Readiness failure -> removed from Service. |
| Container Dies | Probes stop. |

### Probe Types Comparison

| Probe Type | Action on Failure | Use Case |
|------------|-------------------|----------|
| Liveness | Restart Container | App is deadlocked/frozen. |
| Readiness | Remove from Service Endpoints | App is booting, or dependencies are down. |
| Startup | Restart Container (if fails) | App takes >30s to boot. Disables Liveness/Readiness. |

### Probe Methods Comparison

| Probe Method | How it works | Success Condition |
|--------------|--------------|-------------------|
| httpGet | HTTP GET request to IP:Port/Path | Status code 200-399 |
| tcpSocket | TCP handshake to IP:Port | Port is open |
| exec | Runs command inside container | Exit code 0 |

### Common Myths

| Myth | Fact |
|------|------|
| "If my Liveness probe fails, Kubernetes moves my Pod to another node." | False. Kubernetes restarts the container on the same node. It does not reschedule the Pod unless the node itself dies. |
| "Readiness probes restart unhealthy Pods." | False. Readiness probes only control traffic routing (Endpoints). They never restart the container. |

## ASCII Diagrams

Mental Model:

- **Liveness:** "Restart me if I'm broken."
- **Readiness:** "Don't send me users if I'm busy/loading."
- **Startup:** "Give me a minute to wake up before checking on me."

```
[ Pod: api-server ]
  Containers:
  - Liveness: HTTP GET /healthz (Port 8080)
  - Readiness: HTTP GET /readyz (Port 8080)

      |
      v (kubelet checks every 10s)

[ App returns 500 on /healthz ]
      |
      v (After 3 failures)
[ Kubelet kills container ] -> [ Restarted ]
```

## Hands-on

### Objective

Deploy an app with a Liveness probe pointing to a bad path. Watch Kubernetes kill and restart it.

### Step 1: Create the Liveness Pod

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

**Field Explanation:**

- `livenessProbe`: Configures the liveness check.
- `httpGet`: The method to use.
- `path: /bad-path`: The endpoint to hit. Nginx will return 404.
- `initialDelaySeconds: 5`: Wait 5s before starting checks.
- `periodSeconds: 5`: Check every 5s.
- `failureThreshold: 3`: Fail 3 times before killing.

### Step 2: Deploy the Pod

```bash
kubectl apply -f liveness-pod.yaml
```

Expected output:

```
pod/liveness-demo created
```

### Step 3: Observe the Crash

Wait about 30 seconds, then run:

```bash
kubectl get pod liveness-demo
```

Expected output: The `RESTARTS` column will increment.

```
NAME            READY   STATUS    RESTARTS   AGE
liveness-demo   1/1     Running   3          45s
```

### Step 4: Investigate the Failure

```bash
kubectl describe pod liveness-demo
```

Scroll to the Events section.

**Your Task:**

What is the exact warning message in the Events?

(Answer: `Warning: Liveness probe failed: HTTP probe failed with statuscode: 404` and `Normal: Killing container with id ... Container liveness probe failed...`)

### Step 5: Explanation

The kubelet makes an `httpGet` request. It expects HTTP status 200-399. Because we pointed to `/bad-path`, Nginx returned a 404. After 3 failures, the kubelet killed the container.

### Step 6: Cleanup

```bash
kubectl delete pod liveness-demo
```

## Commands

```bash
# Look for Liveness probe failures in Events
kubectl describe pod <name>

# Check RESTARTS column for Liveness failures
kubectl get pod <name>

# If empty, Readiness probe might be failing
kubectl get endpoints <svc>

# Check probe configuration
kubectl get pod <name> -o yaml | grep -A 10 livenessProbe
kubectl get pod <name> -o yaml | grep -A 10 readinessProbe
```

## YAML Explanation

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

### Field-by-Field Explanation

- `livenessProbe`: The probe configuration for liveness checks.
- `httpGet`: Performs an HTTP GET request to check health.
- `path`: The HTTP endpoint to hit.
- `port`: The port to connect to.
- `initialDelaySeconds`: Time to wait after container starts before first probe.
- `periodSeconds`: How often to perform the probe.
- `failureThreshold`: How many consecutive failures before taking action.

## Production Notes

- **Don't use Liveness for dependencies:** If your app's Liveness probe checks if the database is up, and the database goes down, Kubernetes will restart your app. Restarting the app won't fix the database. Liveness should only check if the app itself is unrecoverable.
- **Use different endpoints:** Don't use `/` for both Liveness and Readiness. Use `/healthz` for Liveness (is the process alive?) and `/readyz` for Readiness (are dependencies connected and am I ready to serve?).
- **Set initialDelaySeconds carefully:** If your Java app takes 30s to boot, and you set the delay to 5s, Kubernetes will kill it before it finishes booting. Use a Startup Probe instead to avoid guessing the delay.

### When to Use / When NOT to Use

**Use Probes when:**

- Running web servers (always use Readiness Probes).
- App is prone to deadlocks (use Liveness Probes).
- Java/legacy apps that take >10s to boot (use Startup Probes).

**Avoid Liveness Probes when:**

- For simple scripts or CronJobs.
- If your app doesn't handle SIGTERM gracefully, restarting it abruptly might corrupt data.

### Performance and Security Considerations

**Performance:** If you set `periodSeconds: 1`, the kubelet generates constant HTTP traffic to your app. This can skew your metrics or add CPU overhead. Stick to 5-10 seconds.

**Security:** Do not expose sensitive data on your `/healthz` endpoint. It should just return 200 OK. Also, ensure the endpoint doesn't require authentication, or the kubelet's probe will fail.

## Best Practices

- Always use Readiness Probes for web servers.
- Use Liveness Probes if your app is prone to deadlocks.
- Use Startup Probes for Java/legacy apps that take >10s to boot.
- Don't use the same endpoint for Liveness and Readiness.
- Set `initialDelaySeconds` based on your app's actual boot time.
- Monitor probe failures with `kubectl describe pod`.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| No Readiness Probe | Kubernetes assumes Pod is ready instantly | Always add Readiness Probes for web servers |
| Probing the wrong port | Probe hits port 80, but app listens on 8080 | Verify the port matches your application |
| Liveness too aggressive | `periodSeconds: 2` and `failureThreshold: 1` | Use reasonable intervals (5-10s) and thresholds (3) |
| Using same endpoint for both | Liveness and Readiness check different things | Use `/healthz` for Liveness, `/readyz` for Readiness |

## Troubleshooting

**Symptom: Pod in CrashLoopBackOff**

Cause: Liveness probe failing before app finishes booting.

```bash
kubectl describe pod <name> | grep -A 5 Events
```

Fix: Increase `initialDelaySeconds` or add a Startup Probe.

**Symptom: Pod Running but no traffic routed**

Cause: Readiness probe failing.

```bash
kubectl get endpoints <svc>
```

Fix: Check Readiness probe configuration and ensure the endpoint returns 200.

**Symptom: Liveness probe failed: connection refused**

Cause: Probe hitting wrong port or app not listening.

```bash
kubectl get pod <name> -o yaml | grep -A 10 livenessProbe
```

Fix: Verify the port matches your application's listening port.

## Interview Questions

**Q: What is the difference between Liveness and Readiness?**

A: Liveness determines if a container should be restarted. Readiness determines if traffic should be routed to the Pod.

**Q: If a Readiness probe fails, does the Pod restart?**

A: No. The Pod stays running, but its IP is removed from the Service Endpoints, so it receives no traffic.

**Q: Why would you use a Startup Probe?**

A: For applications that take a long time to initialize, like Java. Without a Startup probe, I would have to set a high `initialDelaySeconds` for the Liveness probe, which delays detecting actual crashes. A Startup probe allows the app to take as long as it needs to boot, and only then does the Liveness probe take over.

**Q: You deployed a new version of your app. It keeps crashing on startup with CrashLoopBackOff. The logs show the app is fine, but the `kubectl describe` shows `Liveness probe failed: connection refused`. Why?**

A: The app is taking longer to boot than the `initialDelaySeconds` configured for the Liveness probe. The kubelet is probing the port before the app has opened it. I should either increase the delay or, better, implement a Startup Probe.

**Q: Should you use the same endpoint for Liveness and Readiness?**

A: No. Readiness should check dependencies (database, message queue), while Liveness should only check if the app process itself is alive. If the database is down, you don't want Kubernetes to restart the app — you want it to stop sending traffic until the database recovers.

## Scenario Questions

**Scenario 1:** Your Java application takes 45 seconds to start. How do you configure probes?

A: I would use a Startup Probe with a long `failureThreshold` (e.g., 60) and `periodSeconds: 1`. This gives the app 60 seconds to boot. Once the Startup Probe passes, Liveness and Readiness probes take over.

**Scenario 2:** Your app is deadlocked and not responding to HTTP requests. What happens?

A: The Liveness probe will fail. After `failureThreshold` consecutive failures, the kubelet kills the container and restarts it. The app should recover from the deadlock after restart.

**Scenario 3 (Mini Project - The Traffic Controller):**

Deploy an Nginx Pod with a Readiness Probe on path `/` port 80. Wait for it to be Running and Ready (1/1). Exec into the pod and delete the index.html file (`rm /usr/share/nginx/html/index.html`). Watch `kubectl get pods`. The Pod should stay Running (1/1), but the READY column should eventually change to 0/1 because Nginx returns 403 Forbidden when the index file is missing.

## Quiz

1. What does a Liveness Probe do when it fails?
   - A. Removes Pod from Service
   - B. Restarts the container
   - C. Scales down the Deployment
   - D. Sends an alert

2. What is the success condition for an httpGet probe?
   - A. Status code 200
   - B. Status code 200-399
   - C. Status code 200-299
   - D. Any status code

3. What happens when a Readiness Probe fails?
   - A. Pod is restarted
   - B. Pod is deleted
   - C. Pod IP is removed from Service Endpoints
   - D. Pod is rescheduled to another node

4. When should you use a Startup Probe?
   - A. For simple scripts
   - B. For apps that take >10s to boot
   - C. For CronJobs
   - D. For all applications

5. What is the recommended interval for probes?
   - A. 1 second
   - B. 5-10 seconds
   - C. 30 seconds
   - D. 60 seconds

Answers: 1-B, 2-B, 3-C, 4-B, 5-B.

## Revision

One-minute revision:

- Liveness = Restart me.
- Readiness = Stop my traffic.
- Startup = Wait for me.
- 200-399 = Pass. 404/500 = Fail.

Memory trick:

- **Liveness:** The doctor checking your pulse. If it stops, they use the defibrillator (restart).
- **Readiness:** The bouncer opening the velvet rope. If you aren't ready, the rope stays closed (no traffic).

Key facts:

- Liveness = Restart.
- Readiness = Route traffic.
- Startup = Delay other probes.
- 200-399 = Pass.
- 404/500 = Fail.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl describe pod <name>` | Look for Liveness probe failed in Events |
| `kubectl get pod <name>` | Check RESTARTS column for Liveness failures |
| `kubectl get endpoints <svc>` | If empty, Readiness probe might be failing |

## References

- [Kubernetes Documentation: Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Kubernetes Documentation: Probe Handlers](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#probe-v1-core)
- [Kubernetes Documentation: Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)

## Related Lessons

- [Lesson 6 - Pods, ReplicaSets, and Deployments](../03-workloads/lesson-06-pods-replicasets-and-deployments.md) - how Pods work.
- [Lesson 21 - Resource Management and the OOMKiller (Requests vs Limits)](../06-configuration/lesson-21-resource-requests-limits-and-quotas.md) - resource limits.
- [Lesson 11 - RBAC and Service Accounts](../07-security/lesson-22-rbac-and-service-accounts.md) - API Server security.

## Coming Next

Now that you understand how to monitor application health, the next module covers Packaging — how to manage Kubernetes applications with Helm and Kustomize.
