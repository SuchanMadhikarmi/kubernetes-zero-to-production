---
title: Lesson 42 - etcd Backup and Restore
module: 14 Certifications
lesson: 42
status: Complete
tags: [kubernetes, cka, etcd, etcdctl, backup, restore, snapshot, disaster-recovery, static-pod]
---

# Lesson 42 - etcd Backup and Restore

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

- Explain what etcd is and why it is the most critical component in Kubernetes.
- Use the `etcdctl` CLI tool to take a snapshot of the database.
- Explain the mandatory `ETCDCTL_API=3` environment variable.
- Execute the exact steps required to restore etcd from a backup (CKA exam critical).

## Prerequisites

- Completion of Lessons 1 through 41.
- A running kind cluster.
- kubectl installed and configured.
- Openness to serious Linux and cluster administration.

## Real-world Motivation

### From Lesson

The catastrophic database corruption: imagine a rogue script accidentally deletes the `kube-system` namespace. The API Server loses its configuration and the cluster goes dark. Or the etcd database itself becomes corrupted due to a disk failure. Without a backup, your entire production cluster is unrecoverable; you would have to rebuild it from scratch.

Why this exists: etcd is a distributed, reliable key-value store. Kubernetes stores its entire state (as JSON/YAML) in it. Because etcd is the single source of truth, it is the most critical component for disaster recovery. Taking regular etcd snapshots is your last line of defense against catastrophic cluster failure.

### Additional Production Knowledge

Backups are only "hard" to do until the first time they save you. The expensive lesson most teams learn is that the RTO (Recovery Time Objective) for an etcd restore is dominated by one thing: deciding and rehearsing the restore procedure. A cluster-level backup answers the question "what was my infrastructure like at time T", but it cannot answer "what was my application data like", so DR planning must pair etcd snapshots with a separate strategy for Persisted Volumes and database data. Rehearse the restore into a scratch cluster on a schedule, and record the exact commands, cert paths, and data-dir values so they are not rediscovered under pressure.

## Core Concepts

### From Lesson

- **etcd**: A consistent and highly-available key-value store used as Kubernetes' backing store for all cluster data.
- **etcdctl**: The command-line interface for interacting with etcd.
- **ETCDCTL_API=3**: An environment variable that must be set when using etcdctl. By default etcdctl uses the old v2 API, which does not support snapshots.
- **Static Pod**: In a kubeadm-provisioned cluster, etcd runs as a Static Pod on the control-plane node. Its manifest lives at `/etc/kubernetes/manifests/etcd.yaml`.

### Additional Production Knowledge

- **etcd versions**: etcd v3 is now the only supported API. Setting `ETCDCTL_API=3` is legacy behavior but still widely expected on the CKA because older etcdctl binaries default to v2. When your etcdctl is a v3-only build the variable is a no-op, but keep setting it to be safe.
- **`--endpoints`**: by default etcdctl talks to `127.0.0.1:2379`. On a control-plane node that is exactly where the local etcd Static Pod listens, so you usually do not need to override it.
- **`--cacert` vs `--cert`**: `--cacert` is the CA that verifies the server; `--cert/--key` are the client credentials presented to the server. In many kubeadm setups the `server.crt`/`server.key` pair is also used as the client identity for local admin tasks, but a dedicated peer or client pair is cleaner where available.

## Architecture

### From Lesson

etcd listens on port 2379 for client communication (API Server) and 2380 for peer communication (other etcd nodes). It uses strict mTLS.

```text
[ kubectl ] -> [ API Server ] <--(mTLS port 2379)--> [ etcd ]
        Shared etcd:
                 |
                 v
          [ /var/lib/etcd/data ]
```

### Additional Production Knowledge

In a single control-plane (like a kind node or a CKA single-node task) there is one etcd replica. In production, three (or five) replicas form a Raft quorum. Write Path: a `kubectl apply` lands in the API Server, which writes the object into etcd and waits for a quorum of etcd members to persist it before acknowledging the client. Read Path: the API Server reads from etcd (with caching), serving the warm watch streams and get requests. Losing quorum (a majority of members) freezes the entire cluster and stops accepts writes, which is exactly why an even number of replicas defeats the purpose.

## ASCII Diagrams

### From Lesson

```text
[ etcdctl (CLI) ] --(mTLS)--> [ etcd Database ]
        |
        v (Reads data directory)
[ /var/lib/etcd ]
        |
        v (Writes snapshot file)
[ /tmp/etcd-backup.db ]
```

### Additional Production Knowledge

```text
Backup:
  /etc/kubernetes/pki/etcd/{ca.crt, server.crt, server.key}
          |
          v
  ETCDCTL_API=3 etcdctl snapshot save backup.db --cacert .. --cert .. --key ..
          |
          v
  upload backup.db -> offsite object storage (S3/GCS) with retention

Restore:
  mv /etc/kubernetes/manifests/*.yaml /tmp/          (stop control plane)
  ETCDCTL_API=3 etcdctl snapshot restore backup.db --data-dir=/var/lib/etcd-restored
  edit etcd.yaml   hostPath  -> /var/lib/etcd-restored
  mv /tmp/*.yaml /etc/kubernetes/manifests/           (start control plane)
```

## Hands-on

### From Lesson

Goal: take a live snapshot of the etcd database running in a kind cluster and verify the backup is valid.

Step 1 - Find the etcd Pod:

```bash
kubectl get pods -n kube-system | grep etcd
```

Expected a Pod named `etcd-<control-plane>` (e.g. `etcd-prod-mindset-control-plane`).

Step 2 - Exec into the etcd container:

```bash
kubectl exec -it etcd-prod-mindset-control-plane -n kube-system -- sh
```

Step 3 - Take a snapshot. Specify the API version and TLS certificates:

```sh
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

Step 4 - Verify the snapshot:

```sh
ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db -w table
```

Look for `HASH`, `REVISION`, and `TOTAL KEYS`. This proves the backup is valid. Type `exit` to leave the Pod.

Step 5 - The restore procedure (mental exercise):

Full restores on a kind cluster can permanently break its bootstrap because the kubelet manages the Static Pod. The exam steps:

1. Stop the API Server: `mv /etc/kubernetes/manifests/*.yaml /tmp/`
2. Restore the backup to a new data dir:
   ```sh
   ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db \
     --data-dir=/var/lib/etcd-restored
   ```
3. Update the etcd Static Pod: edit `/etc/kubernetes/manifests/etcd.yaml` so its `hostPath` points at `/var/lib/etcd-restored`.
4. Restart components: `mv /tmp/*.yaml /etc/kubernetes/manifests/`
5. The kubelet starts etcd against the restored data, the API Server starts, and the cluster recovers.

## Commands

```bash
# Ubuntu control plane node: install the etcd client if not present
sudo apt-get install -y etcd-client

# Backup
ETCDCTL_API=3 etcdctl snapshot save etcd-backup.db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify
ETCDCTL_API=3 etcdctl snapshot status etcd-backup.db -w table

# Restore to a fresh directory
ETCDCTL_API=3 etcdctl snapshot restore etcd-backup.db --data-dir=/var/lib/etcd-restored

# Confirm etcd health (from inside or on the node)
ETCDCTL_API=3 etcdctl endpoint health \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

## YAML Explanation

```yaml
# excerpt from /etc/kubernetes/manifests/etcd.yaml
spec:
  hostNetwork: true
  containers:
  - name: etcd
    image: registry.k8s.io/etcd:3.5.x
    args:
    - --listen-client-urls=https://127.0.0.1:2379
    - --client-cert-auth=true
    volumeMounts:
    - name: etcd-credentials
      mountPath: /etc/kubernetes/pki/etcd
    - name: etcd-data
      mountPath: /var/lib/etcd
  volumes:
  - name: etcd-data
    hostPath:
      path: /var/lib/etcd
  - name: etcd-credentials
    hostPath:
      path: /etc/kubernetes/pki/etcd
```

The critical fields for a restore are under `etcd-data`:

- `volumeMounts[].mountPath: /var/lib/etcd` is inside the container.
- `volumes[].hostPath.path: /var/lib/etcd` is where data persists on the host node.

When restoring, the very common exam bug is forgetting to change that hostPath. If you restore into `/var/lib/etcd-restored` but leave the Static Pod mounted on `/var/lib/etcd`, etcd starts against the old, corrupted directory and your restore appears to "do nothing". Change the hostPath (and the `--data-dir` in the command if it is set) to point at the restored directory.

## Production Notes

### From Lesson

- Off-site backups: do not store the etcd backup on the same node as the cluster. Upload to S3/GCS.
- Automate: use a CronJob or systemd timer to take daily snapshots.
- Test restores: a backup you have not tested is worthless. Restore regularly into a staging cluster.

### Additional Production Knowledge

- Retention and encryption: set a retention window on object storage and enable at-rest encryption on the bucket; snapshots hold `Secrets`, and encryption at rest + strict ACLs reduce the blast radius of a stolen object key.
- Version compatibility: the restore binaries and the snapshot should come from the same minor etcd strip. Restoring against a wildly different etcd version can fail or corrupt. Prefer same patch series.
- RTO planning: record the `--data-dir` you name so the operator can clean a misdirected leftover directory.

## Best Practices

### From Lesson

- Set `ETCDCTL_API=3` for every `etcdctl` call for snapshots/restore.
- Store off-site and off-node.
- Take a snapshot before any major cluster upgrade or config change.
- Restore to a new data directory; never write into a live data dir.

### Additional Production Knowledge

- Use a dedicated, short-lived admin identity for `etcdctl` that is scoped and rotated.
- Keep snapshots versioned by timestamp and cluster name so you can select the correct restore point.
- Automate the snapshot side-by-side with the cluster's existing backup tooling, and verify the automation output by checking `snapshot status`.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Missing `ETCDCTL_API=3` | etcdctl defaults to v2 API | Always prefix the command with the env var. |
| Wrong cert paths | Using apiserver certs instead of etcd certs | Use the etcd-specific ones under `/etc/kubernetes/pki/etcd/`. |
| Restoring over a running etcd | Treating restore like apply | Stop control plane, restore to new dir, update manifest, restart. |
| Leaving `--data-dir`/hostPath misdirected | Forgot to edit etcd.yaml | Confirm the hostPath points to the restored dir. |

## Troubleshooting

### From Lesson

Scenario: `context deadline exceeded` on snapshot save.

1. Check etcd health: `kubectl get pods -n kube-system`, `endpoint health`.
2. Check certificates: wrong `--cacert/--cert/--key` fails the mTLS handshake.
3. Check network: is `2379` reachable from the host running etcdctl (firewall)?

### Additional Knowledge

- "apply request took too long" events during restore usually mean the snapshot came from a different cluster or a mismatched version; verify `snapshot status` metadata.
- If after restore `kubectl get nodes` shows stale/older data, you restored an old snapshot; that is expected behavior for a restore.

## Comparison Tables

| Feature | etcdctl Backup | Velero (Lesson 35) |
|---------|----------------|--------------------|
| What it backs up | Entire cluster metadata (etcd) | Specific namespaces/resources |
| Backs up PV data | No | Yes (snapshots or restic) |
| Granular restore | No (all or nothing) | Yes (specific namespaces) |
| Use case | Cluster-level DR | App-level DR / migration |

## When to Use / When Not to Use

Use etcdctl backup:

- Cluster-level disaster recovery.
- Before a major cluster upgrade.
- CKA exam.

Do not use etcdctl backup to:

- Back up application data (use database-native tools or Velero).
- Migrate an app to a different cluster (backups are tied to the cluster's certificates).

## Performance & Security Considerations

- Performance: a snapshot is fast; a restore requires stopping the API Server and writes are blocked during the window.
- Security: backup files contain the cluster's Secrets (base64). Protect with strict file permissions, encrypt at rest, and enable retention locking.

## Real Company Examples

### From Lesson

A major bank takes hourly etcd snapshots to AWS S3 with Object Lock to prevent ransomware deletion. A nightly job restores the snapshot into a staging cluster to verify validity. If an engineer deletes a critical namespace, they recover the entire cluster to the previous hour within 15 minutes.

## Common Myths

- Myth: "etcd backups save my application data (database rows)." False. etcd saves cluster configuration only, not PV data; use Velero for that.
- Myth: "You must run etcdctl from inside the etcd container." False. You can install etcdctl on the control-plane and point it at `localhost:2379` and the cert paths.

## Summary

- etcd is the consistent key-value store holding all Kubernetes cluster state.
- It runs as a Static Pod whose manifest is `/etc/kubernetes/manifests/etcd.yaml`, exposing port 2379 (client) with strict mTLS.
- Backup: `ETCDCTL_API=3 etcdctl snapshot save ...`.
- Restore: stop control plane, `snapshot restore` to new dir, update the etcd manifest, restart.
- Guaranteed question on the CKA exam.

## Revision Notes & Cheat Sheet

One-minute:

- etcd = cluster memory.
- Port 2379.
- `ETCDCTL_API=3` mandatory.
- Certs in `/etc/kubernetes/pki/etcd/`.
- Restore = stop API server → restore to new dir → update manifest → restart.

Memory trick:

- etcd = the cluster's diary.
- `ETCDCTL_API=3` = the magic open.
- `snapshot save` = photograph of the diary.
- `/etc/kubernetes/manifests/` = the ignition switch (files in = started, out = stopped).

```bash
# Backup
ETCDCTL_API=3 etcdctl snapshot save snapshot.db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify
ETCDCTL_API=3 etcdctl snapshot status snapshot.db -w table

# Restore
ETCDCTL_API=3 etcdctl snapshot restore snapshot.db --data-dir=/var/lib/etcd-restored
```

## Interview Preparation

### Beginner

Q: What port does etcd listen on?

A: 2379 for client traffic (API Server), 2380 for peer traffic between etcd nodes.

Q: What env var is mandatory when using etcdctl for snapshots?

A: `ETCDCTL_API=3`; otherwise the tool defaults to v2 and won't support snapshots.

### Intermediate

Q: Where are the etcd TLS certificates in a kubeadm cluster?

A: `/etc/kubernetes/pki/etcd/` — `ca.crt`, `server.crt`, `server.key`.

Q: How do you back up the cluster?

A: Snapshot the etcd database with etcdctl, passing the CA, cert, and key, then upload the file to an offsite bucket.

### Scenario

Q: etcd database is corrupted. Walk through restoring.

A: (1) Move static manifests out of `/etc/kubernetes/manifests/`. (2) `etcdctl snapshot restore snapshot.db --data-dir=/var/lib/etcd-restored`. (3) Update etcd.yaml hostPath to that dir. (4) Move manifests back. (5) The kubelet starts etcd and the cluster recovers.

### True / False

- "etcd backups include Persistent Volume data" → False.
- "You can restore an etcd snapshot directly into a running etcd" → False.

## Interview Questions

- What does etcd store, and why is it the source of truth for the cluster?
- How do you back up etcd on a control-plane node that runs etcd as a static Pod?
- Why must a restore use the same certificates and the correct snapshot version?
- What is the difference between backing up etcd and recreating the affected node?

## Scenario Questions

1. A disk failure wiped etcd data on a single-node control plane. Write the ordered steps to restore from your latest snapshot.
2. The team restored a day-old snapshot and now an app resource is missing. How do you confirm what was lost and communicate it to the app owner without panicking?

## Quiz

1. Which port does etcd use for client traffic?
   - A. 8080
   - B. 2379
   - C. 2380
   - D. 6443

2. Which env var do you set before taking an etcd snapshot?
   - A. `ETCDCTL_API=2`
   - B. `ETCDCTL_API=3`
   - C. `ETCDCTL_VERSION=3`
   - D. `KUBECONFIG=3`

3. Where are the etcd TLS certs in a kubeadm cluster?
   - A. `/var/lib/etcd/`
   - B. `/etc/kubernetes/pki/apiserver/`
   - C. `/etc/kubernetes/pki/etcd/`
   - D. `/etc/kubernetes/manifests/`

4. What is the correct order during an etcd restore?
   - A. restore → update manifest → move manifests out
   - B. move manifests out → restore to new dir → update hostPath → move manifests back
   - C. update hostPath → restore → restart kubelet
   - D. run kubectl apply → snapshot status

5. True or False: an etcd backup includes the data inside Persistent Volumes.
   - A. True
   - B. False

Answers: 1-B, 2-B, 3-C, 4-B, 5-B

## Revision

- etcd is the authoritative store for all cluster metadata (not app data).
- Single-node (kind) vs quorum (3/5 nodes) — odd number required.
- `ETCDCTL_API=3` + `/etc/kubernetes/pki/etcd` certs.
- Restore strictly: stop control plane → restore → new dir → edit hostPath → start.
- Off-site + automated + tested backups only real protection.

## Cheat Sheet

```bash
# Backup
ETCDCTL_API=3 etcdctl snapshot save snapshot.db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify
ETCDCTL_API=3 etcdctl snapshot status snapshot.db -w table

# Restore
ETCDCTL_API=3 etcdctl snapshot restore snapshot.db --data-dir=/var/lib/etcd-restored

# Manual resume (control plane)
mv /etc/kubernetes/manifests/*.yaml /tmp/
mv /tmp/*.yaml /etc/kubernetes/manifests/
```

## References

- [Kubernetes: Operating etcd clusters for Kubernetes](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)
- [etcd Documentation](https://etcd.io/docs/)
- [etcd Interacting with 3.0+ (etcdctl)](https://etcd.io/docs/v3.5/dev-internal/interacting_v3/)

## Related Lessons

- [Lesson 35 - Backups and Disaster Recovery with Velero](../12-production/lesson-35-backups-and-disaster-recovery-with-velero.md) - the app-level, PV-aware complement to cluster-level etcd backups.
- [Lesson 41 - Cluster Architecture and the Kubeconfig File](lesson-41-cluster-architecture-and-the-kubeconfig-file.md) - the control-plane nodes and the kubelet that starts etcd.
- [Lesson 29 - Node Pressure and Evictions](../13-troubleshooting/lesson-29-node-pressure-and-evictions.md) - control-plane health.
- [Module 02 - Architecture](../02-architecture/README.md) - where the control plane and etcd first appear.

## Coming Next

Lesson 43 continues the CKA core-domain series with control-plane components (API Server, Scheduler, Controller-Manager) and high-level cluster lifecycle operations: upgrades, node drain, and context management.