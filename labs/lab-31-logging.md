# Lab 31 - Logging

## Prerequisite

- Completion of [Lesson 31 - Logging](../docs/08-observability/lesson-31-logging.md).
- A running kind cluster.
- kubectl installed and configured.

## Objective

Create a multi-container Pod, view logs for a specific container, crash the main container, and retrieve the crash logs using `--previous`.

## Estimated Time

15 minutes.

---

## Step 1: Create the Multi-Container Pod

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

Apply it:

```bash
kubectl apply -f multi-pod.yaml
```

## Step 2: Investigate Multi-Container Logs

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

## Step 3: Investigate the Crash

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

## Step 4: Cleanup

```bash
kubectl delete pod multi-app
```

---

## What You Learned

- Applications must print logs to stdout or stderr.
- The container runtime captures this and saves it as JSON files on the node at `/var/log/pods/`.
- Multi-container Pods: If a Pod has multiple containers, you must specify `-c <container-name>`.
- `--previous` (`-p`): Retrieves the logs of the previous container instance before it restarted. Essential for finding crash root causes.

## Next Steps

Proceed to [Lesson 32 - Probes and Health Checks](../docs/08-observability/lesson-32-probes-and-health-checks.md) to learn about application health checks.

---

[Back to Labs](README.md)
