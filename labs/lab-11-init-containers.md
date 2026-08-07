# Lab 11 - Init Containers

## Prerequisite

- Completion of [Lesson 11 - Init Containers](../docs/03-workloads/lesson-11-init-containers.md).
- A running kind cluster.
- kubectl installed and configured.

## Objective

Create a Pod with an Init Container that generates an `index.html` file. The main Nginx container will then serve that file. Then, break the Init Container and observe the `Init:CrashLoopBackOff` state.

## Estimated Time

15 minutes.

---

## Step 1: Create the Init Pod

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

Apply it:

```bash
kubectl apply -f init-pod.yaml
```

## Step 2: Verify the Setup Worked

Wait for the Pod to be Running, then test it:

```bash
kubectl exec init-demo -c web-server -- cat /usr/share/nginx/html/index.html
```

Expected output: `Config loaded by Init Container!`

## Step 3: Break Things on Purpose

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

## Step 4: Investigate the Failure

Wait about 15 seconds, then run:

```bash
kubectl get pod broken-init
```

Expected output: The STATUS should be `Init:CrashLoopBackOff`.

Run `kubectl describe pod broken-init`. Look at the `Containers:` section. Notice that the `web-server` container isn't even listed yet!

**Your Task:**

- What is the exact STATUS of the `broken-init` pod?
- In the `kubectl describe` output, does the main `web-server` container exist yet?
- Based on the theory of the Pod lifecycle, why hasn't Nginx started?

(Answer: 1. `Init:CrashLoopBackOff`. 2. No, it does not exist. 3. The kubelet enforces a strict rule: the main containers cannot be created until ALL Init Containers have successfully exited with code 0. Because the Init Container exited with 1, the Pod restarted and is trying the Init Container again. Nginx is held hostage).

## Step 5: Cleanup

```bash
kubectl delete pod init-demo broken-init
```

---

## What You Learned

- Init Containers are specialized containers that run to completion before the main application container starts.
- They run sequentially. If Init Container 1 fails, the Pod restarts and tries again.
- The main application container is never created until all Init Containers exit with code 0.
- They share the same Pod namespaces (Network, IPC) and can share files using an `emptyDir` volume.

## Next Steps

Proceed to [Lesson 20 - ConfigMaps and Secrets](../docs/06-configuration/lesson-20-configmaps-and-secrets.md) to learn about injecting configuration into Pods.

---

[Back to Labs](README.md)
