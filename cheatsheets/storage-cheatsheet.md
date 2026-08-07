---
title: Storage Cheat Sheet
topic: storage
status: Complete
tags: [cheatsheet, storage, volume, pv, pvc, storageclass, csi]
---

# Storage Cheat Sheet

## Storage Model

```text
Pod -> volume (emptyDir, configMap, PVC) 
PVC -> bound to a PV -> provisioned by a StorageClass -> CSI driver -> cloud/on-prem disk
```

- A **PersistentVolume (PV)** is cluster storage (the actual disk/NFS/cloud volume).
- A **PersistentVolumeClaim (PVC)** is a request for storage; it binds to a matching PV.
- A **StorageClass** defines provisioning rules (type, reclaim policy, CSI driver) and enables **dynamic provisioning**.

## Volume Types in the Pod

| Volume type | Lifecycle | Use |
|-------------|-----------|-----|
| `emptyDir` | Pod lifetime | scratch, caches, sidecar sharing |
| `hostPath` | Node lifetime | access a node's file; use carefully |
| `configMap` / `secret` | lives with the object | config/secrets injection |
| `projected` | object lifetime | combine several sources into one mount |
| `persistentVolumeClaim` | PVC | durable storage across restarts |

```yaml
spec:
  volumes:
  - name: cache
    emptyDir: {}
  - name: cfg
    configMap:
      name: app-config
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /data
    - name: cfg
      mountPath: /etc/app
```

## StorageClass and Dynamic Provisioning

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ssd
provisioner: kubernetes.io/aws-ebs      # cloud CSI provisioner
parameters:
  type: gp3
reclaimPolicy: Delete                   # Delete | Retain
volumeBindingMode: WaitForFirstConsumer # Immediate | WaitForFirstConsumer
allowVolumeExpansion: true
```

```bash
kubectl get storageclass
kubectl get sc -o yaml
kubectl get sc ssd -o template --template='{{.reclaimPolicy}}'
```

A PVC that specifies `storageClassName` requests that class. Omitted uses the default class in the cluster.

## PVC and PV Pairing

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
spec:
  accessModes:
  - ReadWriteOnce            # RWO, ROX, RWX
  storageClassName: ssd
  resources:
    requests:
      storage: 10Gi
```

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-logs
spec:
  capacity:
    storage: 10Gi
  accessModes: [ReadWrite]
  hostPath:                  # single-node demo only
    path: /mnt/data
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
```

```bash
kubectl get pv
kubectl get pvc -A
kubectl describe pvc <name>
```

Binding rules: a PV must have enough capacity and a matching access mode; the claim is bound only when both match. A PVC without a matching PV and without a dynamic provisioner stays `Pending`.

## Access Modes

| Access mode | Meaning |
|-------------|---------|
| `ReadWrite` | single node read-write (most common) |
| `ReadOnlyMany` (ROX) | many nodes read-only |
| `ReadWriteMany` (RWX) | many nodes read-write (e.g. NFS) |

A single PVC normally binds to a single node. For multi-node read-write use RWX with network FS (NFS, CephFS).

## Reclaim policy on PV

| ReclaimPolicy | On PVC deletion |
|----------------|----------------|
| `Delete` | PV and underlying storage are deleted |
| `Retain` | PV keeps the data; admin must release/delete it manually |

```bash
kubectl get pv -o custom-columns=NAME:.metadata.name,CAPACITY:.spec.capacity.storage,CLAIM:.spec.claimRef
kubectl patch pvc <name> -p '{"metadata":{"finalizers":null}}'   # force-remove stuck finalizer (last resort)
```

## CSI and lifecycle

- CSI (Container Storage Interface) drivers: `ebs.csi.aws.com`, `pd.csi.storage.gke.io`, `nfs.csi.k8s.io` (Linux), `file.csi.efs`.
- Mount propagation and multi-attach rules vary by driver.

### Expansion

```bash
kubectl edit pvc data-pvc   # increase spec.resources.requests.storage
```

Requires `allowVolumeExpansion: true` on the StorageClass; RWO volumes can expand.

### StatefulSet external storage each replica

StatefulSets use `volumeClaimTemplates` to create one PVC per replica (`data-db-0`, ...). See workload-cheatsheet.md.

## Troubleshooting quick commands

```bash
kubectl get pvc -A -o wide
kubectl get pv
kubectl describe pvc <name>   # PVC Pending / VolumeBindingMode issues
kubectl describe pv <name>
kubectl get sc -A
kubectl get events -A | grep -i volume
```

Common failure: PVC `Pending` - StorageClass missing, CSI not installed, or insufficient volume capacity from your provider.