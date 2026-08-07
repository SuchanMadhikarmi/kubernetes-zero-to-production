---
title: Lesson 41 - Cluster Architecture and the Kubeconfig File
module: 14 Certifications
lesson: 41
status: Complete
tags: [kubernetes, cka, kubeadm, kubelet, containerd, kubeconfig, context, static-pod, cluster]
---

# Lesson 41 - Cluster Architecture and the Kubeconfig File

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

- Explain the three core binaries that make up a Kubernetes node: kubeadm, kubelet, and containerd.
- Describe what happens when a cluster is born (`kubeadm init`).
- Explain the structure of the kubeconfig file: clusters, users, contexts.
- Manipulate contexts to switch between clusters or namespaces effortlessly.
- Intentionally break a kubeconfig file and debug the authentication failure.

## Prerequisites

- Completion of Lessons 1 through 40.
- A running kind cluster.
- kubectl installed and configured.

## Real-world Motivation

### From Lesson

The accidental production delete: imagine you have a Dev cluster and a Prod cluster. You have two kubeconfig files on your laptop. You are testing a script in Dev that deletes a namespace. However, your terminal is currently authenticated against the Prod cluster. You run the script, and accidentally delete the production namespace.

Alternatively, the control plane crashes, and you need to give a Junior developer access to a specific namespace. You must understand how the kubeconfig file works to generate a secure token for them.

Why this exists: Kubernetes needed a secure, stateless way for CLI tools to authenticate to the API Server. The kubeconfig file acts as your VIP pass. It tells kubectl who you are, which cluster you want to talk to, and which namespace to default to. Understanding this is critical for the CKA exam, where you will manage multiple clusters.

### Additional Production Knowledge

Every production disruption that begins with "I ran it on the wrong cluster" traces back to a misread or unverified context. The kubeconfig is not merely config; it is the security boundary between your workstation and each environment. A single human mistake (or a stolen file) compromises everything you can reach. Because of that, guardrails such as read-only contexts, IAM-based auth, and restricting who may hold Prod kubeconfigs matter more than the raw mechanics. The CKA tested you on the mechanics; production rewards you for the discipline built on top of them.

## Core Concepts

### From Lesson

- **kubeadm**: A tool used to bootstrap the Kubernetes control plane. It generates TLS certificates, writes static Pod manifests to `/etc/kubernetes/manifests/`, and sets up etcd.
- **kubelet**: The node agent. It runs on every node (including the control plane). It communicates with the API Server and ensures containers are running. It is NOT managed by Kubernetes; it runs as a native systemd service.
- **kubeconfig**: A YAML file (usually at `~/.kube/config`) with three main sections:
  - `clusters`: the API Server URLs and their CA certificates.
  - `users`: your credentials (client certificates, tokens, or cloud auth plugins).
  - `contexts`: a binding of a User to a Cluster, optionally with a default namespace.

### Additional Production Knowledge

- **containerd (CRI)**: kubelet does not start containers directly. It asks the container runtime through the Container Runtime Interface (CRI). containerd (and CRI-O) is the interface implementation, typically running as its own `containerd` systemd/real-service. Keep it in mind as the third binary on the node.
- **`KUBECONFIG` vs `--kubeconfig`**: kubectl merges files listed in the `KUBECONFIG` environment variable (colon-separated on Linux). The `--kubeconfig` flag overrides everything and points at exactly one file. Knowing when each is used matters on the CKA and in multi-cluster setups.
- **exec-based auth / auth-provider**: production contexts frequently use `exec:` plugins (aws-iam-authenticator, gke-gcloud-auth-plugin) that fetch short-lived tokens on each call. This keeps the static certificate (and its expiry) out of the file.

## Architecture

### From Lesson

To build a cluster from scratch (as you do in the CKA exam), you install three things on a Linux machine:

1. A container runtime (containerd).
2. The kubelet agent, running as a systemd service.
3. kubeadm, a CLI tool used to bootstrap the control plane.

```text
[ Developer Laptop ]
      |
      +---> [ ~/.kube/config ] (kubeconfig file)
              |
              v (Reads current-context)
      [ kubectl ] -> Sends HTTPS mTLS request -> [ API Server ]
```

### Additional Production Knowledge

A kubeadm-cluster is kept together not by a single orchestrator but by a sequence of self-referential steps. kubeadm runs only long enough to generate certs, write static manifests, and prepare a kubeconfig; from there the kubelet watches the manifests and "pulls up" the control plane. The API Server, once running, becomes the source of truth for all static Pods as well as normal workloads. This is why the failure of containerd or kubelet on a control-plane node can orphan the whole cluster, and why the extra node care matters.

## ASCII Diagrams

### From Lesson

```text
[ kubeconfig YAML ]
  clusters:
  - name: prod-cluster
    server: https://10.0.0.1:6443
  users:
  - name: admin
    client-certificate: /path/to/cert.crt
  contexts:
  - name: prod-admin
    cluster: prod-cluster
    user: admin
    namespace: default
  current-context: prod-admin

(kubectl reads this) -> Sends HTTPS mTLS request -> [ API Server ]
```

### Additional Production Knowledge

```text
kubeadm init (on control plane)
   |
   | 1. generate TLS certs /etcd-ca, apiserver certs etc.
   | 2. write manifests to /etc/kubernetes/manifests/
   | 3. start kubelet (systemd) which launches those manifests as static pods
   | 4. kubelet boots API Server, Controller-Manager, Scheduler, etcd
   | 5. write /etc/kubernetes/admin.conf (a full kubeconfig)
   v
`kubeadm join <token> <apiserver>  (on each worker node)
```

## Hands-on

### From Lesson

Goal: inspect the kubeconfig file that kind generated for you, change the default namespace of your current context, and intentionally break the server URL to observe the failure.

Step 1 - View the raw config:

```bash
cat ~/.kube/config
```

Look at the YAML. You will see the `clusters`, `users`, and `contexts` sections, and how kind named the cluster and user (e.g. `kind-prod-mindset`).

Step 2 - View the processed config:

```bash
kubectl config view
```

`kubectl config view` prints a merged, cleaned view and hides the large base64 certificate data for readability.

Step 3 - List contexts:

```bash
kubectl config get-contexts
```

The context marked with `*` is your `current-context`.

Step 4 - Change the default namespace in the current context:

```bash
kubectl config set-context --current --namespace=kube-system
kubectl get pods
```

You now see the `kube-system` Pods without passing `-n`.

Step 5 - Reset the namespace:

```bash
kubectl config set-context --current --namespace=default
```

Step 6 - Break the kubeconfig on purpose. Substitute the API Server URL with an unreachable one:

```bash
sed -i 's|https://127.0.0.1:[0-9]*|https://192.168.99.99:6443|g' ~/.kube/config
```

Step 7 - Try to use kubectl:

```bash
kubectl get pods
```

Your task:

1. What error message did kubectl return?
2. Why did kubectl hang or fail to connect, based on the kubeconfig architecture?
3. How would you fix it in a real scenario where you accidentally broke your config?

Answer: (1) `Unable to connect to the server: dial tcp 192.168.99.99:6443: connection refused` or an `i/o timeout`. (2) The context points to a cluster, and that cluster's `server` URL was changed. kubectl read the config, found the context, and tried to send an HTTPS request to `192.168.99.99`; no API server exists there, so the connection failed. (3) Manually fix the URL in vim, or regenerate a valid config. For a kind cluster, restore it with `kind get kubeconfig --name prod-mindset > ~/.kube/config`.

Step 8 - Restore the kubeconfig from kind:

```bash
kind get kubeconfig --name prod-mindset > ~/.kube/config
```

Step 9 - Verify the fix:

```bash
kubectl get nodes
```

## Commands

```bash
# View the merged kubeconfig
kubectl config view
kubectl config view --raw   # include the base64-encoded certificate data

# List contexts and inspect the active one
kubectl config get-contexts
kubectl config current-context

# Switch cluster / context
kubectl config use-context dev-cluster

# Set a default namespace on the current context
kubectl config set-context --current --namespace=kube-system

# Generate a context with a namespace only if the context is missing
kubectl config set-context <name> --cluster=<c> --user=<u> --namespace=<ns>

# Use a specific config file for one command without touching the default
kubectl --kubeconfig=/path/to/config get pods
export KUBECONFIG=/path/to/config
```

## YAML Explanation

```yaml
apiVersion: v1
kind: Config
clusters:
- name: prod-cluster
  cluster:
    certificate-authority: /path/to/ca.crt
    server: https://10.0.0.1:6443
users:
- name: admin
  user:
    client-certificate: /path/to/cert.crt
    client-key: /path/to/cert.key
contexts:
- name: prod-admin
  context:
    cluster: prod-cluster
    user: admin
    namespace: default
current-context: prod-admin
```

- `clusters[].cluster.server` is the untrusted API/SDN address kubectl connects to. In the lab, changing it to a bad IP broke connect.
- `clusters[].cluster.certificate-authority-data` is the base64 CA which lets kubectl verify the API server's identity. The example above uses inline path.
- `users[].user` contains the client certificate and key. Validating the client certificate against the CA is how the API server authenticates.
- `contexts[].context.namespace` defines the default namespace for that binding; most kubectl namespace overrides.
- `current-context` is the single pointer kubectl reads on every command, which is why "wrong file/context" leads to the wrong cluster.

## Production Notes

### From Lesson

- Use a cloud IAM (EKS/GKE) instead of static client certs so credentials can expire and rotate automatically.
- Always run `kubectl config current-context` before a destructive action.
- Merge multiple kubeconfig files with `KUBECONFIG=file1:file2 kubectl config view --raw > merged-config`.

### Additional Production Knowledge

- Keep each cluster's Production IAM/exec auth plugin on the same host as standard path. Don't copy production contexts to a multi-user bastion that many engineers share; or use a narrow, read-only system identity.
- For a single command, prefer the `--kubeconfig` flag or inline `KUBECONFIG` env var over editing global config, so you don't temporarily change the default for every shell.
- Set `chmod 600 ~/.kube/config`. `kubectl config view` will warn if it is too permissive.

## Best Practices

### From Lesson

- Confirm context before running destructive actions.
- Set a default namespace only in the context you actually need it in.
- Regenerate the config from a trusted source (e.g. `kind get kubeconfig`) rather than hand-editing CA blobs.
- Keep a known-good copy or generate a fresh one instead of trying to patch a corrupted file by memory.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Running a Dev script against Prod | Wrong `current-context` in an active shell | Always `kubectl config current-context` before destructive actions; scope contexts to namespaces. |
| Editing YAML indentation by hand | Config is YAML; a mis-indent makes kubectl fail parse | Use `kubectl config set-context` rather than manually editing. |
| Typing `kubectl` fully each time | Slow on the exam and on-call | Use the `k` alias from Lesson 40. |
| Rarely deleting the cluster | Untracked expired contexts | `kubectl config delete-context <name>`. |

## Troubleshooting

### From Lesson

Symptom: `The connection to the server localhost:8080 was refused`
Cause: kubectl cannot find a kubeconfig file. When no config is found, it defaults to trying an unsecured API server at `localhost:8080`.
Fix: (1) ensure your config is at `~/.kube/config`, or (2) set `export KUBECONFIG=/path/to/config`.

### Additional Knowledge

- If a newly restored config says `error: You must be logged in to the server`, your home directory's `~/.kube` path could be different in root vs student shell. Set `KUBECONFIG` explicitly.
- If switching clusters results in a certificate error (`x509: certificate signed by unknown authority`), the `certificate-authority-data` does not match the server. Re-export the correct `--certificate-authority` field from the owning cluster or fetch it from `kind get kubeconfig`.

## Comparison Tables

| Component | Role | Managed By |
|-----------|------|------------|
| kubeadm | Bootstraps the cluster (runs once at init/join) | Admin (manually) |
| kubelet | Manages containers on the node (runs forever) | systemd (OS level) |
| API Server | Handles API requests | kubelet (as a static Pod) |
| kubectl | CLI tool for users | User (local machine) |

## When to Use / When Not to Use

### Use

- Switching between Dev, Staging, and Prod contexts
- Generating short-lived tokens for CI/CD
- Setting a default namespace for a specific task

### Do Not

- Hardcode password/token-string in your commmitted config. Use IAM/OIDC.

## Performance & Security Considerations

- Performance: kubectl reads the kubeconfig on every command. A config with thousands of contexts adds a small parsing delay, but for most cases this is negligible.
- Security: The kubeconfig file contains the keys to the cluster. Protect it with `chmod 600 ~/.kube/config`, never commit it to Git, and rotate on exposure.

## Real Company Examples

### From Lesson

A Platform Engineer keeps a bastion host with a kubeconfig containing 10 contexts (dev, staging, prod-us, prod-eu). They switch between them with `kubectl config use-context prod-us`, and enforce cloud IAM authentication on the production contexts so a static TLS certificate cannot be stolen.

## Common Myths

- Myth: "kubectl connects to a cluster with a persistent background connection." False. kubectl is stateless: it reads the config, opens an HTTPS connection per command, prints output, closes the connection.
- Myth: "You must use kubeadm to install Kubernetes." False. Cloud providers (EKS, AKS) install the control plane for you. kubeadm is the standard for bare metal / VM installs and heavily tested on the CKA.

## Summary

- A cluster is bootstrapped with kubeadm (control plane), kubelet (node agent as systemd), and containerd (runtime).
- The kubeconfig file (`~/.kube/config`) is how kubectl authenticates.
- Three sections: clusters (API URL + CA), users (client cert/key or token), contexts (binding of user to cluster, optional namespace).
- Change default namespace: `kubectl config set-context --current --namespace=<name>`.
- A wrong `server` URL yields a network connection error.

## Revision Notes & Cheat Sheet

- kubeadm = Bootstrapper.
- kubelet = Node Agent (systemd).
- kubeconfig = `~/.kube/config`.
- Context = User + Cluster + Namespace.
- `kubectl config set-context --current --namespace=<ns>` = change default namespace.
- Memory trick: kubeconfig is a VIP pass. cluster = venue address, user = photo ID, context = the lanyard linking the two.

| Command | What it does |
| --- | --- |
| `kubectl config view` | Prints merged kubeconfig |
| `kubectl config get-contexts` | List contexts (the `*` is your active one) |
| `kubectl config use-context <name>` | Switch to a different context/cluster |
| `kubectl config set-context --current --namespace=<ns>` | Change context default namespace |
| `kind get kubeconfig --name <cluster> > ~/.kube/config` | Restore a kind kubeconfig |

## Interview Preparation

### Beginner

Q: What is the difference between kubeadm and kubelet?

Ideal Answer: kubeadm is a bootstrapping tool that generates TLS certificates, writes static Pod manifests, and sets up the control plane. kubelet is an agent that runs on every node periodically, ensuring containers run and are healthy.

Q: Explain the structure of a kubeconfig.

Ideal Answer: it has three areas: clusters (API Server URL + CA), users (client certificates / tokens), contexts (binding a user to a cluster and optionally a default namespace). `current-context` selects the active context.

### Intermediate

Q: How does kubectl know which cluster / can I tell it which to talk to?

Ideal Answer: kubectl reads `KUBECONFIG` (or `~/.kube/config`), looks at `current-context`, resolves the cluster (API URL) and user (credentials), and issues the HTTPS request. You can point at another file with `--kubeconfig` or `KUBECONFIG`.

Q: What does `The connection to the server localhost:8080 was refused` mean?

Ideal Answer: kubectl cannot find a valid kubeconfig. With no config it defaults to an unsecured server on `localhost:8080`. Set `KUBECONFIG` or place the config at `~/.kube/config`.

### Scenario Questions

**Scenario:** You need to run a command against another cluster without changing your default kubeconfig.

**Expected answer:** Use the `--kubeconfig` flag for one command (`kubectl --kubeconfig=/path get pods`) or set `KUBECONFIG=/path` for that shell session only.

**Scenario:** You deleted the namespace demo, and you accidentally did it on `prod` because a script already ran against the current context.

**Expected answer:** Restore the intended context (`kubectl config use-context <the-cluster>`), verify with `current-context`, then re-delete the namespace *exactly* on the intended cluster. Discipline before destructive work prevents most of these.

## Quiz

1. Which component runs as a native service managed by systemd rather than as a container under Kubernetes?
   - A. kubelet
   - B. kube-proxy
   - C. API Server
   - D. Scheduler

2. What are the three sections of the kubeconfig of the file that kubectl reads?
   - A. namespaces, deployments, services
   - B. clusters, users, contexts
   - C. keys, secrets, configmaps
   - D. nodes, pods, resources

3. Which command swaps you to a different cluster/context?
   - A. `kubectl config set-context`
   - B. `kubectl config use-context <name>`
   - C. `kubectl switch-context <name>`
   - D. `kubectl context`

4. A student edits a kubeconfig and sets the `server` URL to `192.168.99.99:6443`. What happens when they run `kubectl get pods`?
   - A. It authenticates with RBAC and works.
   - B. It times out or refuses, because no API server reaches that URL.
   - C. It prints the RBAC-only namespaces.
   - D. It creates a new context.

5. True or False: `kubeadm` is required to run a Kubernetes control plane.
   - A. True
   - B. False (cloud providers install the control plane for you)

Answers: 1-A, 2-B, 3-B, 4-B, 5-B

## Revision

- kubeadm = bootstrapper; kubelet = node agent (systemd); containerd = runtime.
- kubeconfig (`~/.kube/config`) has clusters, users, contexts + `current-context`.
- Control plane components run as static Pods written by kubeadm.
- Wrong `server` URL stale connection → refused/timeout.
- Protect your config (`chmod 600`), verify the context before destructive commands.

## Cheat Sheet

```bash
# Config inspection
kubectl config view
kubectl config get-contexts
kubectl config current-context

# Switching
kubectl config use-context prod-us

# Namespace pin
kubectl config set-context --current --namespace=default

# One-off on another config
kubectl --kubeconfig=/path get pods
export KUBECONFIG=/path

# Restore kind config
kind get kubeconfig --name prod-mindset > ~/.kube/config
```

## References

- [Kubernetes: Organizing Cluster Access Using kubeconfig Files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)
- [Kubernetes: Bootstrapping Clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Kubernetes: Authenticating](https://kubernetes.io/docs/reference/access-authn-authz/authentication/)
- [kubectl cheat sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

## Related Lessons

- [Lesson 40 - CKA Exam Masterclass](lesson-40-cka-exam-masterclass.md) - `k` alias and speed techniques that complement context handling.
- [Lesson 23 - ConfigMaps and Secrets](../06-configuration/lesson-23-configmaps-and-secrets.md) - namespaces and manifest anatomy.
- [Lesson 01 - Anatomy of a Container](../01-fundamentals/lesson-01-anatomy-of-a-container.md) - the container runtime that sits behind the kubelet.

## Coming Next

Lesson 42 continues the CKA core-domain series: the control plane components (API Server, Scheduler, Controller-Manager, etcd) and how the kubelet drives them, plus the troubleshooting of a failing control-plane node.