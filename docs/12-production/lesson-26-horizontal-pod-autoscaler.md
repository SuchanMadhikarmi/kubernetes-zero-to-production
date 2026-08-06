---
title: Lesson 26 - Horizontal Pod Autoscaler
module: 12 Production
lesson: 26
status: Complete
tags: [kubernetes, autoscaling, hpa, metrics-server, cpu, production]
---

# Lesson 26 - Horizontal Pod Autoscaler

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

- Explain the difference between scaling Pods (HPA) and scaling Nodes (Cluster Autoscaler).
- Define what the Horizontal Pod Autoscaler (HPA) is and how it uses the Metrics API.
- Configure an HPA to scale a Deployment based on CPU usage.
- Generate load on a Pod and watch Kubernetes automatically scale it up and down.

## Prerequisites

- Completion of Lessons 1 through 25.
- A running kind cluster.
- The Metrics Server must be installed. If you skipped Lesson 18, install it now:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

## Real-world Motivation

### The Viral Spike

Imagine you run an e-commerce site. On a normal Tuesday, 2 Pods handle the traffic perfectly. On Black Friday, traffic increases 50x. If you statically provision 50 Pods, you waste thousands of dollars on Tuesday. If you provision 2 Pods, you crash on Black Friday.

### Why This Exists

To achieve cloud elasticity. The Horizontal Pod Autoscaler (HPA) is a Kubernetes controller. It watches real-time metrics (via the Metrics Server). If your target CPU is 50%, and the current CPU is 100%, the HPA calculates how many more Pods are needed to bring the average down to 50%. It then patches the Deployment's replicas field automatically.

### Real Company Examples

**Pokemon GO (Niantic):** When Pokemon GO launched, millions of players logged in simultaneously. They used HPA on their location services. The HPA detected the CPU spike and scaled the Pods from 50 to 500 in minutes. Behind the scenes, the Cluster Autoscaler saw the Pending Pods and provisioned 20 new Google Compute Engine nodes to hold them. When the event ended, the Pods scaled down, and the nodes were terminated, saving massive cloud costs.

## Core Concepts

### Explain Like I'm 12

Imagine a thermostat in a house. You set the desired temperature to 70F (Target CPU: 50%).

- If the room gets hot (90F), the AC turns on (adds Pods).
- If the room gets cold (50F), the AC turns off (removes Pods).

### Explain Like I'm a Junior Engineer

The HPA checks the Metrics Server every 15 seconds. It looks at your Deployment's CPU usage. If you set the target to 50%, and the Pods are sitting at 100%, HPA does the math: 100 / 50 = 2. It scales the Deployment to 2 replicas. If it's still at 80%, it does 80 / 50 = 1.6 -> 2. It scales to 2.

### Explain Technically

- The `HorizontalPodAutoscaler` object defines a `scaleTargetRef` (e.g., a Deployment), a `minReplicas`, a `maxReplicas`, and a `targetCPUUtilizationPercentage`.
- The HPA controller queries the `metrics.k8s.io` API (Metrics Server).
- It calculates the desired replicas: `desiredReplicas = ceil(currentReplicas * (currentMetric / targetMetric))`.
- It writes the new replica count to the Deployment's `spec.replicas` via the API Server.
- **Cluster Autoscaler:** A separate component that runs as a Deployment. It watches for Pending Pods. It then interacts with the cloud provider's Auto Scaling Groups to add nodes.

### How Kubernetes Implements It Internally

The HPA is a control loop that sits in the kube-controller-manager. It talks to the API Server and the Metrics Server. Every 15 seconds, it queries the metrics.k8s.io API. The Metrics Server returns the current CPU usage for the Pods. HPA calculates the average. If the average is > 50%, it calculates the new replica count. It sends a PATCH request to the API Server to update `Deployment.spec.replicas`. The Deployment controller notices the change and creates the new Pods.

### Why Kubernetes Was Designed That Way

Kubernetes was designed for cloud-native workloads that need to handle variable traffic. HPA provides automatic scaling without manual intervention, enabling true cloud elasticity. The separation between HPA (Pod scaling) and Cluster Autoscaler (Node scaling) allows each to operate independently while working together.

## Architecture

```
[ Metrics Server ] <-- scrapes Kubelet
      |
      v
[ HPA Controller ] (Checks every 15s)
  Target: 50% CPU
  Current: 100% CPU (1 Pod)
      |
      v (Math: ceil(1 * (100/50)) = 2)
[ API Server ]
      |
      v
[ Deployment ] (Replicas patched from 1 to 2)
```

### Terminology

| Term | Definition |
|------|------------|
| HPA | Horizontal Pod Autoscaler. Scales Pods horizontally (adds more). |
| VPA | Vertical Pod Autoscaler. Scales Pods vertically (adds more CPU/RAM to existing Pods). |
| Cluster Autoscaler | Scales the physical nodes in the cluster. |
| minReplicas | The minimum number of Pods HPA will allow. |
| maxReplicas | The maximum number of Pods HPA will allow. |

### How It Works Internally

1. You create an HPA YAML targeting a Deployment. You set `averageUtilization: 50`.
2. The HPA controller runs inside the kube-controller-manager. Every 15 seconds, it queries the `metrics.k8s.io` API.
3. The Metrics Server returns the current CPU usage for the Pods.
4. HPA calculates the average. If the average is > 50%, it calculates the new replica count.
5. It sends a PATCH request to the API Server to update `Deployment.spec.replicas`.
6. The Deployment controller notices the change and creates the new Pods.

### Step-by-Step Workflow

1. Developer deploys an app with `resources.requests.cpu: 200m`.
2. Developer creates an HPA targeting that app, setting `averageUtilization: 50`.
3. Traffic spikes. The app uses 400m CPU (200% of request).
4. HPA calculates: `1 * (200 / 50) = 4`. Scales Deployment to 4.
5. Traffic drops. App uses 50m CPU (25% of request).
6. HPA waits 5 minutes (cool-down), then scales back to 1.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | HPA is created. It starts polling metrics. |
| Scale Up | Triggered when current > target. Happens quickly (within 15s). |
| Scale Down | Triggered when current < target. Happens slowly (5-minute cool-down to prevent thrashing). |
| Deletion | HPA is deleted. The Deployment retains its current replica count. |

### Communication Patterns

| Communication | Mechanism | Example |
|---------------|-----------|---------|
| HPA -> Metrics Server | Queries metrics.k8s.io API | `GET /apis/metrics.k8s.io/v1beta1/pods` |
| HPA -> API Server | PATCH Deployment replicas | `PATCH /apis/apps/v1/namespaces/default/deployments/php-apache` |
| Cluster Autoscaler -> Cloud Provider | Provisions new nodes | AWS Auto Scaling Group API |

### Common Myths

| Myth | Fact |
|------|------|
| "HPA scales Nodes." | False. HPA only scales Pods. The Cluster Autoscaler scales Nodes. |
| "HPA can scale to 0." | False. Standard CPU-based HPA cannot scale from 0 to 1 because a Pod with 0 replicas generates 0 CPU metrics to trigger the scale-up. You need KEDA or a custom metric to scale from 0. |

## ASCII Diagrams

Mental Model: HPA is a thermostat. You set the desired temperature (50% CPU). If the room gets hot (250%), it turns on more AC units (Pods).

```
[ HPA Object ] (Target: 50% CPU, Max: 5 Pods)
      |
      v (Polls Metrics Server)
[ Current CPU: 250% (1 Pod) ]
      |
      v (Math: 1 * (2.5 / 0.5) = 5)
[ Deployment ] (Replicas patched to 5)
```

## Hands-on

### Objective

Deploy an app, install HPA, generate load, and watch it scale automatically.

### Step 1: Verify Metrics Server

```bash
kubectl top nodes
```

If this works, Metrics Server is running.

### Step 2: Deploy the App

We need an app that consumes CPU. We will use a standard Kubernetes demo image.

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

Wait for it to be Running.

### Step 3: Expose the App

```bash
kubectl expose deployment php-apache --port=80
```

### Step 4: Create the HPA

Let's set the thermostat. We want CPU to stay around 50%. We allow it to scale from 1 to 5 replicas.

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

### Step 5: Generate Traffic (The Spike)

We will open a second terminal and run a temporary Pod that continuously sends HTTP requests to our app.

Open a second terminal and run:

```bash
kubectl run -i --tty load-generator --rm --image=busybox:latest -- /bin/sh -c "while true; do wget -q -O- http://php-apache; done"
```

Leave this running. It is hammering the app with requests.

### Step 6: Watch the Autoscaler React

Go back to your first terminal. Wait about 60 seconds, then run:

```bash
kubectl get hpa
kubectl get pods -l run=php-apache
```

**Your Task:**

- Look at `kubectl get hpa`. What is the TARGETS percentage now? (It should jump well over 50%).
- Look at `kubectl get pods -l run=php-apache`. Did the number of Pods increase from 1?
- Go to your second terminal and press `Ctrl+C` to stop the load generator. Wait 3-5 minutes, then check `kubectl get hpa` again. What happened to the CPU percentage and the replica count?

(Answer: 1. Spiked to >100%. 2. Yes, scaled up to 2, 3, 4, or 5. 3. CPU dropped to 0%, and after a 5-minute cooldown, replicas scaled back down to 1).

### Step 7: Cleanup

```bash
# Stop the load generator (Ctrl+C in terminal 2)
kubectl delete hpa php-apache-hpa
kubectl delete deployment php-apache
kubectl delete svc php-apache
```

## Commands

```bash
# Shows current metrics vs target, and current replica count
kubectl get hpa

# Crucial for debugging. Shows Conditions and Events.
kubectl describe hpa <name>

# Verify the Metrics Server is actually sending data
kubectl top pods

# Check deployment resources
kubectl get deployment <name> -o yaml | grep requests
```

## YAML Explanation

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

### Field-by-Field Explanation

- `scaleTargetRef`: Points to the Deployment we want to scale.
- `minReplicas`: The minimum number of Pods HPA will allow.
- `maxReplicas`: The maximum number of Pods HPA will allow.
- `metrics`: We are using a Resource metric (cpu). We want the `averageUtilization` across all Pods to be 50.

## Production Notes

- **Always set `resources.requests.cpu`:** HPA calculates percentages based on the Pod's CPU request. If there is no request, HPA cannot calculate a percentage and shows `<unknown>`.
- **Consider Custom Metrics:** CPU-based scaling is reactive. If a traffic spike hits, CPU spikes first, then HPA scales. For true predictive scaling, use custom metrics (e.g., "Scale when the number of active HTTP requests per second > 100").
- **Don't scale to 0:** Standard CPU-based HPA cannot scale from 0 to 1 (because a Pod with 0 replicas generates 0 CPU metrics). Use KEDA for scale-to-zero.

### When to Use / When NOT to Use

**Use HPA when:**

- Stateless web applications with variable traffic.
- APIs that experience sudden spikes.
- Background job processors with queue-based scaling.

**Avoid HPA when:**

- Databases. They don't scale horizontally well. Use VPA or manually resize.
- Applications that take 5 minutes to boot. By the time HPA scales them, the traffic spike is over.
- Stateful applications that require stable network identities.

### Performance and Security Considerations

**Performance:** HPA scaling is reactive. There is a delay (Metrics Server scrape + HPA calculation + Pod boot time). For massive spikes, you might need to over-provision slightly or use predictive scaling.

**Security:** HPA itself doesn't introduce security risks, but if you use custom metrics (e.g., scaling based on "number of user logins"), ensure the metric provider is secure so an attacker can't fake a metric to force your cluster to scale to max capacity (DoS attack).

## Best Practices

- Always define CPU requests in Pod spec.
- Set reasonable min/max replicas.
- Use custom metrics for predictive scaling.
- Monitor HPA with `kubectl describe hpa`.
- Combine HPA with Cluster Autoscaler for full elasticity.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Deploying HPA without Metrics Server | HPA will show `<unknown>` and do nothing | Verify Metrics Server is running with `kubectl top nodes` |
| Missing CPU Requests | The most common HPA error | Always set `resources.requests.cpu` in Pod spec |
| Setting minReplicas too high | Wastes money at night when traffic is zero | Start with `minReplicas: 1` and adjust based on baseline traffic |
| Confusing HPA with Cluster Autoscaler | HPA adds Pods, Cluster Autoscaler adds Nodes | Understand the separation of concerns |

## Troubleshooting

**Symptom: HPA shows `<unknown>/50%`**

Cause: Metrics Server not running or Pod missing CPU requests.

```bash
kubectl top pods
kubectl get deployment <name> -o yaml | grep requests
```

Fix: Install Metrics Server and add CPU requests to Pod spec.

**Symptom: HPA not scaling during traffic spike**

Cause: CPU requests too high or Metrics Server not scraping correctly.

```bash
kubectl describe hpa <name>
kubectl top pods
```

Fix: Check HPA Conditions section for errors. Verify Metrics Server is returning data.

**Symptom: Pods scaling up and down rapidly**

Cause: Cool-down period too short or metrics fluctuating.

```bash
kubectl describe hpa <name> | grep -A 5 Conditions
```

Fix: Increase the cool-down period or smooth metrics with custom metrics.

## Interview Questions

**Q: What is the difference between HPA and Cluster Autoscaler?**

A: HPA scales Pods horizontally (adds more replicas) based on CPU/Memory metrics. Cluster Autoscaler scales Nodes (adds more physical servers) when Pods are stuck in Pending because the cluster is full.

**Q: Does HPA scale Nodes?**

A: No. HPA only scales Pods. The Cluster Autoscaler scales Nodes.

**Q: If HPA TARGETS shows `<unknown>/50%`, what are the two most likely causes?**

A: 1. The Metrics Server is not running or cannot scrape the Pod. 2. The Pod is missing a `resources.requests.cpu` definition.

**Q: How does HPA calculate the number of replicas needed?**

A: It takes the current CPU utilization as a percentage of the request, divides by the target percentage, and multiplies by the current number of replicas. Formula: `desiredReplicas = ceil(currentReplicas * (currentMetric / targetMetric))`.

**Q: You deployed an HPA, but your application is not scaling up during a traffic spike. How do you debug it?**

A: First, I run `kubectl get hpa` to see if the TARGETS column shows a high CPU percentage. If it shows `<unknown>`, I check if the Metrics Server is running (`kubectl top pods`) and if the Deployment has CPU requests defined. If the target is high but replicas aren't increasing, I run `kubectl describe hpa` to check the Conditions and Events for errors.

**Q: True or False: HPA requires the Metrics Server to function.**

A: True.

**Q: True or False: HPA can scale a Deployment to 0 replicas if there is no traffic.**

A: False. Standard HPA needs `minReplicas: 1` to function.

## Scenario Questions

**Scenario 1:** You have an HPA targeting 50% CPU. During peak hours, Pods scale to 5. During off-hours, they scale to 1. The problem is that the first request during off-hours takes 30 seconds because the Pod needs to warm up. How do you solve this?

A: Set `minReplicas: 2` to ensure at least 2 Pods are always running. This way, one Pod can handle the first request while the other is warming up.

**Scenario 2:** You want to scale based on the number of requests per second, not CPU. How do you do this?

A: Use custom metrics with the Custom Metrics API. You need a metrics adapter (like Prometheus Adapter) that exposes `requests_per_second` as a metric. Then configure HPA to use `type: Pods` with the custom metric.

**Scenario 3 (Mini Project - The Memory Scaler):**

Deploy an app that leaks memory (e.g., a script that allocates arrays in a loop). Create an HPA that scales based on Memory utilization (target 50%). Watch the Pods scale up as memory usage climbs.

## Quiz

1. What does HPA stand for?
   - A. High Performance Autoscaler
   - B. Horizontal Pod Autoscaler
   - C. Horizontal Protocol Allocator
   - D. High Priority Autoscaler

2. What is the default cool-down period for HPA scale-down?
   - A. 30 seconds
   - B. 1 minute
   - C. 5 minutes
   - D. 15 minutes

3. What happens if a Pod doesn't have `resources.requests.cpu`?
   - A. HPA scales it to 0
   - B. HPA shows `<unknown>` and cannot calculate percentages
   - C. HPA ignores it
   - D. HPA sets a default request

4. Which component scales Nodes?
   - A. HPA
   - B. VPA
   - C. Cluster Autoscaler
   - D. kube-scheduler

5. Can HPA scale from 0 to 1?
   - A. Yes, always
   - B. No, standard HPA needs minReplicas: 1
   - C. Only with custom metrics
   - D. Only with VPA

Answers: 1-B, 2-C, 3-B, 4-C, 5-B.

## Revision

One-minute revision:

- HPA = Scales Pods.
- Cluster Autoscaler = Scales Nodes.
- Needs Metrics Server.
- Needs CPU requests.
- Cooldown = 5 mins for scale-down.
- Formula: `desiredReplicas = ceil(current * (current% / target%))`.

Memory trick:

- **HPA:** A thermostat. Set to 50%. If room gets hot (250%), turn on more ACs (Pods).
- **Cluster Autoscaler:** The construction crew. If there is no room in the house for the new ACs, they build a new wing (Node).

Key facts:

- HPA scales Pods, not Nodes.
- HPA needs Metrics Server.
- HPA needs CPU requests.
- HPA cooldown is 5 minutes.
- HPA cannot scale to 0.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl get hpa` | Shows current metrics vs target, and current replica count |
| `kubectl describe hpa <name>` | Crucial for debugging. Shows Conditions and Events. |
| `kubectl top pods` | Verify the Metrics Server is actually sending data |
| `kubectl get deployment <name> -o yaml \| grep requests` | Check if Pod has CPU requests |

## References

- [Kubernetes Documentation: Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Kubernetes Documentation: Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [Kubernetes Documentation: Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
- [KEDA Documentation](https://keda.sh/)

## Related Lessons

- [Lesson 07 - Worker Node Architecture](../02-architecture/lesson-07-worker-node-architecture.md) - basic scheduling.
- [Lesson 25 - Node Affinity and Pod Anti-Affinity](../02-architecture/lesson-25-node-affinity-and-anti-affinity.md) - advanced scheduling.
- [Lesson 24 - Building a 3-Tier Web Application](lesson-24-building-a-3-tier-web-application.md) - applying HPA to real applications.

## Coming Next

Now that you understand how to automatically scale Pods based on traffic, the next lesson covers High Availability and Multi-Zone Deployments — how to protect your application from entire datacenter outages.
