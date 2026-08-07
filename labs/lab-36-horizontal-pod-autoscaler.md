---
title: Lab 36 - Horizontal Pod Autoscaler
lesson: 36
module: 12 Production
tags: [kubernetes, autoscaling, hpa, metrics-server, cpu]
---

# Lab 36 - Horizontal Pod Autoscaler

## Objective

In this lab you will deploy an application, configure a Horizontal Pod Autoscaler (HPA), generate traffic load, and watch Kubernetes automatically scale Pods up and down based on CPU usage.

## Prerequisites

- A running kind cluster
- kubectl installed and configured
- Metrics Server installed
- Completion of Lessons 1 through 25

## Pre-Lab Checklist

- [ ] kind cluster running
- [ ] Metrics Server installed (`kubectl top nodes` works)
- [ ] Understand HPA basics from Lesson 36

---

## Step 1: Verify Metrics Server

```bash
kubectl top nodes
```

If this works, Metrics Server is running. If not, install it:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

Wait 30 seconds and try again.

## Step 2: Deploy the App

Create `hpa-app.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-apache
spec:
  replicas: 1
  selector:
    matchLabels:
      run: php-apache
  template:
    metadata:
      labels:
        run: php-apache
    spec:
      containers:
      - name: php-apache
        image: registry.k8s.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 200m
          limits:
            cpu: 500m
```

Apply it:

```bash
kubectl apply -f hpa-app.yaml
```

Wait for it to be Running:

```bash
kubectl wait --for=condition=ready pod -l run=php-apache --timeout=60s
```

## Step 3: Expose the App

```bash
kubectl expose deployment php-apache --port=80
```

## Step 4: Create the HPA

Create `hpa.yaml`:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php-apache
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```

Apply it:

```bash
kubectl apply -f hpa.yaml
```

Check the HPA status:

```bash
kubectl get hpa
```

You should see `TARGETS: 0%/50%` or similar. 0% because there is no traffic right now.

## Step 5: Generate Traffic (The Spike)

Open a second terminal and run:

```bash
kubectl run -i --tty load-generator --rm --image=busybox:latest -- /bin/sh -c "while true; do wget -q -O- http://php-apache; done"
```

Leave this running. It is hammering the app with requests.

## Step 6: Watch the Autoscaler React

Go back to your first terminal. Wait about 60 seconds, then run:

```bash
kubectl get hpa
kubectl get pods -l run=php-apache
```

**Your Task:**

- Look at `kubectl get hpa`. What is the TARGETS percentage now? (It should jump well over 50%).
- Look at `kubectl get pods -l run=php-apache`. Did the number of Pods increase from 1?

## Step 7: Watch Scale Down

Go to your second terminal and press `Ctrl+C` to stop the load generator.

Wait 3-5 minutes, then check:

```bash
kubectl get hpa
kubectl get pods -l run=php-apache
```

**Your Task:**

- What happened to the CPU percentage?
- What happened to the replica count after the cool-down period?

## Step 8: Check HPA Details

```bash
kubectl describe hpa php-apache-hpa
```

Look at the Events section to see the scaling actions.

## Step 9: Cleanup

```bash
kubectl delete hpa php-apache-hpa
kubectl delete deployment php-apache
kubectl delete svc php-apache
```

---

## Lab Questions

1. Why does HPA need `resources.requests.cpu` to be defined?
2. What is the formula HPA uses to calculate the desired number of replicas?
3. Why is there a 5-minute cool-down period for scale-down?
4. How would you scale based on memory usage instead of CPU?
5. What happens if you set `minReplicas: 0` with standard CPU-based HPA?

---

## Expected Results

After completing this lab:
- You can deploy an HPA targeting a Deployment
- You understand how HPA reacts to CPU load
- You know the difference between scale-up and scale-down behavior
- You can debug HPA issues with `kubectl describe hpa`

---

## Key Commands Reference

| Command | Purpose |
|---------|---------|
| `kubectl get hpa` | Show current metrics vs target |
| `kubectl describe hpa <name>` | Debug HPA issues |
| `kubectl top pods` | Verify Metrics Server is working |
| `kubectl get pods -o wide` | See pod scaling in action |

---

## Next

- Return to the [Lesson 36 file](../docs/12-production/lesson-36-horizontal-pod-autoscaler.md) to review the concepts
- Try the advanced task: Configure HPA with memory-based scaling
- Proceed to the next lesson to learn about High Availability and Multi-Zone Deployments
