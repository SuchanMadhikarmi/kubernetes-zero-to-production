---
title: Lab 27 - The SRE Troubleshooting Masterclass
lesson: 27
module: 13 Troubleshooting
tags: [kubernetes, troubleshooting, sre, debugging, crashloopbackoff]
---

# Lab 27 - The SRE Troubleshooting Masterclass

## Objective

In this lab you will deploy a multi-tier application with multiple, overlapping, compounding failures. You will use the SRE 5-step methodology to find and fix each issue systematically.

## Prerequisites

- A running kind cluster
- kubectl installed and configured
- Completion of Lessons 1 through 26

## Pre-Lab Checklist

- [ ] kind cluster running
- [ ] `kubectl get nodes` shows Ready status
- [ ] Understand the 5-step troubleshooting methodology

---

## Step 1: Deploy the Broken App

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

## Step 2: Start the Investigation (Phase 1)

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

## Step 3: Investigate the Frontend (Phase 2)

Now check the frontend:

```bash
kubectl describe pod -l app=web
```

**Your Task (Phase 2):**

- What is the STATUS of the `web-frontend` pod?
- What error message do you see in the Events?
- What is the root cause?

## Step 4: Apply the Fixes

Open your `broken-app.yaml` file and make these two changes:

1. Under the `redis-db` Deployment, change the image to a valid tag:
   `image: redis:7.0-alpine`
2. Under the `web-frontend` Deployment, change the configMap key to match the actual key:
   `key: DB_HOST`

Save the file, then apply the changes:

```bash
kubectl apply -f broken-app.yaml
```

## Step 5: Verify the Recovery

Wait about 15 seconds, then run:

```bash
kubectl get pods
```

**Your Task:**

- What is the STATUS of the `redis-db` pod now?
- What is the STATUS of the `web-frontend` pod now?
- Run `kubectl logs -l app=web --tail=5`. What is the web frontend printing to the logs?

## Step 6: Add a Third Failure (Advanced)

Now let's add a third failure. Create `broken-app-advanced.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            memory: 64Mi  # FAILURE 3: Memory limit too low
---
apiVersion: v1
kind: Service
metadata:
  name: api-server
spec:
  selector:
    app: api
  ports:
  - port: 80
```

Apply it:

```bash
kubectl apply -f broken-app-advanced.yaml
```

Wait 30 seconds, then check:

```bash
kubectl get pods -l app=api
kubectl describe pod -l app=api
```

**Your Task:**

- What is the STATUS of the `api-server` pod?
- What does the Events section say?
- What is the exit code?
- How do you fix this?

## Step 7: Fix the Third Failure

Increase the memory limit:

```bash
kubectl patch deployment api-server -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","resources":{"limits":{"memory":"128Mi"}}}]}}}}'
```

Wait 15 seconds, then verify:

```bash
kubectl get pods -l app=api
```

## Step 8: Cleanup

```bash
kubectl delete -f broken-app.yaml
kubectl delete -f broken-app-advanced.yaml
```

---

## Lab Questions

1. What are the three types of failures you encountered in this lab?
2. For each failure, which step of the 5-step methodology helped you find the root cause?
3. Why is it important to use `kubectl logs <pod> --previous` when a Pod is in CrashLoopBackOff?
4. What would happen if you deleted the broken Pod instead of fixing the YAML first?

---

## Expected Results

After completing this lab:
- You can apply the 5-step troubleshooting methodology
- You can identify ImagePullBackOff, CreateContainerConfigError, and OOMKilled
- You know how to read Events to find root causes
- You understand the importance of not deleting evidence

---

## Key Commands Reference

| Command | Purpose |
|---------|---------|
| `kubectl get pods` | Step 1: Assess the state |
| `kubectl describe pod <name>` | Step 2: Read the Events |
| `kubectl logs <pod> --previous` | Step 3: Read crash logs |
| `kubectl get endpoints <svc>` | Step 4: Check Service routing |
| `kubectl auth can-i <verb> <resource>` | Step 5: Check RBAC |

---

## Next

- Return to the [Lesson 27 file](../13-troubleshooting/lesson-27-sre-troubleshooting-masterclass.md) to review the concepts
- Try the Mini Project: Create your own broken YAML with 3 errors and fix them
- Proceed to the next lesson to learn about networking and cluster-level troubleshooting
