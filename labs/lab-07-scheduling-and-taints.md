# Lab 07 - Controlling Where Pods Run (Scheduling and Taints)

## Objective

Create a multi-node cluster, label a node, force a Pod to schedule there using nodeSelector, test Taints and Tolerations, and debug a broken schedule.

## Prerequisites

- Lesson 07 - Controlling Where Pods Run (Scheduling and Taints).
- A running kind cluster with multiple nodes.
- kubectl installed and configured.

### Quick Multi-Node Cluster Setup (kind)

```bash
kind delete cluster

cat <<EOF > kind-multi.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

kind create cluster --config kind-multi.yaml

kubectl get nodes
```

## Steps

### 1. Label a Node

```bash
kubectl label nodes kind-worker2 hardware=highmem
kubectl get nodes --show-labels
```

### 2. Schedule a Pod Using NodeSelector

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: memory-app
spec:
  nodeSelector:
    hardware: highmem
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "sleep 3600"]
EOF
```

```bash
kubectl get pod memory-app -o wide
```

Expected: The NODE column shows `kind-worker2`.

### 3. Test Taints and Tolerations

Taint the GPU node:

```bash
kubectl taint nodes kind-worker2 gpu=true:NoSchedule
```

Deploy a Pod without toleration:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: no-gpu-app
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "sleep 3600"]
EOF
```

```bash
kubectl get pod no-gpu-app -o wide
```

Expected: The Pod lands on `kind-worker` (not `kind-worker2`).

Deploy a Pod with toleration:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-app
spec:
  tolerations:
  - key: "gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "sleep 3600"]
EOF
```

```bash
kubectl get pod gpu-app -o wide
```

Expected: The Pod lands on `kind-worker2` (the tainted node).

### 4. Debug a Broken Schedule

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: broken-schedule
spec:
  nodeSelector:
    disktype: nvme
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "sleep 3600"]
EOF
```

```bash
kubectl get pod broken-schedule
kubectl describe pod broken-schedule
```

The Pod stays Pending. The Events section shows why.

### 5. Cleanup

```bash
kubectl delete pod memory-app no-gpu-app gpu-app broken-schedule
kubectl label nodes kind-worker2 hardware-
kubectl taint nodes kind-worker2 gpu=true:NoSchedule-
kind delete cluster
```

## Verification

- Pod with nodeSelector lands on the labeled node.
- Pod without toleration avoids the tainted node.
- Pod with toleration lands on the tainted node.
- Broken schedule Pod stays Pending with clear error message.

## Expected Output Snapshot

```text
$ kubectl get pod memory-app -o wide
NAME          READY   STATUS    NODE          
memory-app    1/1     Running   kind-worker2  

$ kubectl get pod no-gpu-app -o wide
NAME          READY   STATUS    NODE        
no-gpu-app    1/1     Running   kind-worker  

$ kubectl get pod gpu-app -o wide
NAME        READY   STATUS    NODE          
gpu-app     1/1     Running   kind-worker2  

$ kubectl get pod broken-schedule
NAME              READY   STATUS    PENDING
broken-schedule   0/1     Pending   
```

## Related

- Lesson file: [lesson-07-worker-node-architecture.md](../docs/02-architecture/lesson-07-worker-node-architecture.md)
