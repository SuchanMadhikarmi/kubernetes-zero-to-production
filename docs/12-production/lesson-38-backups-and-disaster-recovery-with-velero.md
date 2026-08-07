---
title: Lesson 38 - Backups and Disaster Recovery with Velero
module: 12 Production
lesson: 38
status: Complete
tags: [kubernetes, velero, backup, restore, disaster-recovery, pv, restic, s3, production]
---

# Lesson 35 - Backups and Disaster Recovery with Velero

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

- Explain why Kubernetes backups are different from traditional server backups.
- Describe how Velero backs up cluster resources (YAML) and Persistent Volumes (data).
- Install Velero and configure a backup storage location.
- Perform a backup, simulate a catastrophic failure, and restore the cluster.

## Prerequisites

- Completion of Lessons 1 through 34.
- A running kind cluster.
- `kubectl` installed and configured.
- Understanding of Persistent Volumes and PVCs from Module 05.

## Real-world Motivation

### The Accidental Deletion

An engineer means to type `kubectl delete namespace dev`, but accidentally types `kubectl delete namespace prod`. In a traditional system, you might restore a server from a snapshot. But in Kubernetes, the state lives in etcd, and the data lives in Persistent Volumes attached to specific nodes. If the namespace is deleted, all its Deployments, Services, ConfigMaps, and PVCs vanish instantly. The application is completely offline.

### Why This Exists

Kubernetes needed a backup tool that understands Kubernetes objects. You cannot just copy files from a server; you need to export the YAML definitions from etcd and snapshot the cloud disks (like AWS EBS). Velero automates this. It takes a point-in-time snapshot of your cluster state and restores it to the same cluster (disaster recovery) or a completely new cluster (migration).

### Real Company Examples

**GitHub:** GitHub uses Velero for their AKS clusters. They schedule regular backups to Azure Blob Storage. In the event of a cluster failure or accidental deletion, they can restore the entire cluster state and data to a new AKS cluster in minutes.

## Core Concepts

### Explain Like I'm 12

Imagine you have a huge LEGO castle. It took weeks to build. If someone knocks it over, you would have to rebuild from scratch. Velero is like taking a photograph of your castle. If it gets knocked over, you can use the photograph to rebuild it exactly as it was, including all the tiny pieces inside.

### Explain Like I'm a Junior Engineer

Velero is a tool that backs up your Kubernetes cluster. It does not just copy files; it talks to the Kubernetes API Server to export all your Deployments, Services, and ConfigMaps as JSON files. It also talks to your cloud provider (AWS/GCP) to snapshot your Persistent Volumes. If something breaks, you can restore everything with one command.

### Explain Technically

- Velero runs as a Deployment inside the `velero` namespace.
- It uses Custom Resource Definitions (CRDs) for `Backup`, `Restore`, `Schedule`, and `BackupStorageLocation`.
- When a `Backup` CR is created, the Velero controller queries the Kubernetes API for the requested resources, serializes them to JSON, and uploads them to the configured object storage (S3).
- For Persistent Volumes, Velero uses cloud-native snapshots (via CSI drivers) or Restic/Kopia (file-level backups) to capture the actual data.

### How Kubernetes Implements It Internally

By using CRDs, Velero integrates natively with Kubernetes. A `Backup` is just another Kubernetes object stored in etcd. The Velero controller watches for new `Backup` objects and executes the backup logic when it sees one. This means you can manage backups with GitOps: deploy a `Schedule` YAML from Git, and Velero automatically starts backing up.

### Why Kubernetes Was Designed That Way

Kubernetes stores desired state in etcd and data in volumes. A backup tool must capture both, and the reconciliation pattern already exists for controllers. Velero reuses that pattern: backups are declarative objects reconciled by the Velero controller, so they integrate with RBAC, GitOps, and the rest of the Kubernetes tooling without custom glue.

## Architecture

Velero runs inside your cluster as a controller. It communicates with the Kubernetes API to export resources and with the cloud provider to snapshot volumes.

```
[ Developer: velero backup create my-backup ]
      |
      v
[ API Server ] -> [ etcd ] (Velero Controller reads YAML)
      |
      v
[ Velero Controller ]
      |
      +---> Exports resources to JSON
      +---> Snapshots PVs (via CSI / Cloud Provider)
      |
      v
[ Backup Storage Location ] (AWS S3, GCP GCS, Local)
```

### Terminology

| Term | Definition |
|------|------------|
| Velero | The open-source disaster recovery tool for Kubernetes. |
| Backup | A CRD representing a point-in-time capture of cluster resources. |
| Restore | A CRD representing the action of applying a Backup to the cluster. |
| Schedule | A CRD that creates Backups on a cron schedule. |
| BackupStorageLocation (BSL) | Tells Velero where to store the backup JSON files (for example, an S3 bucket). |
| VolumeSnapshotLocation | Tells Velero where to store cloud disk snapshots (for example, AWS EBS snapshots). |

### How It Works Internally

1. You create a `Backup` object pointing to a namespace.
2. The Velero controller notices the new object.
3. It queries the API Server for all resources in that namespace.
4. It serializes the resources to JSON.
5. It uploads the JSON tarball to the BackupStorageLocation (for example, S3).
6. If configured, it asks the CSI driver to snapshot the Persistent Volumes.
7. It updates the Backup status to `Completed`.

### Step-by-Step Workflow

1. Admin installs Velero and configures an S3 bucket.
2. Admin creates a `Backup` CR.
3. Velero exports YAML and snapshots volumes.
4. A namespace is accidentally deleted.
5. Admin creates a `Restore` CR pointing to the Backup.
6. Velero applies the YAML back to the cluster and reattaches the volume snapshots.
7. The application is recovered.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | A `Backup` CR is created. Velero executes the backup. |
| Completion | Backup status becomes `Completed`. Data is safely in object storage. |
| Restoration | A `Restore` CR is created. Velero applies the backup. |
| Deletion | A `Backup` CR is deleted. Velero deletes the data from storage per the retention policy. |

### Communication Patterns

| Communication | Mechanism | Example |
|---------------|-----------|---------|
| CLI -> API Server | Create Backup CR | `POST /apis/velero.io/v1/namespaces/velero/backups` |
| Velero controller -> API Server | Read cluster resources | `GET /api/v1/namespaces/<ns>/configmaps` |
| Velero controller -> Object Storage | Upload tarball | PutObject to S3 bucket |
| Velero controller -> CSI/cloud | Snapshot PV | `CreateSnapshot` on the volume |

### Common Myths

| Myth | Fact |
|------|------|
| "Velero backs up the container images." | False. Velero backs up the YAML, which references the image. If the image is deleted from the registry, Velero cannot restore it. |
| "Velero is a replacement for database backups." | False. A file-level snapshot may capture a database mid-write. Always use database-native tools (`pg_dump`) for application-level consistency. |

## ASCII Diagrams

Mental Model: Velero is a time machine.

- Backup: take a snapshot of the present.
- Restore: travel back to that point in time.

```text
[ Cluster State (etcd + PVs) ]
      |
      v (Velero Backup)
[ Object Storage (S3) ] (Stores JSON YAML + Volume Snapshots)
      |
      v (Velero Restore)
[ Same Cluster (or New Cluster) ]
```

## Hands-on

### Objective

Install Velero with a local storage provider, create a backup, simulate a disaster, and restore it.

### Step 1: Install the Velero CLI

```bash
wget https://github.com/vmware-tanzu/velero/releases/download/v1.11.1/velero-v1.11.1-linux-amd64.tar.gz
tar -xzf velero-v1.11.1-linux-amd64.tar.gz
sudo mv velero-v1.11.1-linux-amd64/velero /usr/local/bin/
velero version
```

### Step 2: Create Local Storage for Backups

In production you use S3. In kind, use a local directory and the MinIO S3-compatible API.

```bash
mkdir -p /tmp/velero-backups

cat <<EOF > /tmp/velero-credentials
[default]
aws_access_key_id = minio
aws_secret_access_key = minio123
EOF
```

### Step 3: Install Velero

```bash
velero install \
    --provider aws \
    --bucket velero-backups \
    --secret-file /tmp/velero-credentials \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://localhost:9000 \
    --plugins velero/velero-plugin-for-aws:v1.7.1 \
    --use-volume-snapshots=false \
    --use-restic
```

Explanation:

- `--provider aws`: Tells Velero to use the AWS S3 API.
- `--bucket velero-backups`: The bucket name.
- `--secret-file`: The credentials to access the bucket.
- `--backup-location-config`: Points to the local MinIO server.
- `--use-volume-snapshots=false`: Cloud disk snapshots do not work in kind.
- `--use-restic`: Uses Restic for file-level volume backups (works anywhere).

Wait for Velero to be ready:

```bash
kubectl wait --for=condition=available deployment/velero -n velero --timeout=5m
```

### Step 4: Create Test Data

```bash
kubectl create namespace backup-test
kubectl create configmap important-data \
    --from-literal=message="This is important data" \
    -n backup-test
```

### Step 5: Create a Backup

```bash
velero backup create my-backup --include-namespaces backup-test
```

Check the backup status:

```bash
velero backup describe my-backup --details
```

Wait until `Phase: Completed`.

### Step 6: Simulate a Disaster

```bash
kubectl delete namespace backup-test
kubectl get namespace backup-test
# Error: namespaces "backup-test" not found
```

### Step 7: Restore from Backup

```bash
velero restore create --from-backup my-backup
```

Check restore status:

```bash
velero restore describe my-backup
```

Verify everything is restored:

```bash
kubectl get namespace backup-test
kubectl get configmap important-data -n backup-test -o yaml
```

### Cleanup

```bash
velero backup delete my-backup
kubectl delete namespace backup-test velero
rm -rf /tmp/velero-backups /tmp/velero-credentials
```

## Commands

```bash
# Install Velero with a storage location
velero install --provider aws --bucket <bucket> ...

# Create an on-demand backup of one or more namespaces
velero backup create <name> --include-namespaces <ns>

# Show backup status and contents
velero backup describe <name> --details

# Restore from a backup
velero restore create --from-backup <name>

# Create a scheduled backup (example: 2 AM daily)
velero schedule create <name> --schedule="0 2 * * *"
```

## YAML Explanation

### A Scheduled Backup

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: nightly-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"
  template:
    includedNamespaces:
    - production
    ttl: 720h
```

### Field-by-Field Explanation

- `schedule`: a cron expression controlling when backups run.
- `template.includedNamespaces`: which namespaces to back up.
- `template.ttl`: how long to keep each backup before deleting it (for example, `720h` = 30 days).

### A Restore

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: my-restore
  namespace: velero
spec:
  backupName: my-backup
```

`backupName` selects the backup to restore. Velero applies the stored YAML back to the cluster.

## Production Notes

- Test your restores. A backup you have never restored is worthless. Restore into a staging cluster regularly to verify it works.
- Use S3 Object Lock (WORM) to prevent ransomware from deleting backups.
- Do not rely on etcd backups alone: `etcdctl snapshot save` only captures YAML, not Persistent Volume data. Velero does both.
- Use Schedules to back up automatically every night.
- Backing up PVs with Restic can take hours and consume node CPU/I/O; schedule backups during off-peak hours.
- The backup storage contains your secrets in plaintext JSON. Encrypt with KMS and lock down access.

### When to Use / When NOT to Use

**Use Velero when:**

- Disaster recovery for production clusters.
- Migrating applications between clusters (for example, on-prem to EKS).
- Backing up stateful applications before upgrades.

**Avoid Velero when:**

- Backing up application code (use Git).
- Backing up databases (use database-native tools like `pg_dump` or managed backups, which are more consistent).

### Performance and Security Considerations

**Performance:** Large PVs backed up with Restic can take hours and consume node CPU and I/O. Schedule during off-peak windows.

**Security:** The S3 bucket contains all cluster secrets in plaintext JSON. Encrypt it (KMS) and restrict access. Use Object Lock for ransomware protection.

## Best Practices

- Test restores into a staging cluster on a schedule.
- Use `Schedule` CRs instead of manual backups.
- Enable volume snapshots or Restic for stateful workloads.
- Encrypt and lock your backup storage.
- Keep the Velero namespace and its CRDs intact; they track your backup history.
- Combine Velero with application-native backups for consistency.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Not backing up PVs | YAML-only backups recreate an empty database | Enable volume snapshots or Restic |
| Deleting the Velero namespace | Velero loses its backup history (data stays in S3) | Protect the `velero` namespace |
| Cross-cloud restores | An AWS EBS snapshot cannot restore to GCE | Use Restic/Kopia for cross-cloud volume backups |
| Never testing restores | Backups are assumed correct | Regularly restore into staging |

## Troubleshooting

**Symptom: Backup stuck in `New` or `InProgress`**

Check the Velero Pods:

```bash
kubectl get pods -n velero
```

Is the Velero pod running?

Check the Velero logs:

```bash
kubectl logs -n velero deployment/velero
```

Look for errors connecting to S3 or permission issues.

**Symptom: Restore completes but volumes are empty**

The backup was YAML-only. Verify `--use-restic` or volume snapshots were enabled, then re-run the backup.

## Comparison Table

| Feature | etcd backup (etcdctl) | Velero |
|---------|-----------------------|--------|
| Backs up YAML | Yes (all of it) | Yes (filtered by namespace/label) |
| Backs up PV data | No | Yes (snapshots or Restic) |
| Cross-cluster restore | No (tied to etcd) | Yes (restore to a new cluster) |
| Granular restore | No (all or nothing) | Yes (specific namespaces) |

## Interview Questions

**Q: How do you back up a Kubernetes cluster?**

A: I use Velero. It backs up cluster resources (YAML) to an object store like S3 and snapshots Persistent Volumes, enabling granular restores of namespaces or full disaster recovery.

**Q: What is the difference between an etcd backup and a Velero backup?**

A: An etcd backup captures the entire cluster state (all YAML) but not Persistent Volume data. Velero backs up both YAML and PV data, supports granular restores, and allows cross-cluster migration.

**Q: How does Velero handle Persistent Volumes?**

A: It can use cloud-native snapshots (for example, AWS EBS via CSI) for fast block-level backups, or Restic/Kopia for file-level, cross-cloud backups.

**Q: If an engineer deletes a namespace accidentally, how do you restore it?**

A: Run `velero restore create --from-backup <latest> --include-namespaces <deleted-namespace>`. Velero recreates all Deployments, Services, and ConfigMaps from the backup.

**Q: True or False: Velero can restore a backup to a different cluster.**

A: True.

**Q: True or False: Velero automatically backs up container images.**

A: False. It backs up the YAML that references the images.

## Scenario Questions

**Scenario 1:** You must migrate 50 microservices from an on-prem cluster to EKS. How?

A: Install Velero on the EKS cluster pointing at the same S3 bucket as the on-prem cluster. Run a Velero backup on the on-prem cluster, then run a Velero restore on the EKS cluster. Velero recreates the YAML and reattaches volume data.

**Scenario 2 (Mini Project - The Scheduled Backup):**

1. Create a Velero `Schedule` that backs up the default namespace every 5 minutes.
2. Verify a new `Backup` object is created automatically after 5 minutes.
3. Delete a ConfigMap in the default namespace.
4. Restore from the latest scheduled backup and verify the ConfigMap returns.

## Quiz

1. What does Velero back up besides YAML resources?
   - A. Container images
   - B. Persistent Volume data
   - C. Node OS disks
   - D. Git repositories

2. What component tells Velero where to store backup files?
   - A. BackupStorageLocation
   - B. VolumeSnapshotLocation
   - C. StorageClass
   - D. Namespace

3. Which mechanism does Velero use for file-level PV backups?
   - A. Restic/Kopia
   - B. etcdctl
   - C. rsync
   - D. kubectl cp

4. What does a `Schedule` CR do?
   - A. Restores backups
   - B. Creates backups on a cron schedule
   - C. Deletes backups
   - D. Migrates clusters

5. True or False: etcd backups capture Persistent Volume data.
   - A. True
   - B. False

Answers: 1-B, 2-A, 3-A, 4-B, 5-B.

## Revision

One-minute revision:

- Velero = backups for Kubernetes.
- Backs up YAML to object storage.
- Backs up PVs via snapshots or Restic.
- `velero restore create --from-backup <name>`.

Memory trick:

- Velero = a time machine.
- Backup = a photograph of the present.
- Restore = traveling back to the time of the photograph.

Key facts:

- Velero uses CRDs: Backup, Restore, Schedule, BSL.
- It does not back up container images.
- It is not a substitute for database-native backups.
- Test your restores.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `velero install ...` | Installs Velero |
| `velero backup create <name> --include-namespaces <ns>` | Creates a backup |
| `velero backup describe <name>` | Shows backup status |
| `velero restore create --from-backup <name>` | Restores from a backup |
| `velero schedule create <name> --schedule="0 2 * * *"` | Creates a daily 2 AM backup |

## References

- [Velero Documentation](https://velero.io/docs/)
- [Velero GitHub Repository](https://github.com/vmware-tanzu/velero)
- [AWS EBS CSI Driver Snapshots](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)
- [Kubernetes Documentation: Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

## Related Lessons

- [Lesson 16 - Persistent Storage (PVs, PVCs, and StorageClasses)](../05-storage/lesson-19-persistent-storage-pv-pvc-sc.md) - the volumes Velero snapshots.
- [Lesson 18 - Cluster Upgrades and Maintenance (Cordon and Drain)](lesson-37-cluster-upgrades-and-maintenance.md) - planned node maintenance as a trigger for backups.
- [Lesson 34 - Operators in Practice (Managing Stateful Apps)](../11-operators/lesson-34-operators-in-practice.md) - the stateful apps you must back up.

## Coming Next

In the next lesson we cover production hardening and security best practices: network policies, secrets management, and the hardening checklist used to secure clusters before they serve real traffic.