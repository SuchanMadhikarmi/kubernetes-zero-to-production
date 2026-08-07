---
title: Interview - Storage
module: 05 Storage
status: Complete
tags: [interview, storage, pv, pvc, storageclass, csi]
---

# Interview - Storage

## Beginner

**Q: What is a PersistentVolume?**

A: A cluster-scoped storage object representing a piece of storage (disk, NFS share, cloud volume) that outlives Pods.

**Q: What is a PersistentVolumeClaim?**

A: A request for storage, like a Pod requests CPU/memory. The PVC binds to a PV that satisfies its capacity and access mode, or to a dynamically provisioned PV from a StorageClass.

## Intermediate

**Q: What are the three access modes?**

A: ReadWriteOnce (RWO, single node read-write), ReadOnlyMany (ROX, many nodes read-only), and ReadWriteMany (RWX, many nodes read-write, e.g. NFS).

**Q: How does dynamic provisioning work?**

A: A PVC with `storageClassName` triggers the CSI provisioner defined in that class to create the volume and a matching PV automatically.

**Q: Why does a PVC stay Pending?**

A: No matching PV exists (capacity/access mode), the StorageClass is missing or can't provision, or `volumeBindingMode` (e.g. WaitForFirstConsumer) is waiting for a Pod. Check `kubectl describe pvc` and storage events.

## Advanced

Q: A PVC is stuck in Terminating. What is happening and the fix?

A: Usually a `kubernetes.io/pvc-protection` finalizer waiting for a consuming Pod to terminate, or a PV with `Retain` reclaim policy stuck on a cloud disk. Remove the finalizer as a last resort:

```bash
kubectl patch pvc <name> -p '{"metadata":{"finalizers":null}}'
```

## Scenario

Q: A StatefulSet database restarts and loses its data. What went wrong?

A: Likely no `volumeClaimTemplates` (stateless PVC), or the PVC was deleted (wrong reclaim policy). Each replica should mount its own persistent PVC; use `Retain` or backups for critical data.

## Related

- [Revision - Storage](../revision/storage.md)
- [Lesson 19 - Persistent Storage (PVs, PVCs, and StorageClasses)](../docs/05-storage/lesson-19-persistent-storage-pv-pvc-sc.md)

[Back to Interview Index](README.md)