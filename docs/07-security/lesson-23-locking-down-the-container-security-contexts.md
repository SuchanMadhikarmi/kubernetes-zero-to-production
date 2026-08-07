---
title: Lesson 23 - Locking Down the Container (Security Contexts)
module: 07 Security
lesson: 23
status: Complete
tags: [kubernetes, security, security-context, runasnonroot, capabilities, read-only, psa, production]
---

# Lesson 31 - Locking Down the Container (Security Contexts)

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

- Explain what a Security Context is in Kubernetes.
- Prevent a container from running as the root user.
- Explain Linux Capabilities and how to drop them.
- Use `readOnlyRootFilesystem` to stop attackers from downloading malware.
- Debug a `CreateContainerError` caused by strict security contexts.

## Prerequisites

- Completion of Lessons 1 through 30.
- A running kind cluster.
- `kubectl` installed and configured.
- Familiarity with how the CRI and the Linux kernel isolate processes (covered in Lesson 3).

## Real-world Motivation

### The Compromised Container

Imagine you deploy a standard Nginx web server. A hacker finds a Remote Code Execution (RCE) vulnerability in your web application and drops into a shell inside the Nginx container. Because the container runs as root by default, the hacker has full administrative privileges inside the container's namespace. They can download malware (`wget malicious-script.sh`), read mounted Kubernetes Secrets, and attempt to pivot to the host node.

### Why This Exists

To enforce defense-in-depth. Even if the application is compromised, the attacker should be trapped in a least-privilege sandbox. Security Contexts let you tell the Linux kernel: "Run this process as user 1000, give it zero administrative capabilities, and make the filesystem read-only so it can't write files."

### Real Company Examples

**Fintech Company:** A major financial institution enforces strict Security Contexts via Kyverno. Every Pod MUST have `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, and `capabilities.drop: ["ALL"]`. An attacker who exploits an RCE vulnerability finds themselves as user 1000, unable to write to the filesystem, and unable to use sudo. They are trapped in a read-only sandbox, completely neutralizing the attack.

## Core Concepts

### Explain Like I'm 12

Imagine a guest coming to your house. By default, they have the keys to the front door, the safe, and the garage. A Security Context is you taking away the keys. You say: "You are only allowed in the living room (non-root user), you cannot open the safe (drop capabilities), and you are not allowed to write on the walls (read-only filesystem)."

### Explain Like I'm a Junior Engineer

A Security Context is a field in the Pod YAML that tells the container runtime to apply specific Linux kernel restrictions. You can force the app to run as a non-root user, strip away all Linux capabilities, and mount the filesystem as read-only. This ensures that even if an attacker gets into the container, they cannot do any damage.

### Explain Technically

When the kubelet calls the Container Runtime Interface (CRI) to start a container, it passes the Security Context settings. The container runtime (containerd) translates them into an Open Container Initiative (OCI) runtime spec:

- `runAsUser` maps to the UID in the process's user namespace.
- `readOnlyRootFilesystem` sets `readonly: true` in the rootfs mount options.
- `capabilities.drop` strips specific bits from the process's effective capability set, instructing the Linux kernel to deny privileged operations (like changing file ownership or binding to low ports).

### How Kubernetes Implements It Internally

The kubelet acts as a gatekeeper. Before starting a container, it inspects the image metadata to determine the default user. If the image defaults to UID 0 and the request specifies `runAsNonRoot: true`, the kubelet refuses to start the container and reports `CreateContainerError`. Only when the user is valid does the runtime configure the kernel cgroups and namespaces to enforce the UID and dropped capabilities.

### Why Kubernetes Was Designed That Way

Containers are isolated by namespaces but not allowed by identity. Decoupling the runtime enforcement (Security Contexts) from the admission-time policy enforcement (PSA/Kyverno) means developers can fine-tune privileges per unit of work while cluster administrators enforce a minimum baseline cluster-wide. Defense-in-depth requires both layers.

## Architecture

```
[ Pod Spec ]
    securityContext:
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      |
      v
[ Kubelet -> CRI (containerd) -> Linux Kernel ]
      |
      v
[ Container Process ]
  - UID: 1000 (Not root)
  - Filesystem: / (Read-Only)
  - Capabilities: None
```

### Terminology

| Term | Definition |
|------|------------|
| Security Context | A Kubernetes block defining privilege and access control for a Pod or Container. |
| UID | User Identifier. 0 is root. 1000+ is typically a normal user. |
| Linux Capabilities | Fine-grained permissions that divide root privileges (for example, `CAP_NET_BIND_SERVICE`). |
| runAsNonRoot | A boolean flag that blocks the container from running as UID 0. |
| readOnlyRootFilesystem | A boolean flag that mounts the container's root filesystem as read-only. |
| allowPrivilegeEscalation | A boolean flag that prevents a process from gaining more privileges than its parent (blocks sudo or setuid binaries). |

### How It Works Internally

1. You apply a Pod YAML with `securityContext.runAsNonRoot: true`.
2. The API Server saves it to etcd.
3. The scheduler assigns it to a node.
4. The kubelet on that node receives the Pod.
5. Before starting the container, the kubelet inspects the image metadata.
6. If the image defaults to root (UID 0) and the YAML says `runAsNonRoot: true`, the kubelet refuses to start it (`CreateContainerError`).
7. If the image specifies a non-root user (or the YAML sets `runAsUser: 1000`), the kubelet starts it.
8. The container runtime configures the kernel to enforce the UID and dropped capabilities.

### Step-by-Step Workflow

1. Developer writes a Pod spec with a strict Security Context.
2. `kubectl apply` sends it to the API Server.
3. The API Server saves it.
4. The kubelet receives the Pod.
5. The kubelet validates the image user against `runAsNonRoot`.
6. If valid, the runtime starts the container with restricted UID, capabilities, and filesystem.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | The kubelet validates the context. If invalid, the Pod enters `CreateContainerError`. If valid, the container runs with restricted privileges. |
| Running | The app operates normally, but any attempt to write to `/` or bind to port 80 fails. |
| Deletion | Standard Pod deletion applies. |

### Communication Patterns

| Communication | Mechanism | Example |
|---------------|-----------|---------|
| kubelet -> API Server | Store Pod spec | `POST /api/v1/namespaces/default/pods` |
| kubelet -> CRI | Start container | `runtime.v1.ContainerRuntimeService.StartContainer` |
| CRI -> OCI runtime | Apply privileges | `runc create --uid 1000 --cap-drop ALL` |
| kubelet -> API Server | Report status | Pod status `CreateContainerError` |

### Common Myths

| Myth | Fact |
|------|------|
| "Containers are inherently secure because they are isolated." | False. Containers run as root by default. Namespaces isolate them, but a breakout leaves root on the node. |
| "If I set runAsUser: 1000, I don't need runAsNonRoot: true." | Safer to use both. `runAsNonRoot` is a hard validation check at the kubelet level. |

## ASCII Diagrams

Mental Model: A Security Context is a straitjacket for your container. It restricts its movement, removes its tools (capabilities), and prevents it from modifying anything permanent.

```text
[ Container Process ]
  - Runs as UID 1000, not 0
  - Cannot use sudo
  - Cannot write to /
  - Cannot bind to port 80
      |
      v
[ Linux Kernel ]
  - Enforces the UID
  - Checks Capabilities
  - Denies privileged actions
      |
      v
[ Container Filesystem ]
  - Root is Read-Only. Writes are rejected (Read-only file system).
  - Only /tmp (if mounted as a volume) is writable.
```

## Hands-on

### Objective

Deploy a strict, locked-down Pod. Try to hack it, then deploy a broken Pod that the kubelet refuses to start.

### Step 1: Create a Locked-Down Pod

Create `secure-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
  - name: app
    image: busybox:latest
    command: ["sleep", "3600"]
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
```

Apply it:

```bash
kubectl apply -f secure-pod.yaml
```

Wait for it to be `Running`.

### Step 2: Try to Hack the Container (The Failure)

Exec into the container and act like an attacker who just gained a shell:

```bash
kubectl exec -it secure-app -- sh
```

Inside the container, try these commands:

Try to write a file to the root directory:

```sh
touch /hacked.txt
```

Expected Output: `touch: /hacked.txt: Read-only file system`

Try to bind to a low port (requires `CAP_NET_BIND_SERVICE`):

```sh
nc -l -p 80
```

Expected Output: `nc: bind: Permission denied`

Try to check your user ID:

```sh
id
```

Expected Output: `uid=1000` (not root).

Type `exit`.

### Step 3: Break Things On Purpose

Deploy an image that defaults to root but with a strict Security Context applied:

Create `broken-secure.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: broken-secure
spec:
  securityContext:
    runAsNonRoot: true
  containers:
  - name: app
    image: redis:alpine
```

Apply it:

```bash
kubectl apply -f broken-secure.yaml
```

### Step 4: Investigate the Failure

```bash
kubectl get pod broken-secure
```

It should be in `CreateContainerError` or `CrashLoopBackOff`, not `Running`.

```bash
kubectl describe pod broken-secure
```

**Your Task:**

1. What state is the `broken-secure` Pod in?
2. What is the exact error message in the Events section?
3. Why did the kubelet refuse to start this Redis container? (Hint: what user does the `redis:alpine` image run as by default?)

(Answer: 1. `CreateContainerError`. 2. `CreateContainerConfigError: container has runAsNonRoot and image will run as root`. 3. The `redis:alpine` image defaults to root (UID 0). The YAML has `runAsNonRoot: true`. The kubelet acts as a bouncer and refuses to start the container to enforce security.)

### Cleanup

```bash
kubectl delete pod secure-app broken-secure
```

## Commands

```bash
# Run a command inside the container as UID 1000
kubectl exec -it secure-app -- sh

# Show the current user inside the container
kubectl exec secure-app -- id

# Inspect a CreateContainerError
kubectl describe pod broken-secure

# Verify the image's default user
docker inspect redis:alpine --format '{{.Config.User}}'

# Inspect the effective user your YAML asks for
kubectl get pod secure-app -o jsonpath='{.spec.containers[0].securityContext}'
```

## YAML Explanation

The core YAML from the hands-on lab:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
  - name: app
    image: busybox:latest
    command: ["sleep", "3600"]
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
```

### Field-by-Field Explanation

- `spec.securityContext`: Applies to all containers in the Pod. Forces them to run as UID 1000 and forbids root.
- `containers[].securityContext`: Applies to this specific container.
- `allowPrivilegeEscalation: false`: Prevents the process from gaining more privileges than its parent (blocks sudo or setuid binaries).
- `readOnlyRootFilesystem: true`: Mounts the container's `/` as read-only.
- `capabilities.drop: [ALL]`: Drops all Linux kernel capabilities.

## Production Notes

- Always run as non-root: use `runAsNonRoot: true` and `runAsUser: 1000`.
- Make the filesystem read-only (`readOnlyRootFilesystem: true`). If your app needs to write temp files, mount an emptyDir volume to `/tmp`.
- Drop ALL capabilities (`capabilities.drop: ["ALL"]`). Only add back specific capabilities your app truly needs (for example, `NET_BIND_SERVICE` for port 80).
- Enforce via Policy as Code: don't rely on developers remembering these. Use Kyverno or Pod Security Admission (PSA) to enforce contexts at the API Server level.
- Legacy apps that need root to bind to port 80: run them on port 8080 instead and use an Ingress to translate 80 -> 8080.
- Monitoring agents (like Node Exporter) may require privileged Pods; isolate them in the `kube-system` namespace.

### When to Use / When NOT to Use

**Use strict Security Contexts when:**

- Always in production. Every Pod should run as non-root with a read-only filesystem and dropped capabilities.

**Avoid strict Security Contexts when:**

- Running a legacy application that truly requires root to bind to a privileged port (prefer 8080 + Ingress).
- Running host-coupled monitoring agents (Node Exporter) that require privileged access; isolate them to `kube-system`.

### Performance and Security Considerations

**Performance:** Security Contexts have zero runtime overhead. The kernel checks capabilities and UIDs on every syscall anyway; applying restrictions just changes the answer from allow to deny.

**Security:** This is the core of container security. Without dropping capabilities and running as non-root, a container breakout to the host node is far easier for an attacker.

## Best Practices

- Always set `allowPrivilegeEscalation: false`.
- Use `runAsNonRoot: true` and a non-zero `runAsUser`.
- Drop `["ALL"]` capabilities then re-add only those your app needs (allow-listing).
- Mount `emptyDir` to `/tmp` for apps that write temporary files with a read-only root filesystem.
- Set a read-only root filesystem on every container.
- Enforce these settings at the admission layer with PSA `restricted` or Kyverno, not just per-team memory.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| `runAsNonRoot: true` on a root image | The kubelet refuses it with `CreateContainerError` | Build a `USER 1000` image or set `runAsUser: 1000` in the Pod |
| `readOnlyRootFilesystem` without a /tmp volume | Java/Node write temp files and crash with `Permission denied` | Mount an `emptyDir` volume to /tmp |
| Applying contexts only at the Pod level | Container-level security overrides Pod-level in multi-container Pods | Be specific inside each container in multi-container Pods |
| Missing `allowPrivilegeEscalation: false` | Under heavy settings the process can still escalate via setuid | Always set it explicitly |

## Troubleshooting

**Symptom: CreateContainerError or CrashLoopBackOff**

```bash
kubectl describe pod <name>
```

If the Events section says `container has runAsNonRoot and image will run as root`, your YAML and your image user conflict.

Fix Option A: rebuild the Docker image with `USER 1000` in the Dockerfile.
Fix Option B: set `runAsUser: 1000` in the Pod YAML to override the image's default user.

**Symptom: App crashes on startup (read-only filesystem)**

```bash
kubectl logs <pod>
```

If you see `IOException: Permission denied` or `Unable to create log file`, the app is trying to write to the root filesystem. Mount an `emptyDir` volume to the directory the app needs (e.g., `/tmp` or `/var/log/app`).

## Interview Questions

**Q: What is a Security Context in Kubernetes?**

A: A YAML block in the Pod or Container spec that defines privilege and access control settings, such as the user ID to run as, Linux capabilities to drop, and whether the filesystem is read-only.

**Q: How do you prevent a container from running as root?**

A: I set `runAsNonRoot: true` and `runAsUser: 1000` in `securityContext` of the Pod spec.

**Q: If you set `runAsNonRoot: true` but the Docker image defaults to root, what happens?**

A: The kubelet refuses to start the container. The Pod enters `CreateContainerError` with the message `container has runAsNonRoot and image will run as root`. I must explicitly set `runAsUser: 1000` in the YAML to override the image default.

**Q: What is the mechanism/layer where a Security Context is enforced?**

A: The kubelet passes it to the container runtime via the CRI; the runtime turns it into an OCI spec that the Linux kernel enforces.

**Q: True or False: Setting `readOnlyRootFilesystem: true` prevents `kubectl exec` from entering the Pod.**

A: False. It only makes the root filesystem read-only; exec still works.

## Scenario Questions

**Scenario 1:** Your application writes temporary session files to `/tmp`. You enable `readOnlyRootFilesystem: true` and the app crashes with `Permission denied`. How do you fix it while keeping security?

A: Mount an `emptyDir` volume to `/tmp` in the Pod spec and point the app's temp directory there. This keeps the rest of the container filesystem immutable while allowing temporary writes.

**Scenario 2 (Mini Project - The Non-Root Nginx):**

Standard Nginx images default to root. Create a Pod YAML for Nginx with `runAsNonRoot: true` and `runAsUser: 101` (the nginx user inside the image). Change the port Nginx listens on from 80 to 8080, because non-root users cannot bind to port 80. Verify the Pod starts successfully and is secure.

## Quiz

1. What does `runAsNonRoot: true` do?
   - A. Runs the container as UID 1000
   - B. Blocks the container from running as UID 0
   - C. Drops all network namespace permission
   - D. Mounts the filesystem read-only

2. What is the default value of `runAsUser` for containers?
   - A. 1000
   - B. Never run
   - C. 0 (root)
   - D. 65534

3. What Linux capability is required to bind to a privilege-port like port 80?
   - A. CAP_NET_RAW
   - B. CAP_SYS_ADMIN
   - C. CAP_NET_BIND_SERVICE
   - D. CAP_DAC_OVERRIDE

4. Which flag prevents a process from gaining more privileges than its parent (blocks sudo)?
   - A. `runAsNonRoot`
   - B. `allowPrivilegeEscalation: false`
   - C. `readOnlyRootFilesystem`
   - D. `privileged: true`

5. What error appears when a container with `runAsNonRoot: true` uses an image that defaults to root?
   - A. ImagePullBackOff
   - B. CrashLoopBackOff only
   - C. CreateContainerConfigError: container has runAsNonRoot and image will run as root
   - D. DeadlineExceeded

Answers: 1-B, 2-C, 3-C, 4-B, 5-C.

## Revision

One-minute revision:

- `runAsNonRoot: true` blocks root.
- `readOnlyRootFilesystem: true` blocks file writes.
- `capabilities.drop: ["ALL"]` blocks kernel privileges.
- `allowPrivilegeEscalation: false` blocks sudo/setuid.
- `CreateContainerError` with the root message means the image defaults to root.

Memory trick:

- Security Context = a straitjacket for your container.
- `runAsNonRoot`: a bouncer checking ID at the door.
- `readOnlyRootFilesystem`: furniture glued to the floor; you can look but not move anything.

Key facts:

- Containers run as root by default.
- Security Contexts work at the Linux kernel / OCI level.
- `runAsNonRoot` fails-fast when combined with a root image.
- Read-only/filesystem enforced via mount options.

## Cheat Sheet

| YAML Field | What it does |
|-----------|--------|
| `securityContext.runAsNonRoot: true` | Blocks containers from running as UID 0 |
| `securityContext.runAsUser: 1000` | Forces the process to run as UID 1000 |
| `securityContext.readOnlyRootFilesystem: true` | Makes the container's `/` read-only |
| `securityContext.allowPrivilegeEscalation: false` | Prevents sudo or setuid escalation |
| `securityContext.capabilities.drop: [ALL]` | Drops all Linux kernel capabilities |

## References

- [Kubernetes Documentation: Configure a Security Context for a Pod or Container](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Kubernetes Documentation: Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- [Kubernetes Documentation: Linux Capabilities](https://kubernetes.io/docs/concepts/security/)
- [Kubernetes Blog: Security Contexts and Pod Security Standards](https://kubernetes.io/blog/)

## Related Lessons

- [Lesson 11 - RBAC and Service Accounts](lesson-22-rbac-and-service-accounts.md) - authorizing which users and ServiceAccounts may act in the cluster.
- [Lesson 35 - Monitoring and Metrics](../08-observability/lesson-24-monitoring-and-metrics.md) - observing events in the control plane.
- Lesson 42 - Node Pressure and Evictions - security contexts interact with eviction ordering.

## Coming Next

In the next lesson you continue the security module with image security and the software supply chain: trusting registries, signing images, scanning for CVEs, and using Kyverno or PSA to enforce a restricted baseline end-to-end.