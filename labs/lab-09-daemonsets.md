# Lab 9 - DaemonSets

## Objective

Deploy a DaemonSet to a multi-node cluster, verify one Pod per node, and test tolerations for control-plane nodes.

## Prerequisites

- Lesson 9 - DaemonSets.
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

### 1. Deploy a DaemonSet

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
  labels:
    app: log-agent
spec:
  selector:
    matchLabels:
      app: log-agent
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      containers:
      - name: agent
        image: busybox:latest
        command: ["sh", "-c", "echo 'Collecting logs...' && sleep 3600"]
EOF
```

### 2. Verify Placement

```bash
kubectl get pods -o wide -l app=log-agent
```

Expected: 2 Pods running (one on each worker node). No Pod on the control-plane node.

### 3. Check DaemonSet Status

```bash
kubectl get daemonset log-agent
```

Expected: `DESIRED 2`, `CURRENT 2`, `READY 2`.

### 4. Add Toleration for Control Plane

```bash
kubectl delete daemonset log-agent

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
  labels:
    app: log-agent
spec:
  selector:
    matchLabels:
      app: log-agent
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      tolerations:
      - key: "node-role.kubernetes.io/control-plane"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: agent
        image: busybox:latest
        command: ["sh", "-c", "echo 'Collecting logs...' && sleep 3600"]
EOF
```

```bash
kubectl get pods -o wide -l app=log-agent
```

Expected: 3 Pods running (one on each node, including control-plane).

### 5. Cleanup

```bash
kubectl delete daemonset log-agent
kind delete cluster
```

## Verification

- DaemonSet creates one Pod per worker node.
- Control-plane node is skipped without toleration.
- With toleration, DaemonSet runs on all nodes.

## Expected Output Snapshot

```text
$ kubectl get pods -o wide -l app=log-agent
NAME            READY   STATUS    NODE          
log-agent-abc   1/1     Running   kind-worker   
log-agent-xyz   1/1     Running   kind-worker2  

$ kubectl get daemonset log-agent
NAME       DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
log-agent  2         2         2       2            2           <none>          30s
```

## Related

- Lesson file: [lesson-09-daemonsets.md](../docs/03-workloads/lesson-09-daemonsets.md)
