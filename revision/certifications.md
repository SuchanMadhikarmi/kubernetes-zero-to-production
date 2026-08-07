---
title: Revision - Certifications and Capstone
module: 14 Certifications
status: Complete
tags: [revision, certifications, cka, ckad, cks, kubeconfig, etcd, capstone, interview, career]
---

# Revision - Certifications and Capstone

## 1. The Mental Model

Certifications exist to prove you can operate a cluster under pressure, not to test recall. Treat every exam task and every interview question as a **reconciliation loop**: compare Desired State against Actual State, act to close the gap, and verify.

The three-stage ladder:

- **CKA** (Certified Kubernetes Administrator): run the platform. Cluster administration, control plane, troubleshooting, etcd backup/restore, node lifecycle.
- **CKAD** (App Developer): write to the platform. Workloads, config, services; no cluster admin, no etcd.
- **CKS** (Security Specialist): harden the platform. RBAC, admission controllers, image security, Pod Security. Requires a current CKA.

For the career path, everything in the capstone is a business lever. Argo Rollouts reduces rollback time, the HPA lowers cost, Network Policies shrink compliance scope, GitOps makes every deployment a reversible commit. Hiring managers fund outcomes, not YAML.

## 2. Core Concepts

**Certification landscape**

| Exam | Focus | Requires |
|------|-------|----------|
| CKA | Cluster administration, control plane, etcd, troubleshooting, upgrades | None |
| CKAD | Application design, build, config, expose | None |
| CKS | Security hardening, RBAC, admission, image security | CKA |

Passing score is 66% with no per-section cutoff, so collect every easy point first.

**The reconciliation world-view** - every controller is the same pattern (watch, diff, act, repeat): ReplicaSet reconciles Pod count, HPA reconciles replicas to metrics, ArgoCD reconciles the cluster to Git, Argo Rollouts reconciles traffic weight to error rate.

**kubeconfig** - the stateless VIP pass at `~/.kube/config` that tells kubectl who you are (user), where to go (cluster), and which namespace to default to (context). Three sections:

- `clusters`: API server URL + CA.
- `users`: client cert/key, token, or exec plugin.
- `contexts`: binding of a user to a cluster, optional namespace.
- `current-context`: the single pointer read on every command.

**etcd** - the consistent, highly-available key-value store that holds ALL cluster metadata (not application data). Runs as a Static Pod whose manifest is `/etc/kubernetes/manifests/etcd.yaml`. Client traffic on `2379`, peer traffic on `2380`, strict mTLS.

## 3. Speed Tips and Must-Memorize Commands

Configure both files at the very start of the CKA exam, before reading questions.

```bash
# .bashrc additions
alias k='kubectl'
export do='--dry-run=client -o yaml'
export now='--force --grace-period 0'
source ~/.bashrc
```

```bash
# .vimrc additions (YAML hates tabs; use spaces/2)
set expandtab
set tabstop=2
set shiftwidth=2
set autoindent
set smartindent
set nu
```

**Imperative generators (never hand-type YAML):**

```bash
k create ns NAME
k run POD --image=nginx
k create deploy web --image=nginx --replicas=3 $do > deploy.yaml
k expose deploy web --port=80 --target-port=8080 --type=NodePort $do > svc.yaml
k create cm my-cm --from-literal=DB=postgres $do > cm.yaml
k create secret generic my-secret --from-literal=password=pass $do > sec.yaml
k create sa my-sa
k create role read-pods --verb=get,list,watch --resource=pods
k create rolebinding my-rb --role=read-pods --serviceaccount=default:my-sa
```

**Context switching (never skip):**

```bash
kubectl config get-contexts
kubectl config use-context cluster2
kubectl config current-context
```

**etcd backup and verify:**

```bash
ETCDCTL_API=3 etcdctl snapshot save snapshot.db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
ETCDCTL_API=3 etcdctl snapshot status snapshot.db -w table
```

**Must-memorize facts:** etcd client port 2379; API server 6443; `node-monitor-grace-period` 40s; `pod-eviction-timeout` 5m; QoS Guaranteed = requests == limits on all containers; Cilium = eBPF, no iptables; `helm history <name>` shows release history.

## 4. Key YAML/Config patterns (kubeconfig YAML, etcd command) with explanation

**Kubeconfig YAML**

```yaml
apiVersion: v1
kind: Config
clusters:
- name: prod-cluster
  cluster:
    certificate-authority: /path/to/ca.crt   # verifies the API server identity
    server: https://10.0.0.1:6443
users:
- name: admin
  user:
    client-certificate: /path/to/cert.crt     # proves who you are to the server
    client-key: /path/to/cert.key
contexts:
- name: prod-admin
  context:
    cluster: prod-cluster
    user: admin
    namespace: default
current-context: prod-admin
```

- `cluster.server` is the address; point it wrong and you get a connection refused/timeout.
- `context.namespace` is the default namespace for that binding (overrides the `-n` requirement).
- `current-context` is the single pointer read on every command - the reason "wrong file/context" means working on the wrong cluster.
- Merge files with `KUBECONFIG=file1:file2 kubectl config view --raw > merged`; the `--kubeconfig` flag or `KUBECONFIG` env overrides the default.

**etcd restore to a new data directory**

```bash
# 1. stop the control plane (kubelet sees no static manifests, stops the pods)
mv /etc/kubernetes/manifests/*.yaml /tmp/
# 2. restore snapshot into a fresh directory, never the live one
ETCDCTL_API=3 etcdctl snapshot restore snapshot.db --data-dir=/var/lib/etcd-restored
# 3. edit /etc/kubernetes/manifests/etcd.yaml so the data volume hostPath points to /var/lib/etcd-restored
# 4. move the manifests back to start the control plane again
mv /tmp/*.yaml /etc/kubernetes/manifests/
# 5. kubelet starts etcd on the restored dir and the cluster recovers
```

The magic trick is the `hostPath` in `etcd.yaml`: `volumes[].etcd-data.hostPath.path` must point at the restored directory, or etcd boots against the old corrupted data and the restore appears to do nothing. Also requires the mandatory `ETCDCTL_API=3`, otherwise etcdctl defaults to the v2 API without snapshot support. Cert paths come from `/etc/kubernetes/pki/etcd/` (client + CA, not the api-server certs).

## 5. How It Fits Together (exam workflow; etcd restore flow)

**Exam workflow**

```text
Switch context -> generate base YAML with $do -> edit the delta only in vim
   -> kubectl apply -f -> verify with kubectl get / describe -> next question
```

1. Read the question; note the cluster context.
2. `kubectl config use-context <context>`; verify with `current-context`.
3. Generate nearly every resource with `kubectl create ... $do > file.yaml`.
4. Open the file in vim and edit exactly what the question needs (resources, probe, label).
5. `kubectl apply -f file.yaml`, then `kubectl get` it to confirm it is Running/Succeeded.
6. Collect easy points first; skip the hard ones and return if time remains (2 min/question pace).

**etcd restore flow**

```
stop control plane (move manifests out) -> snapshot restore to NEW --data-dir
   -> edit etcd.yaml hostPath -> move manifests back (restart)
   -> kubelet starts etcd -> cluster recovers
```

Backups are offsite, encrypted, automated, and tested (a backup you never restored from is worthless). Pair an etcd snapshot with Velero for PV/app data; etcd holds cluster metadata only.

## 6. Common Mistakes and Gotchas

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Writing YAML from scratch | Believing it is more reliable | Always generate with `kubectl create ... $do`. |
| Working on the wrong cluster | Not checking the context | `use-context` first, verify with `current-context`. |
| Tabs in pasted YAML | Editors default to tabs; YAML forbids them | `expandtab` in `.vimrc`; fix a broken file with `:retab`. |
| Missing `ETCDCTL_API=3` | etcdctl defaults to v2 | Prefix every etcdctl snapshot/restore call. |
| Restoring into a running etcd | Treating restore like apply | Stop control plane, restore to new dir, update manifest, restart. |
| Wrong cert paths | Using api-server, not etcd certs | Use `/etc/kubernetes/pki/etcd/` client pair. |
| Leaving hostPath misdirected | Forgot to edit `etcd.yaml` | Confirm the data volume hostPath points to the restored dir. |
| `kubectl logs` shows nothing | Restart cleared the log | Use `kubectl logs <pod> --previous` for the crashed instance. |

**Gotchas:** `The connection to the server localhost:8080 was refused` means kubectl can find no kubeconfig (it defaults to unsecured localhost:8080). A Pending pod is usually an unschedulable node or missing PVC, not a YAML bug. Protect the kubeconfig with `chmod 600`, and never `kubectl apply` straight into production - use Git via ArgoCD.

## 7. Quick self-check (mini Q/mini table)

| Question | Answer |
|----------|--------|
| What port does etcd use for client traffic? | 2379 (peer 2380) |
| What env var must precede `etcdctl snapshot`? | `ETCDCTL_API=3` |
| Where do the etcd TLS certs live in kubeadm? | `/etc/kubernetes/pki/etcd/` |
| Passing score for CKA? | 66% |
| Three kubeconfig sections? | clusters, users, contexts |
| Which flag generates YAML without contacting the API server? | `--dry-run=client -o yaml` |
| Default node monitor / pod eviction timers? | 40s / 5m |

Answer the capstone five correctly and you are interview-ready:
1. Why `kubectl logs --previous`? Current logs are the fresh restart; `--previous` shows the crashed instance (the real stack trace or OOMKilled).
2. HPA shows `<unknown>/50%`? Metrics Server absent, or the Deployment has no `resources.requests.cpu` baseline.
3. PVC stuck `Terminating`? A `kubernetes.io/pvc-protection` finalizer waits on a using Pod, or a `Retain` PV. Remove with `kubectl patch pvc <name> -p '{"metadata":{"finalizers":null}}'`.
4. ArgoCD detects drift? Polls Git vs live; `selfHealing` re-applies Git state to overwrite manual edits.
5. Headless Service (`clusterIP: None`) for StatefulSets? No load balancing; per-Pod DNS A-records let `db-0` reach `db-1` directly.

## 8. 30-Second Recap

Aliases (`k`, `do`) set at exam start; `dry-run=client -o yaml` generates base YAML, edit only the delta. Switch context before each task. `ETCDCTL_API=3` snapshot to offsite storage; restore = stop control plane, `snapshot restore --data-dir` to a new dir, retarget the etcd hostPath, restart. Kubeconfig three parts - clusters, users, contexts - plus `current-context`. Everything in /ops is a control loop (ReplicaSet, HPA, ArgoCD, Rollouts). Declarative over imperative, verify every apply, bind every action to a business outcome, and answer interview questions with the symptoms-data-hypothesis-action-verify funnel and the STAR method for behavioral stories.

## Related Lessons

- [Lesson 43 - CKA Exam Masterclass (Speed and Shortcut Techniques)](../docs/14-certifications/lesson-43-cka-exam-masterclass.md)
- [Lesson 44 - Cluster Architecture and the Kubeconfig File](../docs/14-certifications/lesson-44-cluster-architecture-and-the-kubeconfig-file.md)
- [Lesson 45 - etcd Backup and Restore](../docs/14-certifications/lesson-45-etcd-backup-and-restore.md)
- [Lesson 46 - The Capstone (Architecture, Career and Interview Mastery)](../docs/14-certifications/lesson-46-the-capstone-architecture-career-and-interview-mastery.md)

## Related Material

- [Interview - Capstone](../interview/capstone.md)
- [All Cheat Sheets](../cheatsheets/README.md)

[Back to Revision Index](README.md)