---
title: Lab 24 - Building a 3-Tier Web Application
lesson: 24
module: 12 Production
tags: [kubernetes, production, 3-tier, services, coreDNS, configmaps, secrets, debugging]
---

# Lab 24 - Building a 3-Tier Web Application

## Objective

In this lab you will deploy a 3-tier application (Database, Backend API, Frontend Web) and wire them together using Kubernetes Services and CoreDNS. You will then intentionally break the backend to practice DNS troubleshooting.

## Prerequisites

- A running kind cluster
- kubectl installed and configured
- Completion of Lessons 1 through 23

## Pre-Lab Checklist

- [ ] kind cluster running
- [ ] `kubectl get nodes` shows Ready status
- [ ] Understand Services and DNS basics

---

## Step 1: Create the Database Tier

Create the DB tier with Redis and a Secret:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
stringData:
  redis-password: "supersecret123"
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
        image: redis:alpine
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: redis-password
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
EOF
```

Wait for the Redis pod to be ready:

```bash
kubectl wait --for=condition=ready pod -l app=db --timeout=60s
```

## Step 2: Create the Backend Tier

Create the Backend API Deployment and Service:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: busybox:latest
        command: ["sh", "-c", "while true; do echo 'Backend: Checking DB...'; nc -z -w2 redis-db 6379 && echo 'Backend: DB is reachable!' || echo 'Backend: DB unreachable'; sleep 5; done"]
---
apiVersion: v1
kind: Service
metadata:
  name: backend-api
spec:
  selector:
    app: backend
  ports:
  - port: 80
EOF
```

## Step 3: Create the Frontend Tier

Create the Frontend Deployment, ConfigMap, and Service:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: frontend-config
data:
  index.html: |
    <html><body><h1>Welcome to the Frontend!</h1><p>Try connecting to the backend API.</p></body></html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        volumeMounts:
        - name: config-volume
          mountPath: /usr/share/nginx/html
      volumes:
      - name: config-volume
        configMap:
          name: frontend-config
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-web
spec:
  selector:
    app: frontend
  ports:
  - port: 80
EOF
```

## Step 4: Verify the Connections

Check all pods are running:

```bash
kubectl get pods
```

Wait for all pods to reach Running status:

```bash
kubectl wait --for=condition=ready pod -l app=backend --timeout=60s
kubectl wait --for=condition=ready pod -l app=frontend --timeout=60s
```

Check Backend logs to verify it can reach the DB:

```bash
kubectl logs -l app=backend --tail=5
```

You should see "Backend: DB is reachable!".

Now verify the Frontend can talk to the Backend:

```bash
kubectl exec -it deploy/frontend-web -- wget -qO- http://backend-api
```

You will get a Connection refused error. This is expected because the Backend is running netcat, not a web server. The important thing is that DNS routing worked - it found the Backend Pod.

## Step 5: Examine DNS Resolution

Let's look at how CoreDNS resolves the service names.

Check the endpoints for each service:

```bash
kubectl get endpoints redis-db
kubectl get endpoints backend-api
kubectl get endpoints frontend-web
```

Test DNS resolution from inside a pod:

```bash
kubectl exec -it deploy/frontend-web -- nslookup redis-db
kubectl exec -it deploy/frontend-web -- nslookup backend-api
```

Check the `/etc/resolv.conf` to see CoreDNS configuration:

```bash
kubectl exec -it deploy/frontend-web -- cat /etc/resolv.conf
```

## Step 6: Break Things on Purpose

Apply a broken backend with a typo in the DB name:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: busybox:latest
        command: ["sh", "-c", "while true; do echo 'Backend: Checking DB...'; nc -z -w2 redis-database 6379 && echo 'Backend: DB is reachable!' || echo 'Backend: DB unreachable'; sleep 5; done"]
EOF
```

Wait about 15 seconds for the new Pod to start, then check the logs:

```bash
kubectl logs -l app=backend --tail=10
```

**Your Task:**

- What does the Backend log say now? Is the DB reachable or unreachable?
- Inside the Pod, the `nc` command is failing. What cluster component is failing to resolve the name `redis-database`?
- If this were a real production app written in Python or Node.js, what specific error type would the application likely throw when trying to connect to a non-existent database DNS name?

## Step 7: Fix It

Now fix the backend to use the correct DNS name:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: busybox:latest
        command: ["sh", "-c", "while true; do echo 'Backend: Checking DB...'; nc -z -w2 redis-db 6379 && echo 'Backend: DB is reachable!' || echo 'Backend: DB unreachable'; sleep 5; done"]
EOF
```

Wait for the new pod to start:

```bash
kubectl wait --for=condition=ready pod -l app=backend --timeout=60s
```

Verify it's working again:

```bash
kubectl logs -l app=backend --tail=5
```

## Step 8: Expose the Frontend

Port-forward the frontend service to access it locally:

```bash
kubectl port-forward svc/frontend-web 8080:80
```

Open a browser and go to `http://localhost:8080`. You should see the "Welcome to the Frontend!" page.

Press `Ctrl+C` to stop port-forwarding.

## Step 9: Cleanup

```bash
kubectl delete -f frontend-tier.yaml
kubectl delete -f backend-tier.yaml
kubectl delete -f db-tier.yaml
kubectl delete -f broken-backend.yaml
```

Or delete by label:

```bash
kubectl delete deployments --all
kubectl delete services --all
kubectl delete configmaps --all
kubectl delete secrets db-secret
```

---

## Lab Questions

1. Why does the Backend Pod need to use a Service DNS name instead of a Pod IP address?
2. What would happen to the application if the Redis database Pod crashed but the Deployment has `replicas: 1`?
3. If you deploy the Database in namespace `data-tier` and the Backend in namespace `app-tier`, what FQDN would the Backend use to connect to the Database?
4. How could you prevent the Frontend from directly accessing the Database using Network Policies?

---

## Expected Results

After completing this lab:
- You understand how to wire a 3-tier application together
- You can verify DNS resolution using `nslookup`
- You can troubleshoot DNS failures (NXDOMAIN)
- You know when to use Services vs Pod IPs
- You understand the role of CoreDNS in Kubernetes networking

---

## Key Commands Reference

| Command | Purpose |
|---------|---------|
| `kubectl logs -l app=backend --tail=5` | Check backend logs |
| `kubectl exec -it deploy/<name> -- sh` | Open shell in pod |
| `kubectl get endpoints <svc-name>` | Check service endpoints |
| `nslookup <service-name>` | Test DNS resolution |
| `nc -z -w2 <host> <port>` | Test TCP connectivity |
| `kubectl port-forward svc/<name> <local>:<remote>` | Access service locally |

---

## Next

- Return to the [Lesson 24 file](../12-production/lesson-24-building-a-3-tier-web-application.md) to review the concepts
- Try the advanced task: Deploy a StatefulSet database instead of a Deployment for production-grade storage
- Proceed to the next lesson to learn about Autoscaling
