---
title: Lesson 20 - Persistent Storage (PVs, PVCs, and StorageClasses)
module: 05 Storage
lesson: 20
status: Complete
tags: [kubernetes, persistent-volumes, persistent-volume-claims, storage-classes, csi, dynamic-provisioning, storage]
---

# Lesson 20 - Persistent Storage (PVs, PVCs, and StorageClasses)

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

- Explain why container storage is ephemeral by default.
- Describe the difference between PersistentVolumes (PV), PersistentVolumeClaims (PVC), and StorageClasses (SC).
- Explain how Dynamic Provisioning works via CSI (Container Storage Interface) drivers.
- Attach a persistent disk to a Pod, crash the Pod, and prove the data survived.

## Prerequisites

- Completion of Lessons 1 through 5 (containers, Pods, Services, Ingress, ConfigMaps).
- A running Kubernetes cluster (see [Lesson 01](../01-fundamentals/lesson-01-anatomy-of-a-container.md) for kind setup instructions).
- kubectl installed and configured.

## Real-world Motivation

### The Database Wipe

Imagine you deploy a PostgreSQL database using a Kubernetes Deployment. A user signs up, and their profile is saved to the database file inside the container.

1. The node runs out of memory, and the database container is OOMKilled.
2. The ReplicaSet instantly creates a new Pod to replace it.
3. The new Pod starts up with a fresh, empty container filesystem.
4. The user tries to log in again. "User not found." All your data is gone.

### Why This Exists

Kubernetes was designed to run stateless workloads (like web servers) where data loss on restart is fine. To run stateful workloads (like databases, message queues, or file storage), Kubernetes needed a way to decouple the storage lifecycle from the Pod lifecycle.

PersistentVolumes allow a disk to exist independently in the cluster. When a Pod dies, the disk stays. When a new Pod is created, it simply re-attaches the existing disk.

### Real Company Examples

**PayPal:** PayPal runs hundreds of MySQL and Redis clusters on Kubernetes. They use a CSI driver to provision high-IOPS SSDs. When a Pod restarts, the CSI driver reattaches the exact same disk to the new node. The data persists, and the database recovers instantly without data loss.

## Core Concepts

### Explain Like I'm 12

Imagine your Pod is a camper sleeping in a tent (ephemeral storage). If the tent blows away, everything inside it is gone.

- A **PersistentVolume (PV)** is a rented storage locker at a facility.
- A **PersistentVolumeClaim (PVC)** is the contract you sign to rent a specific size locker.
- Even if your tent blows away, your stuff in the locker is safe. You can pitch a new tent tomorrow and go get your stuff from the locker.

### Explain Like I'm a Junior Engineer

By default, a container's filesystem is tied to the container's life. To save data, you create a PVC (a request for storage). Kubernetes matches your PVC to a PV (the actual disk). You mount that PV into your Pod at a specific path (e.g., `/data`). Now, data written to `/data` is saved on the PV disk, not inside the container.

### Explain Technically

- The kubelet mounts the PV into the container's filesystem namespace using the `mount` system call.
- For cloud disks (like AWS EBS), the CSI node plugin attaches the disk to the EC2 instance, formats it, and mounts it to the kubelet's directory.
- The PersistentVolumeController watches for new PVCs. It tries to find an existing PV that matches the PVC's size and access modes. If a StorageClass is defined, the controller triggers the CSI external-provisioner to create a new volume in the cloud.

### How Kubernetes Implements It Internally

When you create a PVC, it stays in a Pending state. The StorageClass controller sees it. It sends an API call to AWS to create an EBS volume. Once AWS confirms the volume is created, the StorageClass creates a PV object in Kubernetes and binds it to the PVC. The PV is no longer an empty request; it has a real disk backing it.

### Why Kubernetes Was Designed That Way

Kubernetes separates storage into three API objects to divide responsibilities between the Cluster Admin and the Developer. The admin manages StorageClasses and PVs. The developer just creates a PVC and mounts it. This abstraction means developers don't need to know which cloud provider they're on.

## Architecture

```
[ Developer (Application) ]
      |
      | 1. Creates a PVC (I need 5GB of storage)
      v
[ PVC (PersistentVolumeClaim) ] <--- Lives in a Namespace
      |
      | 2. StorageClass intercepts & provisions a disk
      v
[ StorageClass ] --> [ Cloud Provider (AWS EBS, GCE PD) ]
      |
      | 3. Disk is created and binds to a PV
      v
[ PV (PersistentVolume) ]      <--- Lives at Cluster Level
      |
      | 4. PV is mounted into the Pod
      v
[ Pod ] -> [ Container writes data to /data ]
```

### Terminology

| Term | Definition |
|------|------------|
| PV | PersistentVolume. A cluster-level resource representing a physical disk. |
| PVC | PersistentVolumeClaim. A namespace-level request for storage. |
| StorageClass | A template for dynamically provisioning PVs. |
| CSI | Container Storage Interface. The standard API Kubernetes uses to talk to cloud providers. |
| RWO | ReadWriteOnce. Disk can be attached to one node at a time. |
| ROX | ReadOnlyMany. Disk can be mounted read-only by many nodes. |
| RWX | ReadWriteMany. Disk can be attached to multiple nodes simultaneously. |
| ReclaimPolicy | Determines what happens to a PV when its PVC is deleted (Retain, Delete, Recycle). |

### How It Works Internally

1. Developer creates a PVC requesting 5GB with `storageClassName: standard`.
2. The StorageClass controller notices the PVC.
3. It calls the CSI driver (e.g., AWS EBS CSI driver).
4. The CSI driver calls the AWS API to create an EBS volume.
5. AWS creates the volume and returns the Volume ID.
6. The CSI driver creates a PV in Kubernetes and binds it to the PVC.
7. The Scheduler assigns the Pod to a node.
8. The kubelet on that node tells the CSI node plugin to attach the EBS disk to the EC2 instance.
9. The OS mounts the disk to a kubelet directory.
10. containerd bind-mounts that directory into the container at `/data`.

### Step-by-Step Workflow

1. Create a PVC YAML requesting 1GB.
2. Apply the PVC. It enters Pending state.
3. The StorageClass provisions a disk and binds it. PVC becomes Bound.
4. Create a Pod YAML that references the PVC in its volumes block.
5. Apply the Pod. The Pod mounts the volume.
6. Write data to the volume.
7. Delete the Pod. The PVC and PV remain intact.
8. Create a new Pod referencing the same PVC. The data is still there.

### Lifecycle

| State | Description |
|-------|-------------|
| Provisioning | PV is created (manually or dynamically via SC). |
| Binding | PVC claims the PV. |
| Using | Pod mounts the PVC. Data is read/written. |
| Reclaiming | When the PVC is deleted, the PV is either Retained, Recycled, or Deleted based on the `persistentVolumeReclaimPolicy`. |

### Volume Types Comparison

| Feature | emptyDir | hostPath | PersistentVolume (PV/PVC) |
|---------|----------|----------|---------------------------|
| Lifecycle | Tied to Pod | Tied to Node | Independent (Survives Pod/Node) |
| Use Case | Scratch space | Mounting node files | Databases, persistent app data |
| Cloud Cost | Free | Free | Costs money (Provisions a disk) |

### Access Modes Comparison

| Mode | Abbreviation | Description | Common Backends |
|------|--------------|-------------|-----------------|
| ReadWriteOnce | RWO | Mounted read-write by one node | AWS EBS, GCE PD, Azure Disk |
| ReadOnlyMany | ROX | Mounted read-only by many nodes | NFS, CephFS |
| ReadWriteMany | RWX | Mounted read-write by many nodes | NFS, AWS EFS, CephFS |

### Common Myths

| Myth | Fact |
|------|------|
| "PVs sync data across nodes." | Standard ReadWriteOnce PVs are attached to one node. If you want the same data on 10 nodes simultaneously, you must use ReadWriteMany (which requires a network filesystem like NFS or EFS). |
| "Deleting a PVC always deletes the data." | False. It depends on the ReclaimPolicy. With `Retain`, the underlying disk is preserved. |
| "You must manually create a PV before creating a PVC." | False. StorageClasses do it dynamically. |

## ASCII Diagrams

Mental Model: The PV is the physical warehouse. The PVC is your rental contract. The Pod is the worker who walks into the warehouse to store boxes.

```
[ Pod: database ]
  volumes:
  - name: data-volume
    persistentVolumeClaim:
      claimName: my-pvc
      |
      v (Bound by PVC)
[ PVC (PersistentVolumeClaim) ] (Requested 5GB)
      |
      v (StorageClass dynamically provisions)
[ StorageClass ] -> (CSI Driver) -> [ AWS EBS Disk ]
      |
      v (Binds to)
[ PV (PersistentVolume) ] (5GB Disk Attached)
```

### Dynamic Provisioning Flow

```
[ Developer ]
      | (Creates PVC: 5GB, RWO)
      v
[ PVC ] -> Pending
      |
      v
[ StorageClass Controller ]
      | (Sees PVC, calls CSI)
      v
[ CSI Driver ] -> [ AWS API: CreateVolume ]
      |
      v
[ AWS EBS Volume Created ]
      |
      v
[ PV Created in Kubernetes ]
      |
      v
[ PVC Bound to PV ]
      |
      v
[ Pod Mounts PVC ] -> Data persists
```

## Hands-on

### Objective

Use dynamic provisioning in kind to create a PVC, write data, crash the Pod, and verify the data persisted.

### Step 1: Create the PVC

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

Expected: The PVC transitions from Pending to Bound.

### Step 2: Create a Pod That Writes Data

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

```bash
kubectl exec storage-app -- cat /data/file.txt
```

Expected: `Important Database Data`

### Step 3: Simulate a Crash

```bash
kubectl delete pod storage-app
```

The Pod and container are completely gone. The data is "floating" on the PV.

### Step 4: Recover the Data

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

Expected: `Important Database Data` (the data survived the Pod crash!)

### Step 5: Cleanup

```bash
kubectl delete pod storage-app-read
kubectl delete pvc my-pvc
```

## Commands

```bash
# List PersistentVolumes (cluster-wide)
kubectl get pv

# List PersistentVolumeClaims (namespace-scoped)
kubectl get pvc

# List StorageClasses
kubectl get sc

# Describe a PVC (check events if Pending)
kubectl describe pvc my-pvc

# Describe a PV
kubectl describe pv <pv-name>

# Check which PV is bound to a PVC
kubectl get pvc my-pvc -o jsonpath='{.spec.volumeName}'

# Manually create a PV (rare in production)
kubectl create -f pv.yaml

# Delete a PVC
kubectl delete pvc my-pvc
```

## YAML Explanation

```yaml
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
```

### Field-by-Field Explanation

- `kind: PersistentVolumeClaim`: A request for storage.
- `spec.accessModes: ReadWriteOnce`: The disk can only be mounted on one node at a time.
- `spec.storageClassName: standard`: The name of the StorageClass to use for dynamic provisioning.
- `spec.resources.requests.storage: 1Gi`: The amount of storage requested.

### Pod Volume Reference

```yaml
spec:
  volumes:
  - name: data-volume
    persistentVolumeClaim:
      claimName: my-pvc
  containers:
  - name: app
    volumeMounts:
    - name: data-volume
      mountPath: /data
```

- `spec.volumes`: Defines the volumes available to the Pod.
- `persistentVolumeClaim.claimName`: Points to the PVC.
- `volumeMounts`: Tells the container where to mount the volume inside its filesystem.

## Production Notes

- **Use Retain for critical databases.** If someone accidentally deletes a PVC, the underlying cloud disk is preserved, allowing you to recover the data. `Delete` will destroy the cloud disk instantly.
- **StatefulSets over Deployments.** For databases, use StatefulSets with `volumeClaimTemplates`. It automatically creates a unique PVC for every replica, preventing data corruption.
- **Backups.** PVCs are not backups. Use tools like Velero to snapshot the PV to S3.
- **Encrypted disks.** PVs are not encrypted by default. In production, use encrypted disks (e.g., AWS EBS Encryption) via StorageClass parameters.
- **Monitor IOPS.** Cloud disks have IOPS limits. If your database is slow, you might need to provision a higher-tier disk (e.g., AWS io2 vs gp3).

### When to Use / When NOT to Use

**Use PersistentVolumes when:**

- Running databases (PostgreSQL, MongoDB).
- Running message queues (Kafka, RabbitMQ).
- Any application where user-generated data must survive a restart.

**Do NOT use PersistentVolumes when:**

- Running stateless web frontends. They don't write local data; they read from a database. Adding PVs just adds cost and complexity.

### Performance and Security Considerations

**Performance:** Cloud disks have IOPS limits. If your database is slow, you might need to provision a higher-tier disk (e.g., AWS io2 vs gp3).

**Security:** PVs are not encrypted by default. In production, use encrypted disks (e.g., AWS EBS Encryption) via StorageClass parameters.

## Best Practices

- Use `Retain` ReclaimPolicy for critical data.
- Use StatefulSets with `volumeClaimTemplates` for databases.
- Set up regular backups with Velero or similar tools.
- Use encrypted StorageClasses in production.
- Monitor disk IOPS and latency.
- Test disaster recovery procedures regularly.
- Use `ReadWriteMany` for shared storage needs.
- Set resource requests and limits on Pods using PVs.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Using ReadWriteOnce with Deployment (replicas > 1) | RWO disks attach to one node only | Use ReadWriteMany or StatefulSets |
| Deleting PVC to "clean up" | Not understanding ReclaimPolicy | Always verify ReclaimPolicy before deleting |
| Not setting ReclaimPolicy | Default is Delete | Explicitly set `Retain` for critical data |
| Assuming PVs sync across nodes | Misunderstanding access modes | Use RWX backends (NFS, EFS) for shared data |

## Troubleshooting

**Symptom: PVC stuck in Pending**

Cause: StorageClass doesn't exist, or cloud limits exceeded.

```bash
kubectl get sc
kubectl describe pvc my-pvc
```

Fix: Verify the StorageClass name matches. Check cloud provider limits.

**Symptom: Pod stuck in ContainerCreating with volume errors**

Cause: PV cannot be attached to the node (RWO conflict, or cloud disk issue).

```bash
kubectl describe pod <pod-name> | grep -A 5 Events
kubectl describe pv <pv-name>
```

Fix: Ensure the PV is not already attached to another node. Check cloud provider console for disk status.

**Symptom: Data lost after deleting PVC**

Cause: ReclaimPolicy is set to `Delete`.

Fix: In production, always set `Retain` on critical PVCs. For recovery, check if the cloud disk still exists in the cloud console.

## Interview Questions

**Q: What is the difference between a PV and a PVC?**

A: A PV is the actual physical storage resource in the cluster. A PVC is a user's request for storage. The PVC binds to the PV.

**Q: Why do we need Persistent Volumes?**

A: Container filesystems are ephemeral. If a container crashes, the data is lost. PVs decouple data from the Pod lifecycle, ensuring data persists across restarts.

**Q: What is dynamic provisioning?**

A: Instead of admins manually creating disks (PVs), a StorageClass automatically provisions cloud disks (EBS, Azure Disk) when a PVC is created, and binds them together.

**Q: You have a Deployment with 2 replicas, using a PVC with `accessModes: ReadWriteOnce`. The second Pod gets stuck in ContainerCreating. Why?**

A: ReadWriteOnce means the disk can only be attached to one node. If the Scheduler placed the two Pods on different nodes, the second node cannot attach the disk. To fix it, use ReadWriteMany (if the storage backend supports it) or use a StatefulSet.

**Q: What happens when you delete a PVC?**

A: It depends on the ReclaimPolicy. With `Delete`, the underlying cloud disk is destroyed. With `Retain`, the disk is preserved and can be recovered.

**Q: What is the difference between emptyDir and a PVC?**

A: `emptyDir` is temporary storage that lives as long as the Pod lives. A PVC is persistent storage that survives Pod restarts and deletions.

## Scenario Questions

**Scenario 1:** You deploy a PostgreSQL database using a Deployment with 3 replicas and a single PVC. The database crashes randomly. What is wrong?

A: A Deployment with 3 replicas means 3 Pods trying to mount the same RWO PVC. Only one can mount it. The others fail. Use a StatefulSet with `volumeClaimTemplates` to give each replica its own PVC.

**Scenario 2:** You need to share a configuration directory across multiple Pods. What access mode do you use?

A: Use ReadWriteMany (RWX) with a backend that supports it, like NFS, AWS EFS, or CephFS. RWO only allows one node to mount the disk.

**Scenario 3 (Mini Project - The Volume Expansion):**

Create a PVC requesting 1GB. Deploy a Pod using it. Edit the PVC to request 2GB: `kubectl edit pvc <name>`. Verify the PV expanded. (Note: kind's hostPath doesn't enforce strict quotas, but in AWS EKS, this would trigger the cloud to expand the disk).

## Quiz

1. What is a PersistentVolume?
   - A. A request for storage
   - B. A cluster-level resource representing a physical disk
   - C. A StorageClass
   - D. A container volume

2. What is the default ReclaimPolicy for dynamically provisioned PVs?
   - A. Retain
   - B. Delete
   - C. Recycle
   - D. Preserve

3. Which access mode allows mounting on multiple nodes simultaneously?
   - A. ReadWriteOnce
   - B. ReadOnlyMany
   - C. ReadWriteMany
   - D. ReadWriteOncePod

4. What happens when a PVC is created with a matching StorageClass?
   - A. The PVC stays Pending forever
   - B. The StorageClass dynamically provisions a PV
   - C. The developer must manually create a PV
   - D. The Pod fails to start

5. Why would a Pod get stuck in ContainerCreating with a PVC?
   - A. The PVC is too large
   - B. The PV is already attached to another node (RWO conflict)
   - C. The Pod doesn't have permissions
   - D. The container image is missing

Answers: 1-B, 2-B, 3-C, 4-B, 5-B.

## Revision

One-minute revision:

- Container storage is ephemeral. Data is lost on restart.
- PVs are physical disks. PVCs are requests for disks. StorageClasses buy the disks dynamically.
- By mounting a PVC into a Pod, data is persisted on the disk, surviving Pod crashes.
- In kind, the `standard` SC simulates this using hostPath directories.

Memory trick:

- PV: The physical USB drive.
- PVC: Your request form to borrow a USB drive.
- StorageClass: The IT guy who receives your request, goes to the store, buys the drive, and hands it to you.

Key facts:

- PV = Disk.
- PVC = Request for disk.
- SC = Buys the disk.
- ReadWriteOnce = 1 node only. ReadWriteMany = Many nodes.
- Deleting PVC with Delete policy destroys the data.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl get pv` | Lists cluster-wide disks |
| `kubectl get pvc` | Lists namespace-level claims |
| `kubectl get sc` | Lists StorageClasses |
| `kubectl describe pvc <name>` | Check events if PVC is Pending |
| `kubectl describe pv <name>` | Check PV details and status |
| `kubectl get pvc <name> -o jsonpath='{.spec.volumeName}'` | Find which PV is bound |

## References

- [Kubernetes Documentation: Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Kubernetes Documentation: Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Kubernetes Documentation: CSI Drivers](https://kubernetes.io/docs/concepts/storage/container-storage-interface/)
- [Kubernetes Documentation: Volume Snapshot](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)
- [Velero Documentation](https://velero.io/)

## Related Lessons

- [Lesson 01 - The Anatomy of a Container](../01-fundamentals/lesson-01-anatomy-of-a-container.md) - containers, namespaces, and cgroups.
- [Lesson 10 - Pods, ReplicaSets, and Deployments](../03-workloads/lesson-10-pods-replicasets-and-deployments.md) - how Pods work.
- [Lesson 13 - StatefulSets](../03-workloads/lesson-13-statefulsets.md) - for stateful workloads that need stable identity and storage.
- [Lesson 21 - Persistent Volumes and Claims Deep Dive](lesson-21-persistent-volumes-and-claims.md) - advanced PV/PVC topics.
- [Lesson 22 - Storage Classes and Dynamic Provisioning](lesson-22-storage-classes-and-dynamic-provisioning.md) - advanced StorageClass topics.

## Coming Next

Now that you understand the basics of persistent storage, the next lesson dives deeper into PersistentVolumes and PersistentVolumeClaims, covering manual provisioning, reclaim policies, and volume expansion.
