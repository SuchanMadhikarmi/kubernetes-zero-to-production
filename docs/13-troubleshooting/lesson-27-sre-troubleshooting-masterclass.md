---
title: Lesson 27 - The SRE Troubleshooting Masterclass
module: 13 Troubleshooting
lesson: 27
status: Complete
tags: [kubernetes, troubleshooting, sre, debugging, crashloopbackoff, imagepullbackoff]
---

# Lesson 27 - The SRE Troubleshooting Masterclass

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

- Apply the 5-step methodology Senior SREs use to debug any Kubernetes incident.
- Read `kubectl describe` output to find root causes.
- Systematically isolate and fix overlapping, compounding failures.
- Trace a failed deployment from the API Server down to the container process.

## Prerequisites

- Completion of Lessons 1 through 26.
- A running kind cluster.
- kubectl installed and configured.

## Real-world Motivation

### The 3 AM PagerDuty Alert

You are the On-Call engineer. An alert fires: "Production Web App Down." You log in, run `kubectl get pods`, and see a mess of Pending, CrashLoopBackOff, and ImagePullBackOff statuses. Junior engineers panic and start randomly changing YAML files or restarting nodes. Senior SREs remain calm, follow a strict methodology, and let the system tell them exactly what is broken via Events and Logs.

### Why This Exists

Kubernetes is a complex distributed system. If it failed silently, it would be impossible to operate. To prevent this, Kubernetes is radically transparent. Every time a controller (Scheduler, Kubelet) performs an action on a Pod, it records an Event. The secret to SRE troubleshooting is knowing how to read these events and understand the Pod lifecycle to know where the failure occurred (Scheduling, Pulling, Starting, or Running).

### Real Company Examples

**Google:** An SRE gets paged at 3 AM for a failing service. They don't read the source code. They run `kubectl describe` and `kubectl logs`. They see `Liveness probe failed: connection refused`. They immediately know the app is starting but the internal web server thread is dead. They roll back the deployment. The whole incident takes 5 minutes because they followed the telemetry, not their gut.

## Core Concepts

### Explain Like I'm 12

Imagine a car won't start. You don't immediately replace the engine. You follow a checklist: Is there gas? Is the battery dead? Are the spark plugs connected? You test one thing at a time until you find the broken link.

### Explain Like I'm a Junior Engineer

When an app fails in Kubernetes, it rarely fails silently. The control plane records every error in the Pod's Events log. The secret is knowing how to read those events and understand the Pod lifecycle to know where the failure occurred.

### Explain Technically

The SRE 5-Step Troubleshooting Method:

1. **Assess the State:** `kubectl get pods`. What is the STATUS? (Pending, CrashLoopBackOff, ImagePullBackOff, OOMKilled).
2. **Read the Events:** `kubectl describe pod <name>`. Scroll to the bottom Events section. The Scheduler, Kubelet, and Runtime log their failures here.
3. **Read the Logs:** `kubectl logs <name>`. If the Pod is running but crashing, the application code is throwing an error.
4. **Check Dependencies:** `kubectl get svc`, `kubectl get endpoints`, `kubectl get configmap`. Does the Pod have the config and network routes it needs?
5. **Check Permissions:** `kubectl auth can-i`. Can the Pod actually talk to the API server or read the Secrets it's asking for?

### How Kubernetes Implements It Internally

Every time a controller (Scheduler, Kubelet) performs an action on a Pod, it sends an Event to the API Server. Events are stored in etcd for 1 hour by default. The `kubectl describe` command aggregates the Pod spec, status, and recent events into a single human-readable view.

### Why Kubernetes Was Designed That Way

Kubernetes was designed for observability. Every action is recorded as an Event, every container's output is captured in logs, and every resource has a status. This radical transparency makes debugging possible in a distributed system where you can't just SSH into a machine and check a process.

## Architecture

```
[ 1. Assess State ] (`kubectl get pods`) -> What is the STATUS?
      |
      v
[ 2. Read Events ] (`kubectl describe pod`) -> What did the Scheduler/Kubelet say?
      |
      v
[ 3. Read Logs ] (`kubectl logs`) -> What did the application code say?
      |
      v
[ 4. Check Dependencies ] (`kubectl get svc`, `kubectl get endpoints`) -> Is the network routing correct?
      |
      v
[ 5. Check Permissions ] (`kubectl auth can-i`) -> Is RBAC blocking the app from reading a ConfigMap?
```

### Terminology

| Term | Definition |
|------|------------|
| Events | Kubernetes objects that record what happens to a resource (e.g., scheduling, pulling, starting). |
| Pending | Pod state indicating it has been accepted but cannot be scheduled. |
| ContainerCreating | Pod state indicating the Kubelet is pulling images and mounting volumes. |
| CrashLoopBackOff | Pod state indicating the container started, crashed, and is repeatedly restarting. |
| ImagePullBackOff | Pod state indicating the Container Runtime couldn't fetch the image. |
| OOMKilled | Pod state indicating the container was killed because it exceeded its memory limit. |

### How It Works Internally

1. You send a YAML to the API Server.
2. API Server saves it to etcd.
3. Scheduler assigns it to a Node. (If this fails, Event: `FailedScheduling`).
4. Kubelet on that Node receives the Pod.
5. Kubelet asks the Container Runtime to pull the image. (If this fails, Event: `Failed to pull image`).
6. Kubelet mounts volumes. (If this fails, Event: `MountVolume.SetUp failed`).
7. Kubelet asks the Runtime to start the container. (If config is missing, Event: `CreateContainerConfigError`).
8. Container starts. If it exits, Kubelet restarts it (Status: `CrashLoopBackOff`).

### Step-by-Step Workflow

1. Pager goes off. User reports 502 errors.
2. SRE runs `kubectl get pods -n prod`. Sees `CrashLoopBackOff`.
3. SRE runs `kubectl describe pod <name> -n prod`. Checks Events. Sees `OOMKilled`.
4. SRE knows the app is using too much RAM. SRE checks `kubectl logs <name> -n prod` for memory leak traces.
5. SRE either increases the Memory Limit or rolls back the code.

### Lifecycle

| Phase | Description |
|-------|-------------|
| Detection | Alert fires or user reports. |
| Investigation | Run the 5-step methodology. |
| Mitigation | Roll back the deployment or scale up resources to stop the bleeding. |
| Root Cause Analysis (RCA) | Figure out exactly why it broke after the fire is put out. |
| Post-Mortem | Document the incident and implement safeguards so it never happens again. |

### Communication Patterns

| Symptom | Where to Look | Likely Cause |
|---------|---------------|--------------|
| Pending | `kubectl describe pod` (Events) | FailedScheduling: Not enough CPU/RAM, Taints, Affinity |
| ImagePullBackOff | `kubectl describe pod` (Events) | Bad image name/tag, missing imagePullSecrets |
| ContainerCreating (stuck) | `kubectl describe pod` (Events) | Volume mount failure, missing Secret/ConfigMap |
| CreateContainerConfigError | `kubectl describe pod` (Events) | Missing environment variable key in ConfigMap/Secret |
| CrashLoopBackOff | `kubectl logs <pod> --previous` | App code crashed (exit 1), OOMKilled, bad config |

### Common Myths

| Myth | Fact |
|------|------|
| "If a Pod is CrashLoopBackOff, Kubernetes is broken." | False. CrashLoopBackOff means Kubernetes is doing its job. Your app crashed, and Kubernetes is trying to restart it to keep it alive. |
| "Deleting the Pod will fix the issue." | If it's a transient issue, deleting the Pod forces rescheduling and might fix it. But if it's a bad image or a bad config, the ReplicaSet will just recreate the exact same broken Pod. |

## ASCII Diagrams

Mental Model: The troubleshooting funnel. Start wide, go narrow.

```
[ kubectl get pods ] -> STATUS is bad?
      |
      v
[ kubectl describe pod ] -> EVENTS tell the story
      |
      +---> (Scheduling) "0/3 nodes available" -> Fix Affinity/Resources
      +---> (Pulling) "Failed to pull image" -> Fix Image tag
      +---> (Mounting) "CreateContainerConfigError" -> Fix ConfigMap/Secret
      +---> (Probes) "Liveness probe failed" -> Fix App endpoint
      |
      v
[ kubectl logs ] -> App is crashing? -> Read the stack trace
```

## Hands-on

### Objective

Deploy a multi-tier application with multiple, overlapping, compounding failures. Use the SRE methodology to find and fix them one by one.

### Step 1: Deploy the Broken App

Create `broken-app.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-config
data:
  DB_HOST: "redis-db"
---
apiVersion: v1
kind: Secret
metadata:
  name: db-pass
type: Opaque
stringData:
  password: "mysecretpassword"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: redis
        image: redis:7.0-alpine-broken-tag  # FAILURE 1: Bad Image Tag
---
apiVersion: v1
kind: Service
metadata:
  name: redis-db
spec:
  selector:
    app: db
  ports:
  - port: 6379
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
spec:
  replicas: 1
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
        image: busybox:latest
        command: ["sh", "-c", "while true; do echo 'Pinging DB...'; nc -z -w2 $DB_HOST 6379 && echo 'DB is UP!' || (echo 'DB is DOWN!' && exit 1); sleep 5; done"]
        env:
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: web-config
              key: DB_HOST_MISSING  # FAILURE 2: Missing ConfigMap Key
```

Apply it:

```bash
kubectl apply -f broken-app.yaml
```

### Step 2: Start the Investigation (Phase 1)

Wait about 10 seconds, then run:

```bash
kubectl get pods
```

You will see a mess. Let's start with the database since the frontend depends on it.

Run:

```bash
kubectl describe pod -l app=db
```

Scroll to the Events section.

**Your Task (Phase 1):**

- What is the STATUS of the `redis-db` pod?
- What is the exact error message in the Events section at the bottom of `kubectl describe`?
- What is the root cause of this specific failure? How do we fix it?

(Answer: 1. `ImagePullBackOff`. 2. `Failed to pull image "redis:7.0-alpine-broken-tag": rpc error: code = NotFound`. 3. The image tag `7.0-alpine-broken-tag` does not exist in Docker Hub. We must change it to `redis:7.0-alpine`).

### Step 3: Apply the Fixes

Open your `broken-app.yaml` file in your text editor and make these two changes:

1. Under the `redis-db` Deployment, change the image to a valid tag:
   `image: redis:7.0-alpine`
2. Under the `web-frontend` Deployment, change the configMap key to match the actual key:
   `key: DB_HOST`

Save the file, then apply the changes:

```bash
kubectl apply -f broken-app.yaml
```

Because Deployments are mutable for these fields, applying the new YAML will trigger Kubernetes to kill the broken pods and start new, fixed ones.

### Step 4: Verify the Recovery

Wait about 15 seconds, then run:

```bash
kubectl get pods
```

**Your Task:**

- What is the STATUS of the `redis-db` pod now?
- What is the STATUS of the `web-frontend` pod now?
- Run `kubectl logs -l app=web --tail=5`. What is the web frontend printing to the logs?

(Answer: 1. Running. 2. Running. 3. "DB is UP!". The frontend successfully resolved the DB Service DNS name and connected to port 6379).

### Step 5: Cleanup

```bash
kubectl delete -f broken-app.yaml
```

## Commands

```bash
# Step 1: Assess the state
kubectl get pods

# Step 2: Read the Events
kubectl describe pod <name>

# Step 3: Read the logs of the crashed container
kubectl logs <pod> --previous

# Step 4: Check if the Service routes to the Pods
kubectl get endpoints <svc>

# Step 5: Check permissions
kubectl auth can-i <verb> <resource>

# Additional debugging commands
kubectl get events --sort-by='.lastTimestamp'
kubectl logs <pod> -c <container>  # for multi-container pods
kubectl exec -it <pod> -- /bin/sh  # shell into a running pod
```

## YAML Explanation

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: redis
        image: redis:7.0-alpine-broken-tag  # FAILURE 1: Bad Image Tag
```

### Field-by-Field Explanation

- `image: redis:7.0-alpine-broken-tag`: This tag doesn't exist in Docker Hub, causing `ImagePullBackOff`.
- `configMapKeyRef.name`: References the ConfigMap name.
- `configMapKeyRef.key`: References the key within the ConfigMap. If this key doesn't exist, you get `CreateContainerConfigError`.

## Production Notes

- **Change one variable at a time:** If you change the image tag, the CPU limit, and the ConfigMap all at once, you won't know which fix actually worked (or which change caused the next bug).
- **Don't delete the evidence:** If a Pod is crashing, don't immediately delete it. Read its logs and events first. Deleting it destroys the forensic evidence.
- **Use `--previous`:** If a Pod is in CrashLoopBackOff, `kubectl logs <pod>` might be empty because the new container just started. Always run `kubectl logs <pod> --previous` to read the logs of the container that actually crashed.

### When to Use / When NOT to Use

**Use this methodology when:**

- Always. Whether it's a production outage or a local dev issue, follow the funnel. Do not guess.

**When the methodology won't work:**

- If the cluster control plane itself is down (e.g., etcd is full, or the API Server is crashed), `kubectl get` won't work. In that case, you must SSH into the nodes and read the Kubelet systemd logs (`journalctl -u kubelet`).

### Performance and Security Considerations

**Performance:** Troubleshooting via `kubectl logs` can be slow in massive clusters. Use centralized logging (Loki/ELK) to search across 1,000 Pods instantly.

**Security:** Ensure developers have `kubectl describe` and `kubectl logs` permissions. If they can't see the Events, they can't debug their own apps, leading to severe bottlenecks for the SRE team.

## Best Practices

- Follow the 5-step methodology every time.
- Change one variable at a time.
- Don't delete the evidence (crashed Pods).
- Use `--previous` to get crash logs.
- Read Events before guessing.
- Keep calm and let the system tell you what's wrong.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Panicking and deleting the Deployment | Stress and urgency | Follow the methodology, read Events first |
| Changing multiple YAML fields at once | Trying to fix everything fast | Change one thing at a time, verify, then move on |
| Ignoring Events | Staring at `kubectl get pods` waiting for it to fix itself | The fix is always in the Events or Logs |
| Not using `--previous` | Assuming current logs have the error | Always check previous container logs for crashes |

## Troubleshooting

**Symptom: Pod stuck in `ImagePullBackOff`**

Cause: Bad image name or tag, or missing `imagePullSecrets`.

```bash
kubectl describe pod <name> | grep -A 5 Events
```

Fix: Verify the image exists on Docker Hub. Check for typos in the image name.

**Symptom: Pod stuck in `CreateContainerConfigError`**

Cause: Missing ConfigMap or Secret key.

```bash
kubectl get configmap <name> -o yaml
kubectl get secret <name> -o yaml
```

Fix: Ensure all keys referenced in the Pod spec exist in the ConfigMap/Secret.

**Symptom: Pod in `CrashLoopBackOff` with empty logs**

Cause: Container crashed immediately after starting.

```bash
kubectl logs <pod> --previous
```

Fix: The previous container's logs will have the actual error.

**Symptom: Pod in `Pending` forever**

Cause: Scheduler can't find a valid node.

```bash
kubectl describe pod <name> | grep -A 5 Events
```

Look for `FailedScheduling` events. Fix taints, affinity, or resource requests.

## Interview Questions

**Q: Walk me through how you troubleshoot a Pod in CrashLoopBackOff.**

A: First, I run `kubectl describe pod` to check the Events and confirm the exit code (e.g., Exit Code 137 for OOMKilled). If it's Exit Code 1, I know the application crashed. I then run `kubectl logs <pod> --previous` to read the stack trace of the crashed container before it restarted. Based on the error, I fix the configuration or roll back the image.

**Q: What is the first command you run when investigating a failing Pod?**

A: `kubectl get pods` to see the status, followed immediately by `kubectl describe pod <name>` to read the Events at the bottom.

**Q: What does a `CreateContainerConfigError` usually indicate?**

A: The Pod is referencing a key in a ConfigMap or Secret that does not exist. The Kubelet refuses to start the container because the environment variable is mandatory.

**Q: You deploy an application, but it keeps crashing. `kubectl logs <pod>` shows the application starting up fine, but then it exits. How do you find the actual error?**

A: I use the `--previous` flag. `kubectl logs <pod>` shows the current container's logs. Since it just restarted, those logs are fresh and don't contain the crash. `kubectl logs <pod> --previous` reads the logs of the crashed container instance before it was restarted, which will contain the actual stack trace or error.

**Q: True or False: If a Pod is stuck in ContainerCreating for 5 minutes, it's normal.**

A: False. It usually means a volume mount failed or a CSI driver is stuck.

**Q: True or False: Deleting a namespace deletes all resources inside it instantly.**

A: True, which is why it's dangerous.

## Scenario Questions

**Scenario 1:** Users report 502 errors. You check the Pods and they are all Running and Ready. What happened?

A: Check the Ingress configuration, verify Endpoints exist for the Service, and check if the app is listening on the correct port. The Service selector might not match Pod labels, or Pods might be failing Readiness Probes.

**Scenario 2:** You deploy an app and it shows `ImagePullBackOff`. You verify the image exists on Docker Hub. What else could be wrong?

A: Check if there's a typo in the image name. Check if the image is in a private registry and needs `imagePullSecrets`. Check if the node has network access to Docker Hub.

**Scenario 3 (Mini Project - The Bug Maker):**

Create a Deployment YAML for an Nginx web server. Introduce 3 different errors (e.g., wrong port in the Service, missing ConfigMap key, typo in the image tag). Give the YAML to a colleague (or test yourself). Use the 5-step methodology to find and fix all 3 errors without looking at the original file.

## Quiz

1. What is the first step in the SRE troubleshooting methodology?
   - A. Read the logs
   - B. Check permissions
   - C. Assess the state with `kubectl get pods`
   - D. Restart the Pod

2. What does `ImagePullBackOff` mean?
   - A. The app crashed
   - B. The Container Runtime couldn't fetch the image
   - C. The Scheduler couldn't find a node
   - D. The Pod exceeded its memory limit

3. What command reads the logs of a crashed container?
   - A. `kubectl logs <pod>`
   - B. `kubectl logs <pod> --previous`
   - C. `kubectl describe pod <pod>`
   - D. `kubectl exec <pod>`

4. What does `CreateContainerConfigError` indicate?
   - A. Bad image tag
   - B. Missing ConfigMap/Secret key
   - C. Not enough CPU
   - D. Taints preventing scheduling

5. What is the correct order of the troubleshooting funnel?
   - A. Logs -> Events -> Get Pods
   - B. Get Pods -> Describe -> Logs
   - C. Describe -> Get Pods -> Logs
   - D. Logs -> Get Pods -> Events

Answers: 1-C, 2-B, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- 5 Steps: Get -> Describe -> Logs -> Dependencies -> RBAC.
- Pending = Scheduler.
- ImagePullBackOff = Runtime.
- ContainerCreating = Kubelet (Mounts/Secrets).
- CrashLoopBackOff = App code.
- Use `--previous` for crash logs.

Memory trick:

- **The Troubleshooting Funnel:** Start wide at the cluster level (get pods), narrow down to the node (describe pod), narrow down to the container (logs), and finally narrow down to the code (stack trace).
- **Events are the security cameras:** If a crime happens (pod crashes), review the security camera footage (Events) before guessing who did it.

Key facts:

- Always follow the 5-step methodology.
- Read Events before guessing.
- Use `--previous` for crash logs.
- Change one thing at a time.
- Don't delete the evidence.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl get pods` | Step 1: Assess the state. |
| `kubectl describe pod <name>` | Step 2: Read the Events. |
| `kubectl logs <pod> --previous` | Step 3: Read the logs of the crashed container. |
| `kubectl get endpoints <svc>` | Step 4: Check if the Service routes to the Pods. |
| `kubectl auth can-i <verb> <resource>` | Step 5: Check RBAC permissions. |
| `kubectl get events --sort-by='.lastTimestamp'` | View all events in chronological order. |

## References

- [Kubernetes Documentation: Troubleshooting Clusters](https://kubernetes.io/docs/tasks/debug/debug-cluster/)
- [Kubernetes Documentation: Application Troubleshooting](https://kubernetes.io/docs/tasks/debug/debug-application/)
- [Google SRE Book](https://sre.google/sre-book/table-of-contents/)

## Related Lessons

- [Lesson 30 - Monitoring and Metrics](../08-observability/lesson-30-monitoring-and-metrics.md) - setting up observability before incidents happen.
- [Lesson 31 - Logging](../08-observability/lesson-31-logging.md) - centralized logging for faster debugging.
- [Lesson 32 - Probes and Health Checks](../08-observability/lesson-32-probes-and-health-checks.md) - preventing CrashLoopBackOff with proper probes.

## Coming Next

Now that you know how to troubleshoot failing workloads, the next lesson covers how to debug networking and cluster-level issues — DNS failures, Service routing problems, and control plane health.
