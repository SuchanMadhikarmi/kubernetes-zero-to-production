---
title: Revision - Fundamentals
module: 01 Fundamentals
status: Complete
tags: [revision, fundamentals, containers, namespaces, cgroups, kubectl]
---

# Revision - Fundamentals

## 1. The Mental Model

Kubernetes is a platform for running and orchestrating containers at scale. A container is not a virtual machine: it is a standard Linux process whose visibility is constrained by **namespaces** (what it can *see*) and whose resource usage is constrained by **cgroups** (what it can *use*). You describe the cluster's **desired state** in declarative YAML, and Kubernetes **controllers** continuously reconcile reality toward that state. `kubectl` is only a client that talks to the API Server, and **kubeconfig** tells kubectl which cluster, user, and namespace to contact. Everything in this module hangs together: containers are the workload, Pods are their smallest packaging unit, Kubernetes Namespaces organize them, cgroups protect the host, and kubectl plus kubeconfig are your interface to all of it.

## 2. Core Concepts

### Containers and Images

An **image** is a read-only template that contains your application code plus every dependency it needs: libraries, runtimes, and configuration. Images are built in **layers**; every instruction in the Dockerfile adds a layer, and layers are cached and shared across images, which is why pulling a new image is fast when you already have most of its layers. Images are stored in a **registry** (Docker Hub, quay.io, GHCR, ECR) and pulled by the runtime. A **container** is a running instance of an image: the runtime extracts the image filesystem and starts the process inside fresh namespaces and cgroups.

Kubernetes does not create containers itself. The **kubelet** on each worker node calls a container runtime through the **CRI** (Container Runtime Interface), a standard API that any runtime (containerd, CRI-O) can implement. This abstraction is why you can swap runtimes without rewriting any manifest.

### Linux Namespaces (isolation: the blindfold)

Namespaces are a kernel feature that partitions kernel resources so each process gets a private view of the system. A process inside a container believes it is alone on the machine.

| Namespace | Isolates |
|-----------|----------|
| PID | Process IDs: container sees only its own process tree, with itself as PID 1 |
| NET | Network stack: its own IP address, interfaces, and routing table |
| MNT | Mount points: its own filesystem view |
| UTS | Hostname and domain: it can set its own |
| IPC | Inter-process communication: own message queues and shared memory |
| USER | User and group IDs: own UID mapping |

Why this matters: without namespaces, two apps on one host would collide on ports, PIDs, and hostnames. With them, each app runs as if it owned the machine.

### cgroups (limitation: the leash)

**cgroups** (Control Groups) account for, limit, and isolate how much CPU, memory, and I/O a collection of processes can consume. In cgroup **v1** each resource has its own hierarchy (for example `/sys/fs/cgroup/memory/memory.limit_in_bytes`); in **v2** there is a single unified hierarchy under `/sys/fs/cgroup` with files such as `cpu.max` and `memory.max`. CPU limits are enforced by the **CFS** (Completely Fair Scheduler) through throttling. Memory limits are enforced by the memory cgroup: if a process exceeds its limit, the kernel's **OOM Killer** terminates it and the container exits with code 137 (`OOMKilled`). Why this matters: cgroups are the "noisy neighbor" defense that stops one leaked app from crashing the whole node, and the accounting they provide is what lets Kubernetes schedule workloads by **requests**.

### Pods

The **Pod** is the smallest deployable unit in Kubernetes. A Pod wraps one or more containers. Containers inside the same Pod share the same network namespace (one IP address), can talk to each other on `localhost`, and share volumes. The Pod, not the container, is the scheduling unit: the kubelet is told to run a Pod, and the Pod is what the scheduler places on a node. Pods are ephemeral by design; anything that must survive a restart belongs in a volume.

### Declarative vs Imperative and Controllers

The **imperative** model says "do this now" (`kubectl run nginx --image=nginx`). The **declarative** model says "this is the state I want" (`kubectl apply -f pod.yaml`). Kubernetes is built around the declarative model: the **desired state** is stored in etcd, and **controllers** (in the controller manager) run reconciliation loops that watch the API Server, compare actual state to desired state, and take actions to close the gap. A Deployment controller sees 2 replicas desired but 1 running and creates another ReplicaSet-owned Pod. You declare, Kubernetes converges.

### kubectl and kubeconfig

`kubectl` is the command-line client. Every kubectl command is an HTTP request (REST, JSON) sent to the **API Server**, which authenticates, authorizes, validates (including admission controllers), and stores state in etcd. **kubeconfig** is the file that tells kubectl where and as whom to talk. By default it lives at `~/.kube/config`. It contains:

- **clusters**: name, API Server URL, and the CA certificate to trust.
- **users**: name and credentials (client certificate, token, or username/password).
- **contexts**: a named tuple of `(cluster, user, namespace)`.
- **current-context**: which context is used when you do not specify one.

kubectl selects config by precedence: `--kubeconfig` flag, then the `KUBECONFIG` environment variable (which can name several files that get merged), then `~/.kube/config`. Switching namespaces is as simple as `kubectl config set-context --current --namespace=<ns>`.

### Kubernetes Namespaces (logical grouping)

Do not confuse kernel namespaces with Kubernetes **Namespaces**. A Kubernetes Namespace is a logical partition of the cluster: a scope for names (the same Pod name can exist in `dev` and `prod`) and a boundary for RBAC and quotas. Namespaced resources: Pods, Services, Deployments. **Cluster-scoped** resources (not namespaced): Nodes, PersistentVolumes, StorageClasses. Four namespaces always exist: `default`, `kube-system`, `kube-public`, `kube-node-lease`. A **ResourceQuota** caps the total CPU/memory requests and limits in a namespace, enforced synchronously by the API Server admission phase (exceeding it returns 403 Forbidden before the object is stored). A **LimitRange** sets defaults for individual Pods. Namespaces do **not** provide network isolation (use NetworkPolicy) and deleting a Namespace deletes everything inside it.

## 3. Key Commands

```bash
# Cluster and API
kubectl cluster-info
kubectl get nodes
kubectl api-resources                 # list resource types
kubectl explain pod.spec              # built-in docs

# Pods
kubectl get pods                      # in current namespace
kubectl get pods -A                   # all namespaces
kubectl get pods -o wide              # extra columns: IP, node
kubectl describe pod <name>           # details + events
kubectl logs <pod>                    # logs
kubectl logs <pod> --previous         # logs of previous crashed instance
kubectl exec -it <pod> -- /bin/sh     # shell into a pod
kubectl run nginx --image=nginx --dry-run=client -o yaml   # generate YAML
kubectl delete pod <name> --grace-period=0 --force

# Declarative CRUD
kubectl apply -f file.yaml
kubectl delete -f file.yaml
kubectl apply -f file.yaml --dry-run=client
kubectl diff -f file.yaml

# Kubernetes Namespaces
kubectl get ns
kubectl create namespace <name>
kubectl delete namespace <name>       # deletes everything inside
kubectl get all -n <ns>
kubectl describe quota -n <ns>        # usage vs hard limits

# kubeconfig, contexts, and current namespace
kubectl config view
kubectl config get-contexts
kubectl config current-context
kubectl config use-context <name>
kubectl config set-context --current --namespace=<ns>
kubectl config set-context <name> --namespace=<ns> --cluster=<c> --user=<u>

# Linux-level inspection (containers)
cat /proc/self/cgroup
cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null   # cgroup v1
docker run -it --memory="512m" --cpus="1" ubuntu:22.04 /bin/bash
docker ps -a
docker inspect <id> | grep -i oom
```

## 4. YAML Patterns

A minimal Pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: resource-demo
  namespace: default
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

Field meanings: `apiVersion: v1` selects the core API group for Pods and Namespaces; `kind: Pod` tells the API Server what object this is; `metadata.name` is the unique name within the namespace; `metadata.namespace` selects which Kubernetes Namespace the object lands in (when omitted it uses the current context's namespace). `spec.containers` is a list, because a Pod may hold several containers that share a network namespace and IP. `image` is the exact registry image reference; pin the tag, never `latest`. The `resources` block is where namespaces and cgroups meet Kubernetes: `requests` map to cgroup shares (`cpu.shares`) and are a scheduling *guarantee* (the scheduler only places the Pod where the sum of requests fits), while `limits` are hard ceilings enforced by CFS for CPU (throttling) and by the memory cgroup for memory (breach triggers the OOM Killer and exit code 137). Rule of thumb: requests protect you from noisy neighbors; limits protect your neighbors from you.

A Namespace:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-alpha
```

Field meanings: `kind: Namespace` is cluster-scoped, so there is no namespace field. `metadata.name` is the Namespace's name, which becomes the `metadata.namespace` value that every namespaced object inside it uses. Create it with `kubectl create namespace team-alpha` or `kubectl apply -f namespace.yaml`. Pair it with a ResourceQuota and, when helpful, a LimitRange to control what can be created inside it.

## 5. How It Fits Together

From Docker image to running Pod:

1. You build an image with a Dockerfile (layers of code plus dependencies) and push it to a registry.
2. You write a Pod manifest describing the desired image, resources, and namespace, and run `kubectl apply -f pod.yaml`.
3. The API Server validates the manifest, writes it to etcd, and (if a quota applies) checks admission, rejecting with 403 if the Namespace's ResourceQuota would be exceeded.
4. The Scheduler sees an unscheduled Pod and assigns it to a worker node with enough capacity for its `requests`.
5. The kubelet on that node receives the Pod assignment and calls the runtime via the CRI.
6. The runtime pulls the image and makes kernel calls (`clone()`/`unshare()`) that create the container's namespaces and cgroups.
7. The process starts inside its isolated, limited bubble; the kubelet reports status back to the API Server.

How kubectl talks to the cluster:

1. kubectl loads kubeconfig, picks the `current-context`, and resolves its `(cluster, user, namespace)` tuple.
2. kubectl sends an HTTP request to the cluster's API Server URL, authenticated as the context's user.
3. The API Server authenticates and authorizes (RBAC), runs admission controllers (validation, quotas), and stores the object in etcd.
4. Controllers in the controller manager watch etcd for changes and reconcile actual state toward the desired state.
5. When the desired state changes (a Pod is deleted), a controller creates a replacement; when it is stable, nothing happens. The loop is continuous.

## 6. Common Mistakes and Gotchas

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Treating containers as VMs | Confusing isolation models | Remember containers share the host kernel; a kernel panic kills every container on the host. |
| No memory limit | Oversight or fear of throttling | Always set `resources.limits.memory`; an unlimited leak can OOM the whole node. |
| Using `latest` tags | Speed of iteration | Pin tags such as `nginx:1.25.2-alpine`, promote by immutable digest in production. |
| Storing state in the container | Not understanding ephemerality | Use volumes or PersistentVolumes. |
| Expecting Namespaces to isolate network | Assuming "isolate" means everything | Namespaces are logical grouping; add a NetworkPolicy for a network boundary. |
| Running destructive commands in the wrong context | Forgetting which context/namespace is active | Verify `kubectl config current-context` before `delete namespace`. |
| Missing requests when a quota exists | Not reading the admission error | If a ResourceQuota is active, every Pod must specify `resources.requests`. |
| Confusing `requests` with `limits` | Similar field names | requests = scheduling guarantee; limits = hard ceiling. |
| Setting huge CPU limits "just in case" | Trying to avoid throttling | Measure real usage; aggressive CPU limits cause CFS throttling and latency spikes. |

## 7. Quick Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Pod stuck in `CrashLoopBackOff` | Process exits immediately (missing config, bad start) | `kubectl logs <pod> --previous`; check image and command. |
| Container `OOMKilled` (exit 137) | Exceeded the memory cgroup limit; OOM Killer fired | Raise `resources.limits.memory` or fix the memory leak; `kubectl describe pod`. |
| `Error from server (Forbidden): exceeded quota` | Pod requests exceed the Namespace ResourceQuota | `kubectl describe quota -n <ns>`; raise the quota or lower requests. |
| Pod not shown by `kubectl get pods` | Wrong context or namespace | `kubectl config current-context`; `kubectl get pods -n <ns>`; switch context. |
| `kubectl` talks to the wrong cluster | kubeconfig merge or current-context is wrong | `kubectl config view`; `kubectl config use-context <name>`. |
| Namespace deletion hangs | Resources still exist inside it | `kubectl get all -n <ns>`; delete resources first, then the Namespace. |
| High latency on a busy pod | CFS throttling from a strict CPU limit | Relax the CPU limit or increase requests. |
| Host is down but a pod seems fine | One app starved the node of memory/CPU | Check limits; pods without requests can be evicted under pressure. |

## 8. 30-Second Recap

- Container = Linux process + namespaces (isolation) + cgroups (limits). Not a VM: it shares the host kernel.
- Namespace types: PID, NET, MNT, UTS, IPC, USER. Blindfold = isolation.
- cgroups bound CPU, memory, I/O. CPU limits use CFS (throttling); memory limits use the OOM Killer (exit 137, `OOMKilled`). Leash = limitation.
- An image is a read-only, layered template in a registry; a container is a running instance of it.
- Kubernetes runs containers via kubelet -> CRI -> runtime (containerd, CRI-O) -> kernel.
- Pod = smallest deployable unit; one or more containers sharing a network namespace, IP, and volumes. Ephemeral.
- Declarative model: write desired state, apply it, and controllers reconcile reality toward it.
- kubectl -> API Server -> etcd -> controllers -> scheduler -> kubelet. It is just an HTTP client.
- kubeconfig holds clusters, users, contexts (cluster + user + namespace), and current-context; `KUBECONFIG` env var overrides the default file.
- Kubernetes Namespaces are logical partitions (name scoping, RBAC, quotas). Nodes, PVs, StorageClasses are cluster-scoped.
- ResourceQuota = namespace budget, enforced at admission (403). Namespaces do not isolate network. Deleting a Namespace deletes everything in it.
- requests protect you; limits protect your neighbors. Set both, pin image tags, and verify your context before destructive commands.

## Related Lessons

- [Lesson 1 - The Anatomy of a Container](../docs/01-fundamentals/lesson-01-anatomy-of-a-container.md)
- [Lesson 2 - Namespaces and Contexts](../docs/01-fundamentals/lesson-02-namespaces-and-contexts.md)

## Related Material

- [kubectl Cheat Sheet](../cheatsheets/kubectl-cheatsheet.md)
- [Interview - Fundamentals](../interview/fundamentals.md)

[Back to Revision Index](README.md)
