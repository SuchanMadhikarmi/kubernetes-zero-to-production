---
title: Lesson 01 - The Anatomy of a Container
module: 01 Fundamentals
lesson: 1
status: Complete
tags: [kubernetes, containers, namespaces, cgroups, linux, docker]
---

# Lesson 01 - The Anatomy of a Container (Namespaces and cgroups)

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

- Explain what a container actually is at the Linux kernel level, not just "a box that runs apps".
- Distinguish between Linux **Namespaces** (what a process can *see*) and **cgroups** (what a process can *use*).
- Compare containers with Virtual Machines and explain the shared-kernel model.
- Describe how Kubernetes, the Container Runtime Interface (CRI), and the Linux kernel work together to run a container.
- Create, inspect, and clean up a container with Docker to prove namespaces and cgroups are real.
- Explain common production signals such as `OOMKilled` (exit code 137).

This is the conceptual foundation for every later lesson. If you master this now, debugging production incidents later becomes dramatically easier.

## Prerequisites

- A Linux machine (Ubuntu preferred) or a terminal.
- Basic terminal comfort: running commands and reading output.
- Docker installed for the hands-on section. If Docker is not available, the concepts still apply and the commands can be run on a Linux host without it (with slightly different output).
- No prior Kubernetes knowledge is required. This lesson starts from first principles.

### Installing Docker

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y docker.io
sudo usermod -aG docker $USER
# Log out and back in for group changes to take effect

# Verify
docker --version
```

### Optional: Setting Up kind for Later Lessons

As you progress through this curriculum, you will need a Kubernetes cluster. Install kind now so you are ready:

```bash
# Linux (amd64)
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Create a cluster
kind create cluster --name learning

# Verify
kubectl cluster-info --context kind-learning
kubectl get nodes
```

Clean up when done:

```bash
kind delete cluster --name learning
```

## Real-world Motivation

Two classic failure modes in software delivery directly motivated containers:

**1. The "It Works on My Machine" problem.** A developer writes code on a laptop and it runs perfectly. They ship the same code to a production server and it crashes. Why? The production server has a different Java version, a missing system library, an older glibc, or a different operating system configuration. The application worked on the laptop not because it was correct everywhere but because it only worked with *that laptop's* exact environment.

**2. The resource starvation (noisy neighbor) problem.** Multiple applications share one server. One application develops a memory leak and gradually consumes all of the server's RAM. The kernel's Out-Of-Memory killer starts terminating processes until the leak is gone. Because nothing isolated one app from another, unrelated healthy applications are killed too. A single bad application takes down the whole machine.

Containers solve both problems:

- They package the application **code plus all of its dependencies** (libraries, runtimes, config) into a single image that runs identically anywhere.
- They restrict how much **CPU, memory, and I/O** an application may use, so one faulty app can no longer starve or crash its neighbors.

Understanding these fundamentals is not academic. When you see a Pod stuck in `CrashLoopBackOff` with exit code 137, or a node mysteriously under memory pressure, the answer lives in the mechanisms covered in this lesson.

### Real Company Examples

**Google:** At Google, everything runs in containers. They invented the concept of Borg, which directly inspired Kubernetes. When you run a search on Google, a container processes it. They use strict cgroup limits to ensure a query from one user does not starve resources from another user's query.

**Netflix:** Netflix uses containers to run its streaming algorithms. By using cgroups, they ensure that the recommendation engine never consumes so much CPU that the actual video streaming service crashes.

## Core Concepts

A container is a **standard Linux process** whose visibility and resource usage are constrained by two kernel features. Nothing more, nothing less.

> Container = Linux process + Namespaces (isolation) + cgroups (limitation)

**Namespaces (isolation): the blindfold.** Namespaces hide parts of the system from a process. Each container gets its own view of the process tree, network interfaces, and filesystem. A process inside a container believes it is alone on the machine. This is achieved by giving each container its own set of kernel data structures for things like PIDs, mounts, and network stacks.

**cgroups (limitation): the leash.** Control Groups limit, account for, and isolate how much CPU, memory, and I/O a collection of processes may use. If a container tries to exceed its memory cgroup limit, the Linux kernel's Out-Of-Memory Killer terminates the offending process.

### Explain Like I'm 12

Imagine you live in a big house with your family. Normally everyone shares the kitchen, the living room, and the electricity. Now imagine we build a soundproof wall inside your room. You cannot hear anyone else and they cannot hear you. From your perspective you are the only person in the house. That is a **namespace**.

Now we put a lock on your electrical panel so you can only use 10% of the house's electricity. If you try to use more, the lights in your room go out. That is a **cgroup**.

A container is simply a room with a soundproof wall (namespace) and an electricity limit (cgroup).

### Explain Like I'm a Junior Engineer

A container is **not** a virtual machine.

- A VM has its own complete guest operating system kernel.
- A container **shares** the host's Linux kernel.

To keep containers isolated, Linux provides two features:

- **Namespaces** give isolation. Key types include PID (processes), NET (network), MNT (mount points), UTS (hostname), IPC (inter-process communication), and USER (user ID mapping).
- **cgroups** give resource accounting and limitation. The kernel's CPU scheduler and memory manager enforce these limits.

### Explain Technically

Containers are simply Linux processes constrained by kernel features:

- **Namespaces** hide shared kernel resources so each container sees a private copy of them.
- **cgroups** bound how many resources (CPU time, memory pages, block and network I/O) those processes can consume.

The container runtime marshals the underlying kernel calls, but it does not add any magic of its own.

### How Kubernetes Implements It Internally

Kubernetes itself does not create containers. The **kubelet**, an agent running on every worker node, communicates with a **Container Runtime Interface (CRI)** implementation such as `containerd` or `CRI-O`. The runtime in turn invokes Linux system calls such as `clone()` and `unshare()` to create the namespaces and cgroups for the container process. The kubelet simply says "run this image".

```
kubectl apply --> kubelet --> containerd (CRI) --> Linux kernel
                                              --> clone()/unshare()
                                              --> create namespaces and cgroups --> container process
```

### Why Kubernetes Was Designed That Way

Kubernetes is deliberately decoupled from the underlying hardware and operating system. By relying on standard Linux primitives through the CRI abstraction, Kubernetes can run on any Linux machine. This lets many containers run securely on a single node without interfering with one another, and lets you swap runtimes (containerd, CRI-O) without changing how you write manifests.

## Architecture

To understand containers you must look at the Linux kernel. A container is not a virtual machine. A VM has its own entire operating system kernel. A container shares the host's Linux kernel.

The two mechanisms live inside the shared kernel:

- **Namespaces** isolate what each container can see (its own ID, mount, network space).
- **cgroups** bound what each container can use (CPU, memory, I/O).

Different containers on the same host therefore appear as separate, private machines even though they run on one shared kernel.

### Terminology

| Term | Definition |
|------|------------|
| Namespace | A Linux kernel feature that partitions kernel resources so that one set of processes sees one set of resources while another set sees a different set. |
| cgroup | Control Group. A Linux kernel feature that limits, accounts for, and isolates the resource usage (CPU, memory, disk I/O, network) of a collection of processes. |
| Container Runtime | The software responsible for running containers, for example containerd, CRI-O, or Docker. |
| Image | A read-only template containing instructions and content for creating a container. |
| Volume | A mechanism to persist data outside the container's ephemeral filesystem. |
| OOM Killer | The Linux Out-Of-Memory killer, which terminates processes that exceed their memory cgroup limit. |
| CFS | The Completely Fair Scheduler, the part of the Linux kernel that enforces CPU limits. |

### Namespace Types

| Namespace | Isolates | What the container no longer sees |
|-----------|----------|-----------------------------------|
| PID | Process IDs | The host's other processes; container-only process tree. |
| NET | Network stack | The host's interfaces and routing tables; its own IP address. |
| MNT | Mount points | The host's full filesystem layout; its own mount view. |
| UTS | Hostname and domain | The host hostname; it can set its own. |
| IPC | Inter-process communication | Host POSIX message queues and shared memory. |
| USER | User and group IDs | Host user account mapping; it can map its own UIDs. |

### How It Works Internally

When the kubelet starts a Pod (which contains containers), it reads the Pod spec and configures the two mechanisms:

- For **requests and limits**, it configures cgroups such as `cpu.shares` and `memory.limit_in_bytes`.
- For **isolation**, it configures namespaces such as PID, NET, and MNT.
- If a process exceeds `memory.limit_in_bytes`, the Linux kernel invokes the OOM Killer and terminates the process.

### Step-by-Step Workflow

When you run a container, whether through Docker or Kubernetes, the following steps happen under the hood:

1. The user runs `docker run` or `kubectl apply`.
2. The container runtime receives the instruction.
3. The runtime downloads the image (if not already present locally).
4. The runtime extracts the image filesystem.
5. The runtime calls the Linux kernel to create a new process.
6. The kernel creates new namespaces for the process (PID, NET, MNT, etc.).
7. The kernel applies cgroup limits to the process (CPU, memory).
8. The process starts inside its isolated bubble.

From the container's perspective, it is the only thing running on the machine. From the host's perspective, it is just another process with restricted visibility and resource usage.

### Container Lifecycle

A container is not always running. It passes through a defined set of states:

| State | Description |
|-------|-------------|
| Created | The runtime has registered the container with the OS, but the application process has not started yet. |
| Running | The application process is executing inside the container. |
| Paused | (Optional) The process is frozen by the runtime. All threads are suspended. |
| Stopped | The process has exited or been killed (either intentionally or by the OOM killer). |
| Deleted | The container filesystem and metadata are removed. All traces are gone. |

Understanding the lifecycle matters for debugging. A container stuck in `Created` means the runtime could not start the process. A container that keeps transitioning between `Running` and `Stopped` with high exit codes usually indicates a bug or a missing dependency.

### Containers vs Virtual Machines

| Feature | Virtual Machine (VM) | Container |
|---------|---------------------|-----------|
| OS Kernel | Has its own full guest kernel | Shares the host kernel |
| Isolation | Hardware-level (Hypervisor) | OS-level (Namespaces) |
| Size | Gigabytes (GB) | Megabytes (MB) |
| Boot Time | Minutes | Seconds |
| Resource Overhead | High (runs full OS) | Low (shares kernel) |
| Security Boundary | Stronger (hardware isolation) | Weaker (kernel is shared) |

The shared-kernel model is why containers are fast and lightweight. It is also why you must be careful: if the host kernel panics, all containers on that host die. VMs do not have this problem because each has its own isolated kernel.

### Real Company Examples

**Google:** At Google, everything runs in containers. They invented the concept of Borg, which directly inspired Kubernetes. When you run a search on Google, a container processes it. They use strict cgroup limits to ensure a query from one user does not starve resources from another user's query.

**Netflix:** Netflix uses containers to run its streaming algorithms. By using cgroups, they ensure that the recommendation engine never consumes so much CPU that the actual video streaming service crashes.

### Common Myths

| Myth | Fact |
|------|------|
| "Containers are just lightweight VMs." | This is dangerously wrong. VMs virtualize hardware. Containers virtualize the OS. They do not have their own kernel. If the host kernel panics, all containers on that host die. |
| "Containers are a strong security boundary by default." | Containers provide OS-level isolation, not a hardened boundary. A namespace breakout can grant access to the host. Defense in depth is required. |
| "Docker is the only way to run containers." | Docker is one container runtime. Kubernetes can use containerd, CRI-O, or any CRI-compliant runtime. Docker is not required. |

The result is that the container's resource usage is both accounted for and bounded by the kernel itself, independent of what any user-space component decides to do.

## ASCII Diagrams

Think of a container as a regular Linux process wearing a blindfold (namespaces) and tied to a leash (cgroups).

```
[ Linux Kernel ]
        |
   +----------+        <- Isolation (Blindfold = Namespaces)
   | Process  |        <- It only sees its own PID (e.g. PID 1)
   | (Container) |      <- It only sees its own IP address
   +----------+
        |
   [ cgroups ]         <- Limitation (Leash)
        |
   Max 512MB RAM
   Max 0.5 CPU
```

### Host View

```
                         Host Machine
+--------------------------------------------------------------+
|                      Linux Kernel (Shared)                     |
|                                                                |
|   +-----------------------------+   +-----------------------+   |
|   |  Namespace Container 1 (PID/NET/MNT) |   |  cgroup Container 1 |   |
|   |    - App code              |   |  Max 512MB RAM      |   |
|   |    - Libraries             |   |  Max 0.5 CPU        |   |
|   +-----------------------------+   +-----------------------+   |
|                                                                |
|   +-----------------------------+   +-----------------------+   |
|   |  Namespace Container 2 (PID/NET/MNT) |   |  cgroup Container 2 |   |
|   |    - App code              |   |  Max 1GB RAM        |   |
|   |    - Libraries             |   |  Max 1.0 CPU        |   |
|   +-----------------------------+   +-----------------------+   |
+----------------------------------------------------------------+
```

Each container believes it owns the machine, while the kernel silently hides the rest (namespace) and caps its appetite (cgroup).

## Hands-on

Objective: **Prove that two containers can run the same process (for example `sh`) and each believes it is Process ID 1, without conflicting.**

This mirrors the `isolation` half of the container story. A matching lab lives at [labs/lab-01-anatomy-of-a-container.md](../../labs/lab-01-anatomy-of-a-container.md).

Step 1 - Check the host's processes:

```bash
ps aux | head -n 10
```

You will see the host's normal processes, with `systemd` or `init` as PID 1.

Step 2 - Start an isolated container:

```bash
docker run -it --memory="512m" --cpus="1" ubuntu:22.04 /bin/bash
```

- `-it`: interactive terminal.
- `--memory="512m"`: creates a cgroup limiting RAM to 512MB.
- `--cpus="1"`: creates a cgroup limiting CPU to one core.

Step 3 - Look around inside the container:

```bash
ps aux
```

The output shows `/bin/bash` as PID 1. The host's `systemd` and other processes are invisible. This is the PID namespace working.

Step 4 - Optional: confirm the cgroup limit is real by running a memory-heavy command and watching the container get killed (see the Mini Project in [Scenario Questions](#scenario-questions) and the Troubleshooting section for the `OOMKilled` result).

Step 5 - Cleanup:

```bash
exit
```

Verification: You created a Linux namespace in which a process believes it is the only thing running, and a cgroup that restricts its resources.

## Commands

```bash
# Inspect the host's process tree
ps aux | head -n 10

# Run an isolated container with a memory and CPU cgroup
docker run -it --memory="512m" --cpus="1" ubuntu:22.04 /bin/bash

# See only the container's processes (PID namespace)
ps aux

# Inspect cgroups directly on a Linux host (namespaces/cgroups for this shell)
cat /proc/self/cgroup

# Inspect the memory cgroup limit for the current process
cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null

# Inspect the network namespace
ip link

# Leave the container
exit

# See containers that were killed for exceeding memory limits
docker ps -a

# Inspect exit metadata of a previously run container
docker inspect <container-id> | grep -i oom
```

## YAML Explanation

Containers do not have to be authored in YAML, but in Kubernetes a Pod manifest's `resources` field is translated by the kubelet into the exact cgroup settings we discussed. This is where namespaces and cgroups meet Kubernetes declarations.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: resource-demo
spec:
  containers:
    - name: app
      image: nginx:1.25.2-alpine
      resources:
        requests:
          cpu: "0.5"
          memory: "256Mi"
        limits:
          cpu: "1"
          memory: "512Mi"
```

Field-by-field explanation:

- `requests.cpu` and `requests.memory`: a *guarantee*. These map to cgroup shares (`cpu.shares` and cgroup memory) and reserve capacity so the scheduler places the Pod safely. The kernel guarantees this much.
- `limits.cpu`: a hard ceiling enforced by the Completely Fair Scheduler (CFS). The process may be throttled to stay under it.
- `limits.memory`: a hard ceiling enforced by the memory cgroup. Exceeding it triggers the OOM Killer and the container exits with code 137 (`OOMKilled`).

The rule of thumb: requests protect you from noisy neighbors, limits protect your neighbors from you. In Kubernetes you should usually set requests and limits together.

## Production Notes

From Listing in an image, to operating at scale, some things change:

- **Always set memory limits.** If a container leaks, it would otherwise consume the whole node and crash critical system processes. Setting the memory limit gives the kernel a boundary it can enforce before damage spreads.
- **Run as non-root.** Even though containers are isolated, if an attacker escapes the namespace they are root on the host node. Use a dedicated non-root user in the image and a read-only root filesystem.
- **Pin image tags.** Never use `latest`. If you use `nginx:latest`, a new version might be pulled tomorrow that breaks your app. Use `nginx:1.25.2-alpine` and promote images by immutable digest in serious environments.
- **Set CPU limits carefully.** Aggressive CPU limits can cause CFS throttling and latency spikes. Measure before capping.
- **Do not store state inside the container.** A container is ephemeral by design. Use volumes for anything that must survive a restart.
- **Distinguish requests from limits.** In production, requests protect you and limits protect neighbors. Match them to expected capacity and headroom.

### When to Use / When NOT to Use

Use containers when you need:

- Microservices architecture.
- Identical behavior across dev, staging, and prod.
- To pack many applications onto a single server efficiently.

Do NOT use containers when:

- The workload needs strict hardware-level isolation or custom kernel modules. Use a VM.
- The application needs a specific kernel version to run, for example a specialized network appliance. Containers share the host kernel.

### Performance and Security Considerations

**Performance:** Containers have near-zero performance overhead compared to bare metal because they use the host kernel directly. However, with strict CPU limits the Linux CFS may throttle the CPU, which can cause latency spikes. Tune limits to your real workload.

**Security:** Containers are not a security boundary by default. If an attacker escapes the namespace (a container breakout), they gain access to the host. Mitigate by running with a read-only filesystem, dropping all Linux capabilities where possible, using rootless builds, and applying namespace-isolation plus resource limits at the cluster level (covered in Module 07).

## Best Practices

- Set memory and CPU limits on every container.
- Run application processes as a non-root user with minimal capabilities.
- Pin images to immutable tags or digests, never `latest`.
- Use volumes for any persistent state.
- Keep images small: use a minimal base, multi-stage builds, and remove unnecessary packages.
- Place requests (guarantee) and limits (ceiling) deliberately and review them under load.
- Prefer read-only root filesystems and drop the `ALL` capabilities, then re-add only what is needed.
- Never store credentials or secrets in the image; inject them via Secrets (Module 06).

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Running containers as root | Convenience; base images default to root | Add a non-root user, run with `USER` in the Dockerfile, drop capabilities. |
| Not setting resource limits | Oversight, or fear of throttling | Always set `resources.limits`; start from observed baselines. |
| Storing data inside the container | Not understanding containers are ephemeral | Use volumes or Persistent Volumes for state. |
| Using `latest` tags | Speed of iteration | Use pinned tags, then promote by digest. |
| Treating containers as VMs | Confusing isolation models | Remember the shared kernel; security and kernel assumptions differ. |
| Blindly setting huge CPU limits | Trying to avoid throttling | Measure real usage and set matching requests and limits. |

## Troubleshooting

**Symptom: container dies immediately with exit code 137 and is reported `OOMKilled`.**
Cause: the Linux kernel terminated the process because it exceeded the memory limit set by the memory cgroup.
Fix: increase the memory limit in the container or Pod configuration, or fix the memory leak in the application code.

Diagnosis steps:

```bash
# List all containers, including stopped ones
docker ps -a

# Inspect the OOM/state of a specific container
docker inspect <container-id> | grep -i -E "state|oom"

# On Kubernetes
kubectl describe pod <pod-name>
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[0].state}'
```

Other frequent issues:

- **`CrashLoopBackOff`**: the process exits immediately, often due to missing config or a failed start. Check logs.
- **High latency under CPU limit**: CFS throttling. Relax the CPU limit or request more CPU.
- **Cannot see host processes**: expected inside a PID namespace. Use the host PID namespace if you intentionally want to see them.
- **`Permission denied` on startup**: often the container runs as root or lacks a device/capability.

## Interview Questions

If asked about this topic, be precise and concrete.

**Q: What is the difference between a container and a virtual machine?**
A: A VM virtualizes the hardware and runs a full guest operating system kernel. A container shares the host's kernel and uses Linux features, namespaces for isolation and cgroups for resource limits.
*Common wrong answer:* "Containers are just smaller VMs." This fails to mention the shared kernel, which is the defining difference.

**Q: How do containers isolate processes if they share the same kernel?**
A: Through Linux namespaces. Namespace types such as PID, NET, and MNT restrict what a process can see, making it believe it is the only process on the system.

**Q: What is an `OOMKilled` container and which kernel feature is responsible?**
A: An `OOMKilled` container tried to consume more memory than allowed. The Linux kernel's cgroup feature enforces the limit, and when it is breached the OOM Killer terminates the process.

**Q: Does Kubernetes run containers directly?**
A: No. The kubelet talks to a Container Runtime Interface (CRI) implementation, for example containerd or CRI-O, which makes the kernel calls that create the namespaces and cgroups.

**Q: What namespace types do you know and what do they isolate?**
A: PID (processes), NET (network stack), MNT (mount points), UTS (hostname), IPC (inter-process communication), and USER (user and group IDs).

**Q: Are containers a strong security boundary by default?**
A: No. They provide OS-level isolation, not a hardened boundary. A namespace breakout can grant access to the host. Defense in depth is required.

## Scenario Questions

**Scenario 1:** You have two containers on the same node. Container A starts consuming 100% of the CPU and container B becomes unresponsive. Why did this happen, and how do you fix it?
A: Container A most likely has no CPU cgroup limit, so it starves the node of CPU resources. Apply CPU requests and limits so the kernel scheduler throttles container A, leaving CPU for container B.

**Scenario 2 (Mini Project - The Resource Hog):** Prove the OOM behavior yourself.

```bash
# Run a container with NO memory limit and observe how it affects the host
docker run -it ubuntu:22.04 /bin/bash
# inside: run yes > /dev/null and observe CPU saturation

# Stop it, then run again with a hard memory limit
docker run -it --memory="100m" ubuntu:22.04 /bin/bash
# inside: run a command that allocates a lot of RAM
```

Observe that the unlimited container can destabilize the CPU, while the limited container is killed as soon as it exceeds 100MB.

## Quiz

1. What do cgroups provide?
   - A. Networking isolation
   - B. Resource accounting and limits for CPU, memory, and I/O
   - C. The container image format
   - D. A separate operating system kernel

2. Which statement about containers is correct?
   - A. Containers have their own full kernel
   - B. Containers share the host's Linux kernel
   - C. Containers require a hypervisor
   - D. Containers cannot run on Linux

3. Which kernel feature enforces a memory limit and triggers the OOM killer?
   - A. Namespaces
   - B. cgroups
   - C. iptables
   - D. SELinux

4. The PID namespace lets a container process believe it is which PID?
   - A. 0
   - B. 1
   - C. 42
   - D. 65535

5. What does the kubelet actually instruct the runtime to do?
   - A. Compile the application
   - B. Run a container image via the CRI
   - C. Install a hypervisor
   - D. Create a virtual machine

Answers: 1-B, 2-B, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- A container is a standard Linux process.
- Namespaces isolate what the process sees.
- cgroups limit what the process can use.
- Kubernetes does not run containers itself; it tells a container runtime, which tells the Linux kernel to create namespaces and cgroups.
- Not a VM: containers share the host kernel; VMs have their own kernel.

Memory trick:

- Namespace = the blindfold (isolation).
- cgroup = the leash (limitation).

Key facts:

- Container = Process + Namespace + cgroup.
- Exceeding a memory cgroup limit triggers the OOM Killer (exit code 137).
- CPU limits are enforced by the Completely Fair Scheduler (CFS).

## Cheat Sheet

| Command / Concept | What it does |
|-------------------|--------------|
| `docker run -it --memory="512m" ubuntu` | Runs a container with a 512MB RAM cgroup limit. |
| `docker run -it --cpus="1" ubuntu` | Runs a container with a one-CPU cgroup limit. |
| `ps aux` | Lists running processes; inside a container it shows only that container's PIDs. |
| `OOMKilled` (exit 137) | Kernel killed the process for exceeding its cgroup memory limit. |
| `/proc/self/cgroup` | Shows the cgroups the current process belongs to. |
| `kubectl run` / Pod `resources` | The Kubernetes way to express requests and limits, mapped to cgroups by the kubelet. |

## References

- [Kubernetes Documentation: Containers](https://kubernetes.io/docs/concepts/containers/)
- [Kubernetes Documentation: Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Linux man page: unshare(2)](https://man7.org/linux/man-pages/man2/unshare.2.html)
- [Linux man page: namespaces(7)](https://man7.org/linux/man-pages/man7/namespaces.7.html)
- [Linux man page: cgroups(7)](https://man7.org/linux/man-pages/man7/cgroups.7.html)
- [Docker Documentation](https://docs.docker.com/)
- [containerd](https://containerd.io/)
- [CRI-O](https://cri-o.io/)

## Related Lessons

- [Module 03: Workloads - Pods](../03-workloads/README.md) - why Pods, not containers, are the smallest unit in Kubernetes.
- [Module 06: Configuration - resource requests and limits](../06-configuration/README.md) - how namespaces and cgroups map to Kubernetes `resources`.
- [Module 07: Security - image security](../07-security/README.md) - running containers safely as non-root.
- [Module 13: Troubleshooting - workload diagnosis](../13-troubleshooting/README.md) - diagnosing `OOMKilled` and resource issues.

## Coming Next

Now that you understand the low-level building blocks, the next lesson moves up one level: what container orchestration is, why manually managing dozens of containers breaks down, and the problems Kubernetes was built to solve. The thinking "container = process + isolation + limits" will motivate everything that follows.