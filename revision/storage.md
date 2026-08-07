---
title: Revision - Storage
module: 05 Storage
status: Complete
tags: [revision, storage, volume, pv, pvc, storageclass, csi]
---

# Revision - Storage

## 1. The Mental Model

Containers are ephemeral: if a Pod dies, everything written inside its filesystem dies with it. To keep data alive across Pod restarts and rescheduling, Kubernetes decouples data from the Pod using three layers.

Think of it like renting a locker for your tent camp:

- **PV (PersistentVolume)** = the rented storage locker itself. It is a real disk that lives at the *cluster* level, independent of any Pod or node.
- **PVC (PersistentVolumeClaim)** = your rental contract. It is a *namespace-scoped request* that describes what you need (size + access mode), not the disk itself.
- **StorageClass** = the facility manager who goes out and *buys* a locker for you when you sign a contract. It makes provisioning automatic.

Flow: Pod -> mounts PVC -> PVC binds to a PV -> PV is backed by a real disk (provisioned either manually by an admin or dynamically by a StorageClass).

## 2. Core Concepts

### Volume types on a Pod

| Type | Lifecycle | Use case |
|------|-----------|----------|
| `emptyDir` | Tied to the Pod | Scratch space, caches, in-Pod sharing. Data gone when the Pod is removed. |
| `hostPath` | Tied to the node | Reading node files (rare in production). Not portable across nodes. |
| `configMap` / `secret` | Pod-applied files | Inject config/credentials as files into the container. |
| `persistentVolumeClaim` | Independent of Pod | Databases and any data that must survive restarts. |

`emptyDir`, `hostPath`, `configMap`, and `secret` volumes still die (or move) with the Pod. Nothing survives unless a PVC backs it.

### PersistentVolume (PV)

A cluster-level resource representing physical storage (EBS, GCE PD, NFS, local disk). It is created by an admin (static) or by a StorageClass/provisioner (dynamic). Has **access modes** and a **reclaim policy**.

### PV access modes

| Mode | Abbrev | Meaning | Typical backends |
|------|--------|---------|------------------|
| ReadWriteOnce | RWO | One node mounts it read-write | AWS EBS, GCE PD, Azure Disk |
| ReadOnlyMany | ROX | Many nodes mount it read-only | NFS, CephFS |
| ReadWriteMany | RWX | Many nodes mount read-write | NFS, AWS EFS, CephFS |
| ReadWriteOncePod | RWOP | One Pod only | CSI (beta) |

The access mode you request limits which containers can attach the volume. **Claim:** a PV does not "sync across nodes." A standard RWO disk attaches to one node at a time.

### PersistentVolumeClaim (PVC)

- A namespace-scoped request for storage. It specifies `accessModes` and a `resources.requests.storage` size.
- Kubernetes matches a PVC to a PV of **>= capacity** and **compatible access modes**.
- If a PV matches and no StorageClass is set, the PVC binds to that existing PV (**static** binding).
- If a `storageClassName` is set and matches a StorageClass, the class dynamically provisions a PV and binds it (**dynamic** binding).

### Claim lifecycle states

| State | Meaning |
|-------|---------|
| `Pending` | PVC exists but no PV is bound yet (waiting for a static PV or a provisioner). |
| `Bound` | A PV is bound to the PVC; the volume is available to a Pod. |
| `Lost` | The PV backing a Bound PVC is missing/deleted. |
| `Terminating` | PVC stuck because of a finalizer (`kubernetes.io/pvc-protection`) or a Retain-held disk. |

### StorageClass (dynamic provisioning)

A StorageClass tells Kubernetes *how* to create a PV from a claim. It has three defining fields:

| Field | Purpose | Values |
|-------|---------|--------|
| `provisioner` | Which CSI/driver creates the volume | e.g. `kubernetes.io/aws-ebs`, `kubernetes.io/gce-pd` |
| `reclaimPolicy` | What happens to the PV when the PVC is deleted | `Delete` (default) or `Retain` |
| `volumeBindingMode` | When to bind/provision the volume | `Immediate` or `WaitForFirstConsumer` |

plus `parameters` (disk type, IOPS, etc.) and `allowVolumeExpansion` (enable resizing).

### Reclaim policies

- `Delete`: deleting the PVC also destroys the underlying cloud disk. Data is lost.
- `Retain`: deleting the PVC leaves the PV and disk behind for manual cleanup or recovery.
- `Recycle`: deprecated legacy behavior.

### Bound / mounted claims

A PVC is `Bound` to one PV. A Pod references the PVC via `spec.volumes[].persistentVolumeClaim.claimName`, and the container mounts it via `volumeMounts.mountPath`. Data written at that path lands on the PV disk, surviving Pod deletion.

## 3. Key Commands

```bash
kubectl get pv            # cluster-wide physical volumes
kubectl get pvc -A        # claims, namespaced
kubectl get sc            # StorageClasses
kubectl describe pvc <name>   # check events if Pending
kubectl describe pv <name>    # PV status and reclaim policy
kubectl get pvc <name> -o jsonpath='{.spec.volumeName}'   # bound PV name
kubectl get events -A | grep -i volume   # provisioning errors
kubectl patch pvc <pvc> -p '{"metadata":{"finalizers":null}}'   # last-resort unstuck
```

## 4. YAML Patterns

A full flow: StorageClass -> PVC -> PV (static, when no SC matches) + a Pod that mounts the PVC.

```yaml
apiVersion: v1
kind: PersistentVolume       # static alternative to dynamic provisioning
metadata:
  name: manual-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ssd
  hostPath:                  # local, for single-node demo clusters only
    path: /mnt/data
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ssd
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp3
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: ssd
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: storage-app
spec:
  volumes:
  - name: data-volume
    persistentVolumeClaim:
      claimName: data-pvc
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "echo data > /data/file && sleep 3600"]
    volumeMounts:
    - name: data-volume
      mountPath: /data
```

### Field-by-field

- `capacity.storage: 10Gi` (PV): maximum storage the volume exposes. A PVC binds only if its `requests` is <= this.
- `accessModes`: must be compatible between PV and PVC (e.g. RWO on both).
- `persistentVolumeReclaimPolicy: Retain` (PV): preserves data when the PVC is deleted. Default `Delete` on dynamic PVs could destroy it.
- `storageClassName` on the PV and PVC (must match for binding). If a PVC omits it, it uses the default class.
- `provisioner`: which driver creates the volume; `parameters.type: gp3` is a disk tier.
- `reclaimPolicy: Delete`: deleting the PVC deletes the PV and the cloud disk.
- `volumeBindingMode: WaitForFirstConsumer`: binds from an actual node (helps topology/RWO).
- `allowVolumeExpansion: true`: permits `kubectl edit pvc`. Then the PV grows up to the class's limits.
- `volumes[].persistentVolumeClaim.claimName: data-pvc`: points the Pod at the claim.
- `volumeMounts[].mountPath: /data`: makes the PV visible as a directory inside the container.

## 5. How It Fits Together

### Static provisioning flow

1. Admin creates a PV (a disk, `Retain`, matching capacity+access mode). It is `Available`.
2. Developer creates a PVC requesting a size/access mode.
3. The persistent volume controller finds a matching free PV and sets it `Bound` to that PVC.
4. A Pod mounts the PVC via `claimName` and writes to `mountPath`.
5. When the PVC is deleted, the PV is released and follows its `reclaimPolicy`.

### Dynamic provisioning flow

1. Pod is scheduled onto a node (if `WaitForFirstConsumer`).
2. Developer creates a PVC with `storageClassName: ssd`.
3. The StorageClass controller (provisioner) calls the CSI driver -> cloud API `CreateVolume`.
4. A PV is created in Kubernetes and bound to the PVC; state becomes `Bound`.
5. The node's kubelet + CSI node plugin attach the disk, format it, and mount it.
6. The PVC is mounted into the Pod; data written at `/data` persists on the cloud disk.

```
[ Developer (app) ]
     | 1. PVC: 10Gi, RWO, storageClassName=ssd
     v
[ PVC ]                            [ StorageClass "ssd" ]
     | 2. provisioner                provisioner: kubernetes.io/aws-ebs
     |    -> CSI CreateVolume            reclaimPolicy: Delete
     v
[ PV (dynamic, 10Gi disk) ] <-------- binds
     |
     v
[ Pod -> volumeMounts /data ]-> writes to disk
```

The same idea online: Pod -> PVC -> StorageClass -> PV -> physical disk.

## 6. Common Mistakes and Gotchas

| Mistake | Why | Fix |
|---------|-----|-----|
| RWO + Deployment with replicas > 1 | Only one node can attach a RWO disk; other replicas hang `ContainerCreating`. | Use a RWX/ROX backend or a StatefulSet with `volumeClaimTemplates`. |
| Deleting a PVC to "clean up" without knowing the reclaim policy | Default `Delete` destroys the cloud disk and data. | Set `Retain` for critical volumes; back it up. |
| Believing a PV syncs across nodes | A PV is bound to one node at a time; data does not replicate. | Use RWX (NFS, EFS, CephFS) for shared file access. |
| A PVC with no matching PV and no StorageClass | No way to create a disk; state stays `Pending`. | Add a StorageClass or a matching static PV. |
| PVC stuck `Terminating` | A finalizer (`kubernetes.io/pvc-protection`) or a `Retain` PV still holds the disk. | Verify the PV/disk is released first; only then patch finalizers as a last resort. |
| PVC requests more than any PV provides | PV capacity < requested size. | Request less or grow the StorageClass/disk. |

## 7. Quick Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| PVC `Pending` | StorageClass missing/misttyped, or no PV/disk capacity. | `kubectl get sc`, `kubectl describe pvc`; correct `storageClassName` or provisioner. |
| Pod stuck `ContainerCreating` with attach/mount error | RWO conflict: PV already attached to another node, or cloud disk issue. | `kubectl describe pod` events + `kubectl describe pv`; check RWO usage and the node. |
| PVC `Lost` | The backing PV was deleted/removed. | Recreate/locate the PV, confirm a matching PV exists; inspect the disk (cloud/console/attach). |
| PVC `Terminating` | PV/PVC finalizer stuck; storage disk still exists. | Release the storage, then patch the finalizer as a last resort. |
| Data gone after deleting PVC | `Delete` reclaim policy destroyed the disk. | Use `Retain` for critical data; recover from cloud snapshots/backup (e.g. Velero). |

Always start with `kubectl describe pvc` and `kubectl get events -A` — they surface the real provisioning error (nonexistent class, quota, driver, RWO conflicts).

## 8. 30-Second Recap

- Compute is ephemeral: mount a PV/PVC to keep data.
- PV = the disk (cluster-level). PVC = the request (namespaced). SC = automatically buys disks (dynamic provisioning).
- Modes: RWO (one node), ROX (many read), RWX (many read/write, needs NFS/EFS).
- Reclaim: `Delete` (default, destroys the disk) vs `Retain` (keeps it), vs `Recycle` (legacy).
- `WaitForFirstConsumer` binds storage to the right node (`RWO-safe`).
- A PVC stuck `Pending` -> check the SC; a PVC `Lost`/`Terminating` -> trace the PV, its policy, and finalizers.
- Static provision (admin) vs dynamic (StorageClass + CSI). `Pod -> PVC -> StorageClass -> PV`.

## Related Lessons

- [Lesson 20 - Persistent Storage (PV, PVC, StorageClass)](../docs/05-storage/lesson-20-persistent-storage-pv-pvc-sc.md)

## Related Material

- [Storage Cheat Sheet](../cheatsheets/storage-cheatsheet.md)
- [Interview - Storage](../interview/storage.md)

[Back to Revision Index](README.md)