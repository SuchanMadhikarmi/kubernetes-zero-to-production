---
title: Lesson 25 - Logging
module: 08 Observability
lesson: 25
status: Complete
tags: [kubernetes, observability, logging, stdout, stderr, kubectl-logs, multi-container, previous, centralized-logging]
---

# Lesson 31 - Logging

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

- Explain how Kubernetes captures container logs and where it stores them on the worker node.
- Read logs from a multi-container Pod using the `-c` flag.
- Retrieve logs from a crashed container using the `--previous` flag.
- Explain why production clusters use centralized logging (Fluent Bit, Loki) instead of `kubectl logs`.

## Prerequisites

- Completion of Lessons 1 through 18.
- A running kind cluster.
- kubectl installed and configured.

## Real-world Motivation

### The Missing Stack Trace

Imagine your Java application crashes due to a `NullPointerException`. The container exits, and the ReplicaSet instantly creates a new Pod to replace it. You, the On-Call engineer, run `kubectl logs <pod-name>` to see why it crashed. But all you see is "Spring Boot starting..." because you are looking at the logs of the brand new container. The actual error message was printed right before the old container died, and it is now gone forever.

### Why This Exists

In traditional environments, applications write logs to local files (`/var/log/app.log`). In Kubernetes, this is an anti-pattern because containers are ephemeral. Kubernetes enforces the Twelve-Factor App methodology, which states that applications should print their logs to standard output (`stdout`) and standard error (`stderr`), letting the platform handle the storage and routing of those logs.

### Real Company Examples

**Robinhood:** During the GameStop trading frenzy, Robinhood's apps generated massive log volumes. They used Fluent Bit as a DaemonSet to continuously read `/var/log/pods/` and ship logs to Loki. Engineers never used `kubectl logs` in production because it was too slow and only showed one Pod. They used Grafana to search millions of logs in milliseconds.

## Core Concepts

### Explain Like I'm 12

Imagine two kids (Containers) sharing a diary (Pod). When one kid writes in the diary, you have to ask, "Which kid's handwriting is this?" If a kid throws a tantrum and is sent to their room, a new kid takes their place. If you want to know what caused the tantrum, you have to ask to read the old diary, not the new one.

### Explain Like I'm a Junior Engineer

Applications running in containers should print their logs to `stdout` and `stderr`. The container runtime (containerd) captures this and saves it as JSON files on the node at `/var/log/pods/`. The kubelet manages this. When you run `kubectl logs`, you are asking the kubelet to read those files and send them to your terminal.

### Explain Technically

- The Container Runtime redirects the container's stdout/stderr to a JSON log file on the host.
- The path format is: `/var/log/pods/<namespace>_<pod-name>_<pod-uid>/<container-name>/<restart-count>.log`.
- `kubectl logs` sends a request to the API Server, which proxies it to the kubelet on the specific node via the LogHandler gRPC endpoint.
- The kubelet streams the file contents back.
- `kubectl logs --previous` simply tells the kubelet to read `<restart-count - 1>.log` instead of `<restart-count>.log`.

### How Kubernetes Implements It Internally

By default, containerd uses the `json-file` logging driver. Notice the `<restart-count>` in the filename. `kubectl logs` reads `0.log` (or the current count). `kubectl logs --previous` reads `-1.log` (or the previous count). If the file doesn't exist (e.g., the container was killed before it could flush its buffers), you get the `unable to retrieve container logs` error.

### Why Kubernetes Was Designed That Way

Kubernetes follows the Twelve-Factor App methodology. Logs are a stream, not a file. By capturing stdout/stderr, Kubernetes decouples the application from the logging infrastructure. The application doesn't need to know where logs go — the platform handles it.

## Architecture

```
[ App Container ]
      | (prints to stdout/stderr)
      v
[ Container Runtime (containerd) ] -> Writes to JSON files on Node
      |
      v
[ Node Filesystem: /var/log/pods/ ]
      |
      v (Kubelet reads files)
[ Kubelet ] -> (gRPC to API Server)
      |
      v
[ kubectl logs <pod> ] (Proxied through API Server)
```

### Terminology

| Term | Definition |
|------|------------|
| stdout | Standard Output. The stream where applications print normal logs. |
| stderr | Standard Error. The stream where applications print error logs. |
| `--previous` (`-p`) | A kubectl logs flag to read logs from the previous instance of a crashed container. |
| Centralized Logging | A production setup where logs from all nodes are shipped to a central database (e.g., Loki, ElasticSearch). |
| Fluent Bit / Promtail | Log forwarders typically run as DaemonSets to read `/var/log/pods/` and ship logs to a central server. |

### How It Works Internally

1. The application writes `print("Starting server")` to stdout.
2. The container runtime catches this output and appends it as a JSON line to `/var/log/pods/default/my-app_abc/app/0.log`.
3. The user runs `kubectl logs my-app`.
4. The API Server receives the request and identifies which node the Pod is running on.
5. The API Server sends a gRPC request to the kubelet on that node.
6. The kubelet opens the `0.log` file and streams the JSON lines back.
7. `kubectl` formats the JSON lines into plain text and prints them to the user's terminal.

### Step-by-Step Workflow

1. Developer writes an app that prints to stdout.
2. Pod is scheduled to a node.
3. Container runtime starts the container and creates the `0.log` file.
4. App prints logs.
5. User runs `kubectl logs <pod>`.
6. Kubelet reads `0.log` and returns the data.
7. Container crashes (exit 1).
8. Kubelet restarts the container. A new `1.log` file is created.
9. User runs `kubectl logs <pod> --previous`.
10. Kubelet reads `0.log` and returns the data.

### Lifecycle

| State | Description |
|-------|-------------|
| Container Creation | The `0.log` file is created. |
| Running | Logs are appended to the file. |
| Rotation | If the file hits the size limit (e.g., 10MB), it is rotated (e.g., `0.log` -> `0.1.log`, `0.log` is created fresh). |
| Restart | The current log file is kept. A new file is created for the new container instance. |
| Deletion | When the Pod is deleted, the logs are garbage collected. |

### Feature Comparison

| Feature | `kubectl logs` | Centralized Logging (Loki/ELK) |
|---------|---------------|--------------------------------|
| Scope | Single Pod on a single Node | Entire Cluster |
| History | Only since last Pod restart (or rotation) | Months of history |
| Search | Manual grep | Powerful query languages (LogQL, Lucene) |
| Persistence | Lost when Pod is deleted | Stored permanently in object storage |

### Common Myths

| Myth | Fact |
|------|------|
| "Kubernetes stores my logs in etcd." | False. Kubernetes only stores the Pod configuration in etcd. The actual log text is stored as JSON files on the worker node's filesystem. |
| "If my app writes to `/var/log/app.log`, I can read it with `kubectl logs`." | False. `kubectl logs` only reads the stdout and stderr streams captured by the container runtime. |

## ASCII Diagrams

Mental Model: A Pod is a house with multiple rooms (containers). Each room has its own trash chute (stdout). The garbage truck (kubelet) collects the trash. If a room gets demolished and rebuilt (restart), the old trash is kept in the basement for a short time (`--previous`).

```
[ Pod: multi-app ]
  Container 1 (app)   ---> stdout: "App started" ---> /var/log/pods/.../app/0.log
  Container 2 (proxy) ---> stdout: "Proxy ready" ---> /var/log/pods/.../proxy/0.log

[ Container crashes! ]
  Container 1 (app)   ---> stdout: "FATAL ERROR" --> /var/log/pods/.../app/0.log (frozen)
  Container 1 (new)   ---> stdout: "App started" --> /var/log/pods/.../app/1.log (active)

(kubectl logs <pod> -c app --previous) -> reads 0.log
(kubectl logs <pod> -c app)           -> reads 1.log
```

## Hands-on

### Objective

Create a multi-container Pod, view logs for a specific container, crash the main container, and retrieve the crash logs using `--previous`.

### Step 1: Create the Multi-Container Pod

Create `multi-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: multi-app
spec:
  containers:
  - name: main-app
    image: busybox:latest
    command: ["sh", "-c", "echo 'Main app is running' && sleep 15 && echo 'FATAL: Database connection lost' && exit 1"]
  - name: sidecar-proxy
    image: busybox:latest
    command: ["sh", "-c", "echo 'Sidecar proxy started' && sleep 3600"]
```

**Field Explanation:**

- This Pod has two containers: `main-app` and `sidecar-proxy`.
- The `main-app` will sleep for 15 seconds, print an error, and then exit with code 1 (crash).

Apply it:

```bash
kubectl apply -f multi-pod.yaml
```

### Step 2: Investigate Multi-Container Logs

Wait about 20 seconds (so the main-app has time to crash and restart at least once), then try to run this:

```bash
kubectl logs multi-app
```

Expected output: It will throw an error: `error: a container name must be specified for pod multi-app, choose one of the following: [main-app sidecar-proxy] (or default to one)`.

Now, run it with the container flag:

```bash
kubectl logs multi-app -c sidecar-proxy
kubectl logs multi-app -c main-app
```

### Step 3: Investigate the Crash

Because the `main-app` exits with code 1, it will restart. Wait a few seconds, then run:

```bash
kubectl logs multi-app -c main-app
```

(You will just see "Main app is running" because this is the NEW container's logs. The fatal error is gone).

Now, run the command to get the previous logs:

```bash
kubectl logs multi-app -c main-app --previous
```

**Your Task:**

- What exact output did you see when you ran `kubectl logs multi-app -c main-app --previous`?
- Why was it necessary to use the `--previous` flag to see the error message?
- Based on the theory, where does the kubelet read this "previous" log data from on the worker node?

(Answer: 1. "Main app is running \n FATAL: Database connection lost". 2. Because the current container just restarted, so its log buffer is fresh. The error was printed right before the previous container died. 3. The `/var/log/pods/` directory, specifically the `0.log` file for that container, while the new container writes to `1.log`).

### Step 4: Cleanup

```bash
kubectl delete pod multi-app
```

## Commands

```bash
# Gets logs for a single-container pod
kubectl logs <pod>

# Gets logs for a specific container in a multi-container pod
kubectl logs <pod> -c <name>

# Gets logs of the crashed container before it restarted
kubectl logs <pod> --previous

# Tails the logs in real-time (like tail -f)
kubectl logs <pod> -f

# Shows logs with timestamps
kubectl logs <pod> --timestamps

# Shows only the last N lines
kubectl logs <pod> --tail=100

# Shows logs since a specific time
kubectl logs <pod> --since=10m
```

## YAML Explanation

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: multi-app
spec:
  containers:
  - name: main-app
    image: busybox:latest
    command: ["sh", "-c", "echo 'Main app is running' && sleep 15 && echo 'FATAL: Database connection lost' && exit 1"]
  - name: sidecar-proxy
    image: busybox:latest
    command: ["sh", "-c", "echo 'Sidecar proxy started' && sleep 3600"]
```

### Field-by-Field Explanation

- `containers[0].name: main-app`: The primary container that will crash.
- `containers[0].command`: Sleeps 15s, prints FATAL, then exits with code 1.
- `containers[1].name: sidecar-proxy`: A sidecar container that stays running.
- `containers[1].command`: Sleeps indefinitely.

## Production Notes

- **Always print to stdout/stderr:** Do not write to files inside the container. Kubernetes cannot read files, it can only read stdout.
- **Use Structured Logging:** Print logs in JSON format. This makes it much easier for tools like Loki or ElasticSearch to parse fields (e.g., `{"level": "error", "message": "DB down"}`).
- **Use Centralized Logging in Prod:** `kubectl logs` is for debugging. In production, deploy a logging stack (Loki + Promtail) so you can search logs across 100 nodes instantly without kubectl.

### When to Use / When NOT to Use

**Use `kubectl logs` when:**

- Active debugging during development.
- Quick sanity checks in production ("Did the app boot up?").

**Avoid `kubectl logs` when:**

- Trying to find a crash that happened 2 hours ago.
- Trying to aggregate error rates across 50 microservices.
- (Use Loki/ELK for these).

### Performance and Security Considerations

**Performance:** If an app prints 100MB of logs per second, it will fill up the node's disk. Always configure log rotation limits on the kubelet (`containerLogMaxSize` and `containerLogMaxFiles`).

**Security:** Do not print sensitive data (Passwords, PII, Credit Card numbers) to stdout. If you do, anyone with `kubectl logs` access can read them, and they will be stored in your centralized logging database unencrypted.

## Best Practices

- Always print to stdout/stderr.
- Use structured logging (JSON).
- Deploy centralized logging in production.
- Configure log rotation on the kubelet.
- Never print sensitive data to logs.
- Use `--previous` to debug crashes.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Writing to files | Java apps using log4j to write to `/var/log/app.log` | Reconfigure to print to stdout |
| Forgetting `-c` | Running `kubectl logs` on multi-container Pods | Always specify `-c <container-name>` |
| Ignoring `--previous` | Looking at current logs when debugging a crash | Use `--previous` to see the crash logs |
| Not using centralized logging | Using `kubectl logs` in production | Deploy Loki/ELK for production |

## Troubleshooting

**Symptom: `error: a container name must be specified`**

Cause: Pod has multiple containers.

```bash
kubectl get pod <name> -o jsonpath='{.spec.containers[*].name}'
```

Fix: Use `-c <container-name>` to specify which container.

**Symptom: `unable to retrieve container logs`**

Cause: Log file doesn't exist (container killed before flushing).

```bash
kubectl get pod <name> -o jsonpath='{.status.containerStatuses[*].restartCount}'
```

Fix: Use centralized logging (Loki/ELK) for production.

**Symptom: `--previous` shows no logs**

Cause: Container hasn't restarted yet.

```bash
kubectl get pod <name> -o jsonpath='{.status.containerStatuses[*].restartCount}'
```

Fix: Wait for a restart, or trigger one by killing the container.

## Interview Questions

**Q: Where does Kubernetes store container logs on the worker node?**

A: The container runtime stores them as JSON files in `/var/log/pods/`.

**Q: How do you read the logs of a container that has already crashed and restarted?**

A: Use `kubectl logs <pod> --previous` (or `-p`). This reads the log file of the terminated container instance.

**Q: Does `kubectl logs` work if the app writes to a file inside the container?**

A: No. `kubectl logs` only reads stdout/stderr. If an app writes to a file, I would either need to reconfigure the app to print to stdout, or run a sidecar container that tails the file and prints it to its own stdout.

**Q: An application pod keeps restarting every 2 minutes. You run `kubectl logs <pod>` but it just shows the application startup sequence. How do you find out why it's crashing?**

A: The current container's logs won't show the crash because it just started. I need to run `kubectl logs <pod> --previous`. This flag reads the log file of the terminated container, which will contain the stack trace or error it printed right before it died.

**Q: Does Kubernetes store container logs in the etcd database?**

A: No. They are stored on the node filesystem at `/var/log/pods/`.

## Scenario Questions

**Scenario 1:** Your app is crashing but `kubectl logs` shows only startup messages. How do you debug?

A: I would use `kubectl logs <pod> --previous` to see the logs of the crashed container. The crash reason is in the previous logs.

**Scenario 2:** You have a Pod with 3 containers. How do you see all logs?

A: I would use `kubectl logs <pod> -c <container-name>` for each container.

**Scenario 3 (Mini Project - The Sidecar Logger):**

Create a Pod with two containers: `app` and `logger`. The `app` container writes the current timestamp to a file in a shared emptyDir volume every 5 seconds. The `logger` container runs `tail -f /var/log/app.log` on that same shared volume, effectively printing the app's file logs to its own stdout. Run `kubectl logs <pod> -c logger` to verify you can see the timestamps.

## Quiz

1. Where does `kubectl logs` get its data from?
   - A. etcd
   - B. The node filesystem at `/var/log/pods/`
   - C. The API Server
   - D. Prometheus

2. What does the `-c` flag do in `kubectl logs`?
   - A. Shows logs in color
   - B. Specifies the container name in a multi-container Pod
   - C. Shows only error logs
   - D. Shows logs from all containers

3. What does `--previous` do?
   - A. Shows logs from the previous Pod
   - B. Shows logs from the previous container instance
   - C. Shows logs from 1 hour ago
   - D. Shows logs from the previous node

4. Why should applications print to stdout instead of files?
   - A. Files are slower
   - B. Kubernetes can only read stdout/stderr
   - C. Files are deleted immediately
   - D. stdout is encrypted

5. What is the main limitation of `kubectl logs`?
   - A. It's too slow
   - B. It only shows current/recent logs, no history
   - C. It can't read JSON
   - D. It requires root access

Answers: 1-B, 2-B, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- Logs = stdout/stderr.
- Stored on Node at `/var/log/pods/`.
- Multi-container: Must use `-c`.
- Crash debugging: Must use `--previous`.

Memory trick:

- **Pod:** A house with multiple rooms.
- **Containers:** The rooms. Each has its own trash chute (stdout).
- **`-c` flag:** Telling the garbage man which room's trash to empty.
- **`--previous` flag:** Asking to see the trash from the previous tenant who got evicted, not the new tenant who just moved in.

Key facts:

- Logs = stdout/stderr.
- Stored on Node filesystem.
- `-c` = Specify container.
- `--previous` = Crash logs.
- No history in etcd.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl logs <pod>` | Gets logs for a single-container pod |
| `kubectl logs <pod> -c <name>` | Gets logs for a specific container in a multi-container pod |
| `kubectl logs <pod> --previous` | Gets logs of the crashed container before it restarted |
| `kubectl logs <pod> -f` | Tails the logs in real-time (like `tail -f`) |

## References

- [Kubernetes Documentation: Logging Architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/)
- [Kubernetes Documentation: Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [Twelve-Factor App: Logs](https://12factor.net/logs)
- [Fluent Bit Documentation](https://docs.fluentbit.io/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)

## Related Lessons

- [Lesson 35 - Monitoring and Metrics](lesson-24-monitoring-and-metrics.md) - real-time CPU/Memory usage.
- [Lesson 36 - Probes and Health Checks](lesson-26-probes-and-health-checks.md) - application health.
- [Lesson 19 - ConfigMaps and Secrets](../06-configuration/lesson-20-configmaps-and-secrets.md) - injecting configuration.

## Coming Next

Now that you understand how to capture and query logs, the next lesson covers Packaging — how to manage Kubernetes applications with Helm and Kustomize.
