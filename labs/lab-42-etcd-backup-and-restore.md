# Lab 42 - etcd Backup and Restore

## Prerequisite

- Completion of [Lesson 42 - etcd Backup and Restore](../docs/14-certifications/lesson-42-etcd-backup-and-restore.md).
- A running kind cluster with an etcd Pod in `kube-system`.
- kubectl installed and configured.

## Objective

Take a live snapshot of the etcd database inside a kind control-plane container, verify its integrity, and rehearse the exact restore sequence you will use on the CKA exam.

## Estimated Time

15 minutes.

---

## Step 1: Find the etcd Pod

```bash
kubectl get pods -n kube-system | grep etcd
```

Expected: a Pod named `etcd-<cluster>-control-plane` (e.g. `etcd-prod-mindset-control-plane`) is Running.

## Step 2: Take a snapshot inside the etcd container

```bash
kubectl exec -it etcd-$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}') -n kube-system -- sh
```

Inside the shell, run:

```sh
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

Expected output:

```
{"level":"info","ts":... "caller":"snapshot/v3_snapshot.go":... "msg":"saved snapshot at path /tmp/etcd-backup.db"}
```

## Step 3: Verify the snapshot

```sh
ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db -w table
```

Expected: a table with `HASH`, `REVISION`, `TOTAL KEYS`, and `SIZE`. A valid hash proves the backup is not corrupted.

Exit the container:

```sh
exit
```

## Step 4: Copy the snapshot to the host

```bash
kubectl cp kube-system/etcd-$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}'):/tmp/etcd-backup.db /tmp/etcd-backup.db
ls -lh /tmp/etcd-backup.db
```

Expected: the snapshot file appears on your workstation, confirming you can move it off the node (the production equivalent of uploading it to S3/GCS).

## Step 5: Rehearse the restore (exam walkthrough)

On the CKA the restore sequence is:

1. Move static manifests out so the kubelet stops the control plane:
   ```bash
   mv /etc/kubernetes/manifests/*.yaml /tmp/
   ```
2. Restore to a new data directory:
   ```bash
   ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db --data-dir=/var/lib/etcd-restored
   ```
3. Edit the etcd manifest's `hostPath` to point at `/var/lib/etcd-restored`.
4. Move the manifests back:
   ```bash
   mv /tmp/*.yaml /etc/kubernetes/manifests/
   ```
5. Verify the cluster recovers.

Do not attempt the full restore on a kind cluster; it frequently breaks the node's bootstrap because the kubelet manages the Static Pod. Practice the command sequence here, and perform real restores in a dedicated staging VM or cloud cluster.

## Verification

```bash
kubectl get nodes
kubectl get pods -n kube-system | grep etcd
```

Expected: the cluster still answers and etcd is Running after your snapshot exercise.

## Cleanup

```bash
rm -f /tmp/etcd-backup.db
```

## Summary

You located the etcd Static Pod, took and verified a live snapshot with `ETCDCTL_API=3`, copied it off the node, and rehearsed the exact CKA restore sequence without destroying your kind cluster.