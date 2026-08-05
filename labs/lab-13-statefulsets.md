# Lab 13 - StatefulSets

## Objective

Create a StatefulSet with a Headless Service, observe the strict ordering, and verify unique PVCs per Pod.

## Prerequisites

- Lesson 13 - StatefulSets.
- A running kind cluster.
- kubectl installed and configured.

### Quick Cluster Setup (kind)

```bash
kind create cluster --name learning
kubectl cluster-info --context kind-learning
```

## Steps

### 1. Create a Headless Service

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: db-svc
spec:
  clusterIP: None
  selector:
    app: db
  ports:
  - port: 80
EOF
```

### 2. Create the StatefulSet

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
spec:
  serviceName: db-svc
  replicas: 3
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: db
        image: busybox:latest
        command: ["sh", "-c", "echo 'Database started on \$(hostname)' && sleep 3600"]
  podManagementPolicy: OrderedReady
EOF
```

### 3. Observe Sequential Boot

```bash
kubectl get pods -l app=db --watch
```

Expected: Pods boot one by one: `db-0`, then `db-1`, then `db-2`.

### 4. Verify Stable DNS

```bash
kubectl run -it --rm dns-test --image=busybox -- nslookup db-0.db-svc
```

### 5. Verify Unique PVCs

```bash
kubectl get pvc
```

Expected: 3 PVCs: `data-db-0`, `data-db-1`, `data-db-2`.

### 6. Test Scaling Down

```bash
kubectl scale statefulset db --replicas=1
kubectl get pods -l app=db
kubectl get pvc
```

Expected: `db-2` and `db-1` are deleted. `db-0` remains. PVCs are NOT deleted.

### 7. Cleanup

```bash
kubectl delete statefulset db
kubectl delete svc db-svc
kubectl delete pvc data-db-0 data-db-1 data-db-2
kind delete cluster --name learning
```

## Verification

- StatefulSet creates Pods sequentially (0, then 1, then 2).
- Each Pod has a unique PVC.
- Scaling down deletes Pods in reverse order but preserves PVCs.
- Headless Service provides DNS resolution to specific Pods.

## Expected Output Snapshot

```text
$ kubectl get pods -l app=db
NAME    READY   STATUS    NODE
db-0    1/1     Running   kind-worker
db-1    1/1     Running   kind-worker
db-2    1/1     Running   kind-worker

$ kubectl get pvc
NAME           STATUS   VOLUME
data-db-0      Bound    pvc-abc
data-db-1      Bound    pvc-def
data-db-2      Bound    pvc-ghi
```

## Related

- Lesson file: [lesson-13-statefulsets.md](../docs/03-workloads/lesson-13-statefulsets.md)
