---
title: Lesson 21 - Resource Management and the OOMKiller (Requests vs Limits)
module: 06 Configuration
lesson: 21
status: Complete
tags: [kubernetes, resources, requests, limits, oomkilled, qos, cgroups, cpu, memory]
---

# Lesson 25 - Resource Management and the OOMKiller (Requests vs Limits)

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

- Explain the critical difference between CPU/Memory Requests and Limits.
- Describe how the Kubernetes Scheduler uses Requests to place Pods.
- Explain how the Linux Kernel uses Limits to enforce cgroups.
- Distinguish between the three Quality of Service (QoS) classes (Guaranteed, Burstable, BestEffort).
- Trigger and debug an OOMKilled container.

## Prerequisites

- Completion of Lessons 1 through 7.
- A running Kubernetes cluster (see [Lesson 01](../01-fundamentals/lesson-01-anatomy-of-a-container.md) for kind setup instructions).
- kubectl installed and configured.

## Real-world Motivation

### The Noisy Neighbor

Imagine you run 5 applications on a single node. One of them is a Java app with a memory leak. Because you didn't set any resource limits, the Java app slowly consumes 100% of the server's 16GB of RAM. The Linux kernel panics. The node crashes. All 5 applications go offline instantly, even the healthy ones.

### The Starving App

You run a high-traffic API and a background analytics job on the same node. The analytics job hogs all the CPU. Your API becomes unresponsive, and users experience extreme latency.

### Why This Exists

Kubernetes needed a way to guarantee fair resource sharing and protect the physical node from runaway applications.

- **Requests** ensure your critical applications get the CPU/RAM they need to function (used for scheduling).
- **Limits** ensure an application can never use more than a specific amount, protecting the node from OOMKilled crashes or CPU starvation.

### Real Company Examples

**Target (Retail):** During Black Friday, Target's inventory service sees massive traffic spikes. They set strict Memory Limits to prevent a memory leak from crashing the node, but they intentionally left CPU Limits unset on their API gateway so it could burst and handle the sudden influx of HTTP requests without being throttled by the kernel.

## Core Concepts

### Explain Like I'm 12

Imagine a buffet.

- **Request:** You call ahead and say, "I weigh 100 lbs, please reserve a chair that can hold 100 lbs for me." The restaurant (Scheduler) uses this to make sure they don't overbook the tables.
- **Limit:** When you actually sit down, the restaurant puts a lock on your plate. You can eat up to 150 lbs of food. If you try to eat more, the waiter takes your plate away and kicks you out (OOMKilled).

### Explain Like I'm a Junior Engineer

- **Requests** are what the Pod is guaranteed to get. The Kubernetes Scheduler uses this number for capacity planning.
- **Limits** are the maximum the Pod is allowed to use. If it goes over, bad things happen.
  - CPU limits cause throttling (the app is forced to slow down).
  - Memory limits cause OOMKilled (the app is killed instantly by the kernel).

### Explain Technically

When the kubelet starts a Pod, it reads the `resources` block.

- For **Requests**, it configures Linux cgroups `cpu.shares` and `memory.soft_limit_in_bytes`. The scheduler uses these numbers for capacity planning.
- For **Limits**, it configures cgroups `cpu.cfs_quota_us` (hard CPU cap) and `memory.limit_in_bytes` (hard memory cap). If a process exceeds `memory.limit_in_bytes`, the Linux kernel invokes the OOM Killer and sends a SIGKILL (Signal 9) to terminate the process.

### How Kubernetes Implements It Internally

Kubernetes assigns a QoS class to every Pod based on its requests/limits. If a node runs out of memory and the kubelet needs to evict Pods to save the node, it kills BestEffort Pods first. If it still needs more memory, it kills Burstable Pods. Guaranteed Pods are protected last.

### Why Kubernetes Was Designed That Way

By separating Requests (scheduling) from Limits (enforcement), Kubernetes allows you to overcommit resources safely. You can schedule more Pods than the node can physically run, relying on the fact that most apps don't use their full request. Limits prevent any single app from taking down the node.

## Architecture

```
[ Pod Spec (resources: requests/limits) ]
      |
      +---> [ Scheduler ] (Uses requests to find a node with enough free space)
      |
      +---> [ Kubelet ] (Reads limits and configures Linux cgroups)
                |
                v
      [ Linux Kernel (cgroups) ]
                |
                +---> CPU Throttling (If CPU > limit, app slows down)
                +---> OOMKiller (If Memory > limit, app is shot instantly)
```

### Terminology

| Term | Definition |
|------|------------|
| Requests | The guaranteed minimum amount of CPU/Memory for a container. |
| Limits | The maximum amount of CPU/Memory a container can use. |
| millicores (m) | The unit for CPU. 1000m = 1 CPU core. |
| OOMKilled | Out of Memory Killed. The Linux kernel's defense mechanism against runaway processes. |
| QoS Class | Quality of Service. A ranking system (Guaranteed, Burstable, BestEffort) used during node memory pressure. |
| CFS | Completely Fair Scheduler. The Linux kernel component that enforces CPU limits. |

### How It Works Internally

1. You apply a Pod YAML with `limits.memory: "100Mi"`.
2. API Server saves it to etcd.
3. Scheduler sees the requests (let's say 50Mi). It finds a node with enough free RAM.
4. Kubelet on that node starts the container.
5. Kubelet tells the container runtime (containerd) to create a cgroup with `memory.limit_in_bytes` set to 100 Mebibytes.
6. The app runs. It tries to allocate 150Mi of RAM.
7. The Linux kernel checks the cgroup, sees it's over the 100Mi limit.
8. The OOM Killer sends SIGKILL to the process. Exit code is 137 (128 + 9).
9. Kubelet notices the container died and restarts it.

### Step-by-Step Workflow

1. Developer writes a Pod spec with CPU/Memory requests and limits.
2. `kubectl apply` sends it to the API Server.
3. API Server validates (e.g., rejects if Limit < Request).
4. Scheduler uses requests to find a node.
5. Kubelet uses limits to configure the OS cgroups.
6. Container runs within its bounded environment.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | Resources are reserved. cgroups are applied. |
| Running | App consumes resources. If it hits CPU limit, it is throttled (waits). If it hits Memory limit, it is killed. |
| Deletion | cgroups are destroyed, resources returned to the node pool. |

### Resource Behavior Comparison

| Resource | Request (Guarantee) | Limit (Maximum) | What happens if exceeded? |
|----------|---------------------|-----------------|---------------------------|
| CPU | Used by Scheduler | Enforced by cgroups | Throttling (App slows down, waits for next cycle) |
| Memory | Used by Scheduler | Enforced by cgroups | OOMKilled (App is terminated instantly, Exit Code 137) |

### QoS Classes

| QoS Class | Condition | Priority during Node Pressure |
|-----------|-----------|-------------------------------|
| Guaranteed | Request == Limit (CPU and RAM) | Last to be killed |
| Burstable | Has Request, Limit is higher | Medium priority |
| BestEffort | No Requests, No Limits | First to be killed |

### Common Myths

| Myth | Fact |
|------|------|
| "If I set a CPU limit, my app will run faster." | False. A CPU limit is a hard ceiling. It can only slow your app down (throttle it). It can never make it run faster. |
| "OOMKilled means the node ran out of memory." | False. OOMKilled means the container exceeded its own cgroup limit. If the node runs out of memory, the kubelet initiates an Eviction. |
| "Setting Memory Limit lower than Memory Request is allowed." | False. The API Server rejects this immediately. |

## ASCII Diagrams

Mental Model:

- Request: Your reservation (Scheduler cares about this).
- Limit: Your hard ceiling (Linux Kernel cares about this).
- CPU: If you hit the ceiling, you are forced to walk slower (Throttle).
- Memory: If you hit the ceiling, you are shot on sight (OOMKilled).

```
[ Pod Spec ]
  resources:
    requests:
      cpu: 100m      <-- Scheduler: "Node must have 0.1 CPU free"
      memory: 128Mi  <-- Scheduler: "Node must have 128MB free"
    limits:
      cpu: 200m      <-- Kernel: "If you use >0.2 CPU, I throttle you"
      memory: 256Mi  <-- Kernel: "If you use >256MB RAM, I kill you (OOMKilled)"
```

### CPU Throttling Flow

```
[ App wants to use 300m CPU ]
      |
      v
[ cgroup cpu.cfs_quota_us = 200m ]
      |
      v
[ Linux CFS Scheduler ]
      | (App exceeds quota)
      v
[ App is paused for remainder of CFS period (100ms) ]
      |
      v
[ App resumes after quota resets ]
```

### OOMKiller Flow

```
[ App tries to allocate 256MB RAM ]
      |
      v
[ cgroup memory.limit_in_bytes = 100MB ]
      |
      v
[ Linux Kernel checks cgroup ]
      | (256MB > 100MB limit)
      v
[ OOM Killer sends SIGKILL to process ]
      |
      v
[ Exit Code 137 (128 + 9) ]
      |
      v
[ Kubelet restarts container ]
```

## Hands-on

### Objective

Deploy a Pod with a strict memory limit, and intentionally run a program that tries to eat more memory than allowed. Watch it get OOMKilled.

### Step 1: Create the Pod

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: memory-hog
spec:
  containers:
  - name: app
    image: polinux/stress
    resources:
      requests:
        memory: "50Mi"
      limits:
        memory: "100Mi"
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "250M", "--vm-hang", "1"]
EOF
```

### Step 2: Observe the Crash

```bash
kubectl get pod memory-hog --watch
```

Expected: The Pod cycles through `Running`, `OOMKilled`, and `CrashLoopBackOff`.

### Step 3: Debug

```bash
kubectl describe pod memory-hog
```

Look at the `Last State` section:

```
Last State: Terminated
  Reason: OOMKilled
  Exit Code: 137
```

### Step 4: Test CPU Throttling

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cpu-hog
spec:
  containers:
  - name: app
    image: polinux/stress
    resources:
      requests:
        cpu: "100m"
      limits:
        cpu: "200m"
    command: ["stress"]
    args: ["--cpu", "2"]
EOF
```

```bash
kubectl top pod cpu-hog
```

The Pod uses 200m CPU (its limit) even though it's trying to use more.

### Step 5: Check QoS Class

```bash
kubectl get pod memory-hog -o jsonpath='{.status.qosClass}'
kubectl get pod cpu-hog -o jsonpath='{.status.qosClass}'
```

Both show `Burstable` because requests != limits.

### Step 6: Test Guaranteed QoS

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: guaranteed-app
spec:
  containers:
  - name: app
    image: nginx:1.25-alpine
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "100m"
        memory: "128Mi"
EOF
```

```bash
kubectl get pod guaranteed-app -o jsonpath='{.status.qosClass}'
```

Shows `Guaranteed` because requests == limits.

### Step 7: Cleanup

```bash
kubectl delete pod memory-hog cpu-hog guaranteed-app
```

## Commands

```bash
# Check Pod resource usage (requires Metrics Server)
kubectl top pods
kubectl top nodes

# Check QoS class
kubectl get pod <name> -o jsonpath='{.status.qosClass}'

# Check resource limits in Pod spec
kubectl get pod <name> -o yaml | grep -A 10 resources

# Describe Pod for OOMKilled events
kubectl describe pod <name> | grep -A 5 "Last State"

# Check node capacity
kubectl describe node <node> | grep -A 10 "Allocated resources"
```

## YAML Explanation

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: memory-hog
spec:
  containers:
  - name: app
    image: polinux/stress
    resources:
      requests:
        memory: "50Mi"
        cpu: "100m"
      limits:
        memory: "100Mi"
        cpu: "200m"
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "250M", "--vm-hang", "1"]
```

### Field-by-Field Explanation

- `resources.requests.memory: "50Mi"`: The Scheduler ensures the node has at least 50MB free.
- `resources.requests.cpu: "100m"`: The Scheduler ensures the node has at least 0.1 CPU cores free.
- `resources.limits.memory: "100Mi"`: The kubelet configures the cgroup to kill the process if it exceeds 100MB.
- `resources.limits.cpu: "200m"`: The kernel throttles the process if it tries to use more than 0.2 CPU cores.
- `args`: The stress tool tries to allocate 250MB of RAM. It will fail immediately because the limit is 100MB.

## Production Notes

- **Always set Memory Requests and Limits.** Memory leaks will crash nodes if unbounded.
- **Consider NOT setting CPU Limits.** If you set a CPU limit too low on a latency-sensitive API (like Node.js or Go), the Linux CFS will strictly throttle it, causing high response times even when the node is sitting at 10% CPU. Set CPU Requests, but leave Limits unset to allow bursting.
- **Use Guaranteed QoS for critical apps.** Set Request == Limit. This tells Kubernetes, "Never kill this Pod during node pressure unless absolutely necessary."
- **Monitor OOMKilled events.** A Pod that keeps getting OOMKilled has a memory leak or needs more memory allocated.
- **Set ResourceQuotas at the namespace level** to prevent teams from consuming all cluster resources.

### When to Use / When NOT to Use

**Always set Limits when:**

- Running memory-intensive applications (databases, caches).
- Running batch jobs or background workers where latency doesn't matter.
- You need to protect the node from runaway processes.

**Consider NOT setting CPU Limits when:**

- Running latency-sensitive web APIs (Node.js, Go, Java). CPU limits cause CFS throttling, which adds artificial latency to request processing.

### Performance and Security Considerations

**Performance:** Misconfigured CPU limits are the #1 cause of mysterious latency spikes in Kubernetes. The Linux CFS quota will strictly freeze a thread if it hits its limit, even for 1 millisecond.

**Security:** Without limits, a malicious or compromised container could perform a Denial of Service (DoS) attack against the node by allocating infinite memory.

## Best Practices

- Always set Memory Requests and Limits.
- Set CPU Requests for scheduling; consider leaving CPU Limits unset for latency-sensitive apps.
- Use Guaranteed QoS (Request == Limit) for critical applications.
- Monitor OOMKilled events and adjust limits accordingly.
- Use ResourceQuotas and LimitRanges at the namespace level.
- Profile your application's actual resource usage before setting limits.
- Use Vertical Pod Autoscaler (VPA) to right-size requests and limits.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Setting Memory Limit lower than Memory Request | Misunderstanding the relationship | API Server rejects this; always set Limit >= Request |
| Setting CPU limits too low | Trying to prevent CPU starvation | Measure actual usage; leave CPU Limits unset for latency-sensitive apps |
| Running without Limits | Fear of throttling | Always set Memory Limits; consider CPU Limits based on workload |
| Not monitoring OOMKilled | Assuming limits are set and forget | Set up alerts on OOMKilled events |

## Troubleshooting

**Symptom: Pod in CrashLoopBackOff with Exit Code 137**

Cause: Container exceeded its memory limit and was OOMKilled.

```bash
kubectl describe pod <name> | grep -A 5 "Last State"
```

Fix: Increase the memory limit or fix the memory leak in the application.

**Symptom: High latency despite low CPU usage**

Cause: CPU limit is causing CFS throttling.

```bash
kubectl top pod <name>
kubectl describe pod <name> | grep -A 10 resources
```

Fix: Remove or increase the CPU limit. Set CPU Requests instead.

**Symptom: Pod evicted by kubelet**

Cause: Node is under memory pressure. Kubelet evicts pods based on QoS class.

```bash
kubectl describe node <node> | grep -A 5 "Conditions"
kubectl get events | grep Evicted
```

Fix: Add more nodes, reduce Pod memory requests, or delete unnecessary Pods.

## Interview Questions

**Q: What is the difference between CPU Requests and CPU Limits?**

A: Requests are what the Pod is guaranteed (used by the Scheduler for placement). Limits are the hard maximum enforced by the kernel (via cgroups).

**Q: What happens when a container exceeds its Memory Limit?**

A: The Linux OOM Killer terminates the process (OOMKilled, Exit Code 137).

**Q: A Pod is in CrashLoopBackOff with Exit Code 137. What does that mean and how do you fix it?**

A: Exit code 137 means it was killed by a SIGKILL, usually because it hit its memory limit and was OOMKilled. I would check the Pod's resource limits. If the app legitimately needs more memory, I would increase the limit. If it's a memory leak, I need to debug the application code.

**Q: You have a Java application that takes 30 seconds to boot. You set a CPU limit of 100m. It keeps crashing on startup. Why?**

A: 100m (1/10th of a CPU) is likely too low for Java to boot quickly. The Linux CFS scheduler is throttling the CPU, causing Java to take so long that it hits a startup timeout or fails to initialize. I would remove the CPU limit or raise it to at least 500m during startup.

**Q: What is the difference between Guaranteed, Burstable, and BestEffort QoS?**

A: Guaranteed has Request == Limit for both CPU and Memory (highest priority). Burstable has requests but limits are higher (medium priority). BestEffort has no requests or limits (lowest priority, first to be killed during node pressure).

**Q: Why might you choose NOT to set CPU Limits?**

A: For latency-sensitive applications, CPU limits cause CFS throttling which adds artificial latency. Setting CPU Requests without Limits allows the app to burst when needed.

## Scenario Questions

**Scenario 1:** You have a Pod that keeps getting OOMKilled. The application team insists it only needs 256MB of memory. What do you check?

A: First, verify the actual memory usage with `kubectl top pod`. If it's consistently using more than 256MB, the app has a memory leak or needs more memory allocated. If it spikes briefly, increase the limit or investigate what causes the spike.

**Scenario 2:** Your API Pods are experiencing random latency spikes every few seconds, even though CPU usage is low. What's the likely cause?

A: CPU limits are causing CFS throttling. The app hits its CPU quota for the period, gets paused for the remainder, then resumes. This creates periodic latency spikes. Remove or increase the CPU limit.

**Scenario 3 (Mini Project - The QoS Check):**

Deploy a Pod with no requests or limits. Deploy a second Pod where Requests == Limits. Run `kubectl get pod <name> -o yaml` on both and find the `qosClass` field. Verify the first is BestEffort and the second is Guaranteed.

## Quiz

1. What happens when a container exceeds its Memory Limit?
   - A. CPU throttling
   - B. OOMKilled (Exit Code 137)
   - C. Pod is evicted
   - D. Nothing

2. Which QoS class is killed first during node memory pressure?
   - A. Guaranteed
   - B. Burstable
   - C. BestEffort
   - D. They are killed equally

3. What does `100m` mean in CPU requests?
   - A. 100 megabytes
   - B. 100 milliseconds
   - C. 100 millicores (0.1 CPU cores)
   - D. 100 million operations

4. Why might you choose NOT to set CPU Limits?
   - A. To save resources
   - B. To prevent CFS throttling on latency-sensitive apps
   - C. Because Kubernetes doesn't support it
   - D. To allow BestEffort QoS

5. What is the relationship between Requests and Limits?
   - A. Requests must be greater than Limits
   - B. Limits must be greater than or equal to Requests
   - C. They must be equal
   - D. They are independent

Answers: 1-B, 2-C, 3-C, 4-B, 5-B.

## Revision

One-minute revision:

- Requests = Scheduler. Limits = cgroups (Kernel).
- CPU exceeded = Throttle. Memory exceeded = OOMKilled (137).
- QoS: Guaranteed (Req=Lim), Burstable (Req<Lim), BestEffort (None).
- Always set Memory Limits. Consider leaving CPU Limits unset for latency-sensitive apps.

Memory trick:

- CPU Limit: A speed limiter on a car. You can't go faster, but the car stays running.
- Memory Limit: A landmine on a tightrope. Step over the line, and you explode (OOMKilled).
- QoS Guaranteed: First-class passenger. Last to get kicked off an overbooked flight.

Key facts:

- Exit Code 137 = OOMKilled (128 + 9 = SIGKILL).
- CPU Limits cause throttling. Memory Limits cause death.
- BestEffort Pods die first. Guaranteed Pods die last.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl describe pod <name>` | Look for OOMKilled and Exit Code 137 under Last State |
| `kubectl get pod <name> -o yaml` | Check qosClass under status |
| `kubectl top pods` | See real-time CPU/Memory usage (requires Metrics Server) |
| `kubectl get pod <name> -o jsonpath='{.status.qosClass}'` | Check QoS class |

## References

- [Kubernetes Documentation: Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Kubernetes Documentation: Pod Quality of Service Classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)
- [Kubernetes Documentation: Node-pressure Eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/)
- [Linux man page: cgroups(7)](https://man7.org/linux/man-pages/man7/cgroups.7.html)
- [The Dangers of CPU Limits](https://dnastacio.medium.com/the-dangers-of-cpu-limits-4989a27b464e)

## Related Lessons

- [Lesson 1 - The Anatomy of a Container](../01-fundamentals/lesson-01-anatomy-of-a-container.md) - containers, namespaces, and cgroups.
- [Lesson 3 - Controlling Where Pods Run (Scheduling and Taints)](../02-architecture/lesson-03-worker-node-architecture.md) - how the scheduler places Pods.
- [Lesson 19 - ConfigMaps and Secrets](lesson-20-configmaps-and-secrets.md) - injecting configuration into Pods.
- [Module 12 - Production](../12-production/README.md) - production hardening and capacity planning.

## Coming Next

Now that you understand resource management and the OOMKiller, the next lessons cover security topics: RBAC, ServiceAccounts, and Pod Security Standards.
