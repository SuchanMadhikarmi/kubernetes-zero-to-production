---
title: Lesson 22 - Init Containers
module: 03 Workloads
lesson: 22
status: Complete
tags: [kubernetes, workloads, init-containers, emptydir, pod-lifecycle, setup, prerequisites]
---

# Lesson 22 - Init Containers

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

- Explain what an Init Container is and how it differs from a regular container.
- Describe the sequential lifecycle of a Pod with Init Containers.
- Use Init Containers to share data with the main app using `emptyDir` volumes.
- Intentionally break an Init Container and observe the `Init:CrashLoopBackOff` state.

## Prerequisites

- Completion of Lessons 1 through 21.
- A running kind cluster.
- kubectl installed and configured.

## Real-world Motivation

### The Bloated Image & Missing Prerequisites

Imagine you deploy an Nginx web server. Before Nginx starts, it needs a custom `nginx.conf` file and an SSL certificate from an AWS S3 bucket. If you write a bash script to download these files and put it in the Nginx container's entrypoint, you violate the single-responsibility principle. Your Nginx image now needs `aws-cli`, `bash`, and `curl` installed, making it bloated and insecure. Furthermore, if the S3 bucket is down, Nginx might start with a missing configuration and crash.

### Why This Exists

Kubernetes needed a way to separate setup logic from the main application. Init Containers are specialized containers that run to completion before the main application container even starts. They allow you to use a tooling image (like an Alpine image with `git` or `aws-cli`) to do the setup, and a clean, minimal Nginx image to serve the traffic.

### Real Company Examples

**Ad-Tech Company:** An ad-tech company runs an Nginx web server. Before Nginx starts, an Init Container runs. This Init Container uses `aws-cli` to fetch the SSL certificate and the `nginx.conf` file from an AWS S3 bucket, writing them to a shared volume. Once the Init Container finishes, Nginx starts, mounts that volume, and immediately has its config and SSL certs ready.

## Core Concepts

### Explain Like I'm 12

Imagine you are baking a cake. The main application container is the oven baking the cake. But before you can turn on the oven, someone has to mix the ingredients and grease the pan. The Init Container is the prep chef. They do all the setup, and only when they are completely finished and leave the kitchen does the oven turn on. If the prep chef gets sick and can't finish, the oven never turns on.

### Explain Like I'm a Junior Engineer

An Init Container is a container that runs at startup and exits. A Pod can have multiple Init Containers. They run strictly in order (1, then 2, then 3). If Init Container 1 fails, the Pod restarts, and Init Container 1 tries again. The main app containers will never start until all Init Containers exit with code 0.

### Explain Technically

- Init Containers share the same Pod's Linux namespaces (Network, IPC) and volumes, but they do not share the same process space.
- The kubelet runs the Init Containers sequentially. It does not run them in parallel.
- If an Init Container fails, the kubelet applies the Pod's `restartPolicy` (which is `Always` for Deployments). The Pod goes back to the beginning of the Init phase.
- Because they share a volume (like `emptyDir`), an Init Container can write files to a directory, and the main container can read them.

### How Kubernetes Implements It Internally

When the kubelet receives a Pod with `initContainers`, it updates the Pod's status to `Initialized=False`. It starts the first Init Container via the CRI. It polls the container status. Once it exits with 0, it starts the next one. Once all are done, it sets `Initialized=True` and starts the containers (the main app).

### Why Kubernetes Was Designed That Way

Kubernetes was designed to keep containers focused on a single responsibility. Init Containers separate setup logic from the main application. This allows you to use specialized tooling images for setup (e.g., Alpine with `curl` or `git`) and minimal images for the main application (e.g., Nginx).

## Architecture

```
[ Pod Lifecycle ]
      |
      v
[ Init Container 1 ] -> Exits 0 (Success)
      |
      v
[ Init Container 2 ] -> Exits 0 (Success)
      |
      v
[ Main App Container ] -> Starts and Runs Forever
```

### Terminology

| Term | Definition |
|------|------------|
| Init Container | A specialized container that runs before the main app containers and must exit successfully. |
| emptyDir | A volume type that is created empty when a Pod is assigned to a node, and deleted when the Pod is removed. |
| Initialized Condition | A Pod condition that is set to `True` only after all Init Containers have completed successfully. |

### How It Works Internally

1. The kubelet receives the Pod spec.
2. It mounts the `emptyDir` volume into the node's filesystem.
3. It starts the `setup-script` Init Container, mounting `emptyDir` to `/work-dir`.
4. The Init Container runs `echo '<h1>...' > /work-dir/index.html` and exits with code 0.
5. The kubelet sees the successful exit.
6. It starts the `web-server` main container, mounting the same `emptyDir` to `/usr/share/nginx/html`.
7. Nginx starts and serves the `index.html` file.

### Step-by-Step Workflow

1. Developer creates a Pod YAML with `initContainers` and `containers`.
2. `kubectl apply` sends it to the API Server.
3. Scheduler assigns the Pod to a Node.
4. Kubelet starts the Init Container.
5. Init Container performs setup (e.g., downloads a file) and exits 0.
6. Kubelet starts the Main Container.
7. Main Container runs and serves traffic.

### Lifecycle

| State | Description |
|-------|-------------|
| Init Phase | Init Containers run sequentially. Pod status is `Init:...`. |
| Failure | If an Init Container fails, the Pod restarts (if `restartPolicy: Always`). The Init Container retries. |
| Main Phase | Once all Init Containers pass, the Main Containers start. |
| Deletion | When the Pod is deleted, the `emptyDir` volume is deleted with it. |

### Feature Comparison

| Feature | Init Container | Main Container | Sidecar Container |
|---------|---------------|----------------|-------------------|
| Lifecycle | Runs to completion, then dies. | Runs forever. | Runs forever alongside main. |
| Execution Order | Sequential, before Main. | After all Init Containers. | Concurrent with Main. |
| Use Case | Setup, downloading configs. | The actual application. | Logging, proxies, mTLS. |

### Common Myths

| Myth | Fact |
|------|------|
| "Init Containers run in parallel with the main app." | False. They must complete and exit before the main app container is even created. |
| "If an Init Container fails, the main app starts anyway." | False. The main app is never created until all Init Containers exit with code 0. The Pod will restart and retry the Init Container. |

## ASCII Diagrams

Mental Model: The Init Container is the stage crew. They set up the props and lights before the play begins. Once they leave, the actors (main containers) come out.

```
[ Pod: web-app ]
  Volumes:
  - shared-data (emptyDir)

  Init Containers:
  - setup-script (busybox)
      | writes index.html to /work-dir
      v
      Exits 0

  Containers:
  - web-server (nginx)
      reads /usr/share/nginx/html (shared-data)
```

## Hands-on

### Objective

Create a Pod with an Init Container that generates an `index.html` file. The main Nginx container will then serve that file.

### Step 1: Create the Init Pod

Create `init-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: init-demo
spec:
  volumes:
  - name: shared-data
    emptyDir: {}
  initContainers:
  - name: setup-script
    image: busybox:latest
    command: ["sh", "-c", "echo '<h1>Config loaded by Init Container!</h1>' > /work-dir/index.html"]
    volumeMounts:
    - name: shared-data
      mountPath: /work-dir
  containers:
  - name: web-server
    image: nginx:alpine
    volumeMounts:
    - name: shared-data
      mountPath: /usr/share/nginx/html
```

**Field Explanation:**

- `volumes.emptyDir: {}`: A temporary disk created on the node's RAM/disk.
- `initContainers`: The setup phase. We use `busybox` to echo HTML text into `/work-dir/index.html`. Because `/work-dir` is mounted to `shared-data`, the file is written to the shared disk.
- `containers`: The main Nginx container. It mounts the same `shared-data` volume to Nginx's default HTML directory (`/usr/share/nginx/html`).

Apply it:

```bash
kubectl apply -f init-pod.yaml
```

### Step 2: Verify the Setup Worked

Wait for the Pod to be Running, then let's test it by grabbing the HTML Nginx is serving.

```bash
kubectl exec init-demo -c web-server -- cat /usr/share/nginx/html/index.html
```

Expected output: `Config loaded by Init Container!`

### Step 3: Break Things on Purpose

Create `broken-init.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: broken-init
spec:
  volumes:
  - name: shared-data
    emptyDir: {}
  initContainers:
  - name: broken-setup
    image: busybox:latest
    command: ["sh", "-c", "echo 'Trying to download config...' && exit 1"]
    volumeMounts:
    - name: shared-data
      mountPath: /work-dir
  containers:
  - name: web-server
    image: nginx:alpine
    volumeMounts:
    - name: shared-data
      mountPath: /usr/share/nginx/html
```

Apply it:

```bash
kubectl apply -f broken-init.yaml
```

### Step 4: Investigate the Failure

Wait about 15 seconds, then run:

```bash
kubectl get pod broken-init
```

Expected output: The STATUS should be `Init:CrashLoopBackOff`.

Run `kubectl describe pod broken-init`. Look at the `Containers:` section. Notice that the `web-server` container isn't even listed yet! Look at the `Init Containers:` section and the Events at the bottom.

**Your Task:**

- What is the exact STATUS of the `broken-init` pod?
- In the `kubectl describe` output, does the main `web-server` container exist yet?
- Based on the theory of the Pod lifecycle, why hasn't Nginx started?

(Answer: 1. `Init:CrashLoopBackOff`. 2. No, it does not exist. 3. The kubelet enforces a strict rule: the main containers cannot be created until ALL Init Containers have successfully exited with code 0. Because the Init Container exited with 1, the Pod restarted and is trying the Init Container again. Nginx is held hostage).

### Step 5: Cleanup

```bash
kubectl delete pod init-demo broken-init
```

## Commands

```bash
# Crucial: You must specify the init container name to see its logs
kubectl logs <pod> -c <init-container-name>

# Check if status is Init:CrashLoopBackOff or Running
kubectl get pod <name>

# Describe pod to see Init Container status
kubectl describe pod <name>

# Check Pod conditions
kubectl get pod <name> -o jsonpath='{.status.conditions}'
```

## YAML Explanation

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: init-demo
spec:
  volumes:
  - name: shared-data
    emptyDir: {}
  initContainers:
  - name: setup-script
    image: busybox:latest
    command: ["sh", "-c", "echo '<h1>Config loaded by Init Container!</h1>' > /work-dir/index.html"]
    volumeMounts:
    - name: shared-data
      mountPath: /work-dir
  containers:
  - name: web-server
    image: nginx:alpine
    volumeMounts:
    - name: shared-data
      mountPath: /usr/share/nginx/html
```

### Field-by-Field Explanation

- `volumes[0].name: shared-data`: The name of the shared volume.
- `volumes[0].emptyDir: {}`: Creates a temporary empty directory.
- `initContainers[0].name: setup-script`: The Init Container name.
- `initContainers[0].command`: The setup script.
- `initContainers[0].volumeMounts`: Mounts the shared volume to `/work-dir`.
- `containers[0].name: web-server`: The main container name.
- `containers[0].volumeMounts`: Mounts the shared volume to `/usr/share/nginx/html`.

## Production Notes

- **Use for Setup Only:** Init Containers should be short-lived. Don't run a daemon (like a proxy) in an Init Container. (For long-running sidecars, use the new native Sidecar Containers feature in K8s 1.28+).
- **Share Volumes:** Use `emptyDir` to pass data from the Init Container to the Main Container.
- **Keep Images Small:** Init Containers often just need `curl` or `git`. Use Alpine-based images to keep them lightweight.

### When to Use / When NOT to Use

**Use Init Containers when:**

- Waiting for a database or external service to be reachable before starting the app.
- Downloading configuration files or secrets from an external source (S3, Git).
- Registering the Pod with a service discovery mechanism.

**Avoid Init Containers when:**

- For long-running processes. If it doesn't exit, the main app never starts.
- If the setup logic is trivial and can be handled in the main container's entrypoint script.

### Performance and Security Considerations

**Performance:** Because Init Containers run sequentially, having 5 Init Containers means the Pod takes 5x longer to boot. Combine setup logic into one container if possible.

**Security:** Init Containers often need different permissions than the main app (e.g., access to a cloud IAM role to download secrets). You can apply a separate SecurityContext to the Init Container.

## Best Practices

- Use Init Containers for setup only.
- Share data via `emptyDir`.
- Keep Init Container images small (Alpine).
- Use Init Containers to wait for dependencies.
- Don't run long processes in Init Containers.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Not sharing volumes | Expecting Init Container to write to Main Container's filesystem | Define a shared `emptyDir` volume |
| Infinite Loops | Waiting for a database that never comes up | Set timeouts and proper error handling |
| Forgetting `-c` | Not specifying Init Container name in logs | Always use `-c <init-container-name>` |
| Running long processes | Init Container doesn't exit, main app never starts | Use Init Containers for short-lived setup only |

## Troubleshooting

**Symptom: Pod stuck in `Init:CrashLoopBackOff`**

Cause: Init Container failing repeatedly.

```bash
kubectl describe pod <name> | grep -A 5 "Init Containers:"
```

Fix: Check Init Container logs with `kubectl logs <pod> -c <init-container-name>`.

**Symptom: Pod stuck in `Init:Error`**

Cause: Init Container exited with non-zero code.

```bash
kubectl get pod <name> -o jsonpath='{.status.initContainerStatuses[*].state}'
```

Fix: Fix the Init Container command or image.

**Symptom: Main container not starting**

Cause: Init Container hasn't completed yet.

```bash
kubectl get pod <name> -o jsonpath='{.status.conditions[*].type}'
```

Fix: Wait for Init Container to complete, or fix it if it's failing.

## Interview Questions

**Q: What is an Init Container?**

A: A specialized container that runs before the main application containers in a Pod. It must exit successfully (code 0) before the main containers are started.

**Q: If an Init Container fails, what happens to the main application container?**

A: It is never created. The main app cannot start until all Init Containers exit successfully (code 0). The Pod will restart and retry the Init Container.

**Q: How do you pass data from an Init Container to the main app container?**

A: I mount a shared volume (like `emptyDir`) in both containers. The Init Container writes to it, the main container reads from it.

**Q: Do Init Containers run in parallel with each other?**

A: No. They run strictly sequentially. Init 1 must finish before Init 2 starts.

**Q: You need your application to wait for a PostgreSQL database to be up before it starts. How would you implement this in Kubernetes?**

A: I would use an Init Container with a simple `while` loop and `nc` (netcat) or `pg_isready` to poll the database service. Once the database is reachable, the script exits 0, and the main application container starts.

**Q: Init Containers share the same network namespace as the main container. True or False?**

A: True.

**Q: You must specify `-c` when reading Init Container logs. True or False?**

A: True.

## Scenario Questions

**Scenario 1:** You need your app to download a configuration file from Git before starting. How do you implement this?

A: I would use an Init Container with a `git` image. The Init Container would clone the repository and write the configuration files to a shared `emptyDir` volume. The main container would mount the same volume and read the configuration files.

**Scenario 2:** Your Pod is stuck in `Init:CrashLoopBackOff`. How do you debug?

A: I would run `kubectl describe pod <name>` to see the Init Container status. Then I would run `kubectl logs <pod> -c <init-container-name>` to see the Init Container logs. The logs would show why the Init Container is failing.

**Scenario 3 (Mini Project - The DB Waiter):**

Create a Pod with a main nginx container. Add an Init Container that runs a `while` loop pinging the `kubernetes.default.svc` service on port 443. Only when the ping succeeds should the Init Container exit, allowing Nginx to start.

## Quiz

1. What is an Init Container?
   - A. A container that runs forever
   - B. A container that runs before the main app and must exit successfully
   - C. A container that runs in parallel with the main app
   - D. A container that runs after the main app

2. What happens if an Init Container fails?
   - A. The main app starts anyway
   - B. The Pod restarts and retries the Init Container
   - C. The Pod is deleted
   - D. The Init Container is skipped

3. How do Init Containers run?
   - A. In parallel
   - B. Sequentially
   - C. Randomly
   - D. Only one Init Container per Pod

4. What is `emptyDir`?
   - A. A permanent storage volume
   - B. A temporary volume that lives as long as the Pod
   - C. A network volume
   - D. A ConfigMap

5. How do you read Init Container logs?
   - A. `kubectl logs <pod>`
   - B. `kubectl logs <pod> -c <init-container-name>`
   - C. `kubectl logs <pod> --init`
   - D. `kubectl logs <pod> --previous`

Answers: 1-B, 2-B, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- Init Container = Setup script.
- Must exit 0.
- Main container waits.
- Share data via `emptyDir`.

Memory trick:

- **Init Container:** The stage crew setting up the props before the play.
- **Main Container:** The actors. They stay in their dressing rooms until the stage crew finishes and leaves.
- **`emptyDir` Volume:** A shared briefcase. The stage crew puts the script inside, and the actors read from it.

Key facts:

- Init = Setup.
- Must exit 0.
- Main waits.
- Share via `emptyDir`.
- Sequential execution.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl logs <pod> -c <init-container-name>` | Crucial: You must specify the init container name to see its logs |
| `kubectl get pod <name>` | Check if status is `Init:CrashLoopBackOff` or `Running` |

## References

- [Kubernetes Documentation: Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Kubernetes Documentation: Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [Kubernetes Documentation: EmptyDir Volumes](https://kubernetes.io/docs/concepts/storage/volumes/#emptydir)

## Related Lessons

- [Lesson 10 - Pods, ReplicaSets, and Deployments](lesson-10-pods-replicasets-and-deployments.md) - how Pods work.
- [Lesson 23 - ConfigMaps and Secrets](../06-configuration/lesson-23-configmaps-and-secrets.md) - injecting configuration.
- [Lesson 32 - Probes and Health Checks](../08-observability/lesson-32-probes-and-health-checks.md) - application health.

## Coming Next

Now that you understand Init Containers, the next lesson covers ConfigMaps and Secrets — how to inject configuration into Pods.
