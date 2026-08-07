---
title: Revision - Storage
module: 05 Storage
status: Complete
tags: [revision, storage, volume, pv, pvc, storageclass, csi]
---

# Revision - Storage

## Core Ideas

- **PV** (PersistentVolume) = cluster storage; **PVC** (PersistentVolumeClaim) = request for storage; **StorageClass** enables dynamic provisioning and defines reclaim policy.
- PVC binds to a matching PV (capacity + access mode). Without a matching PV and no StorageClass, it stays Pending.
- **CSI drivers** provision the actual disk/FS via the cloud provider.

## Access Modes

| Mode | Meaning |
|------|---------|
| ReadWriteOnce (RWO) | single node read-write (most common) |
| ReadOnlyMany (ROX) | many nodes read-only |
| ReadWriteMany (RWX) | many nodes read-write (NFS, CephFS) |

## Key Points

- `storageClassName` in a PVC selects a StorageClass (default class if omitted).
- Reclaim policy: `Delete` removes PV; `Retain` keeps data for manual cleanup.
- StatefulSets use `volumeClaimTemplates` to create one PVC per replica (`data-db-0`, ...).
- `allowVolumeExpansion: true` (on the class) enables resizing.
- A PVC stuck in `Terminating` usually has a `kubernetes.io/pvc-protection` finalizer or a stuck `Retain` PV/disk.

## Commands

```bash
kubectl get pv,pvc -A
kubectl describe pvc <name>
kubectl describe pv <name>
kubectl get storageclass -A
kubectl get events -A | grep -i volume
kubectl patch pvc <name> -p '{"metadata":{"finalizers":null}}'   # last resort
```

## Related Lessons

- [Lesson 20 - Persistent Storage (PV, PVC, StorageClass)](../docs/05-storage/lesson-20-persistent-storage-pv-pvc-sc.md)

## Related Material

- [Storage Cheat Sheet](../cheatsheets/storage-cheatsheet.md)
- [Interview - Storage](../interview/storage.md)

[Back to Revision Index](README.md)