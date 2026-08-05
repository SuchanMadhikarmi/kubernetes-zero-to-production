# Lab 20 - Persistent Storage (PVs, PVCs, and StorageClasses)

## Objective

Create a PVC, write data to it, crash the Pod, and verify the data persisted. Understand dynamic provisioning in kind.

## Prerequisites

- Lesson 20 - Persistent Storage (PVs, PVCs, and StorageClasses).
- A running kind cluster.
- kubectl installed and configured.

### Quick Cluster Setup (kind)

```bash
kind create cluster --name learning
kubectl cluster-info --context kind-learning
```

## Steps

### 1. Check Available StorageClasses

```bash
kubectl get sc
```

Expected: You should see a `standard` StorageClass (kind's default).

### 2. Create the PVC

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: 1Gi
EOF
```

```bash
kubectl get pvc
```

Expected: PVC transitions from Pending to Bound.

### 3. Create a Pod That Writes Data

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: storage-app
spec:
  volumes:
  - name: data-volume
    persistentVolumeClaim:
      claimName: my-pvc
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "echo 'Important Database Data' > /data/file.txt && sleep 3600"]
    volumeMounts:
    - name: data-volume
      mountPath: /data
EOF
```

### 4. Verify the Data

```bash
kubectl exec storage-app -- cat /data/file.txt
```

Expected: `Important Database Data`

### 5. Simulate a Crash

```bash
kubectl delete pod storage-app
```

The Pod is gone. The data is "floating" on the PV.

### 6. Recover the Data

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: storage-app-read
spec:
  volumes:
  - name: data-volume
    persistentVolumeClaim:
      claimName: my-pvc
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "cat /data/file.txt && sleep 3600"]
    volumeMounts:
    - name: data-volume
      mountPath: /data
EOF
```

```bash
kubectl logs storage-app-read
```

Expected: `Important Database Data` (the data survived!)

### 7. Cleanup

```bash
kubectl delete pod storage-app-read
kubectl delete pvc my-pvc
kind delete cluster --name learning
```

## Verification

- PVC binds to a PV dynamically.
- Data written to the mounted volume persists after Pod deletion.
- A new Pod mounting the same PVC sees the previous data.

## Expected Output Snapshot

```text
$ kubectl get pvc
NAME     STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
my-pvc   Bound    pvc-abc123                                 1Gi        RWO            standard       30s

$ kubectl exec storage-app -- cat /data/file.txt
Important Database Data

$ kubectl logs storage-app-read
Important Database Data
```

## Related

- Lesson file: [lesson-20-persistent-storage-pv-pvc-sc.md](../docs/05-storage/lesson-20-persistent-storage-pv-pvc-sc.md)
