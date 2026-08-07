---
title: Lab 36 - Multi-Cluster Kubernetes
lesson: 36
module: 12 Production
tags: [kubernetes, multi-cluster, contexts, kubeconfig, federation]
---

# Lab 36 - Multi-Cluster Kubernetes

## Objective

In this lab you will simulate a multi-cluster environment by creating two kind clusters with distinct names, working with their contexts in a single kubeconfig, running workloads on each cluster, and managing those workloads across contexts. Along the way you will see how config sync (GitOps) and true cross-cluster federation differ, and why the latter is not available locally.

## Prerequisites

- Docker running, because we will create multiple kind clusters
- kind installed
- kubectl installed and configured
- Completion of Lessons 1 through 35

## Pre-Lab Checklist

- [ ] Docker daemon is running (`docker info`)
- [ ] kind installed
- [ ] kubectl installed
- [ ] No existing cluster named `cluster-us` or `cluster-eu`

---

## Step 1: Create Two Kind Clusters with Distinct Names

We will simulate a multi-cluster environment by creating two isolated kind clusters, `cluster-us` and `cluster-eu`, each on its own Kubernetes control plane and its own etcd store.

```bash
kind create cluster --name cluster-us
kind create cluster --name cluster-eu
```

Verify both clusters were created:

```bash
kind get clusters
```

Expected Output:

```
cluster-eu
cluster-us
```

Note that each cluster is fully independent. They do not share state, and etcd does not sync between them. This is exactly what a real multi-cluster architecture looks like, just running locally on Docker.

## Step 2: Verify the Contexts Were Added

When kind creates a cluster, it automatically appends a new context to your kubeconfig. Switch into the default cluster with `minikube` or use the `kubectl config get-clusters` command to see what kind added.

List all clusters known to your kubeconfig:

```bash
kubectl config get-clusters
```

Expected Output:

```
kind-cluster-eu
kind-cluster-us
```

Now list the full contexts with their current selection indicator:

```bash
kubectl config get-contexts
```

Expected Output:

```
CURRENT   NAME              CLUSTER           AUTHINFO        NAMESPACE
*         kind-cluster-us   kind-cluster-us   kind-cluster-us
          kind-cluster-eu   kind-cluster-eu   kind-cluster-eu
```

The `*` marks the current context (initially `kind-cluster-us`). Both contexts live in a single kubeconfig, which is how one engineer manages many clusters from one machine.

## Step 3: Work with Multiple Contexts in a Single Kubeconfig

A kubeconfig file (typically `~/.kube/config`) can hold many clusters, users, and contexts. Inspect what kind added:

```bash
kubectl config view
```

Expected Output:

```
apiVersion: v1
clusters:
- cluster:
    server: https://127.0.0.1:...
  name: kind-cluster-us
- cluster:
    server: https://127.0.0.1:...
  name: kind-cluster-eu
contexts:
- context:
    cluster: kind-cluster-us
    user: kind-cluster-us
  name: kind-cluster-us
- context:
    cluster: kind-cluster-eu
    user: kind-cluster-eu
  name: kind-cluster-eu
current-context: kind-cluster-us
kind: Config
preferences: {}
users:
- name: kind-cluster-us
  user:
    client-certificate-data: REDACTED
    client-key-data: REDACTED
    token: REDACTED
```

Because both cluster contexts are in one kubeconfig, you can switch between them without reconfiguring kubectl.

### Switch Contexts

```bash
kubectl config use-context kind-cluster-eu
```

Expected Output:

```
Switched to context "kind-cluster-eu".
```

Confirm the switch:

```bash
kubectl config current-context
```

Expected Output:

```
kind-cluster-eu
```

### List Contexts Again

```bash
kubectl config get-contexts
```

Expected Output:

```
CURRENT          NAME              CLUSTER           AAMINFO         NAMESPACE
                  kind-cluster-us   kind-cluster-us   kind-cluster-us
*                 kind-cluster-eu   kind-cluster-eu   kind-cluster-eu
```

The `*` has moved to `kind-cluster-eu`. You are now operating against the EU cluster.

## Step 4: Deploy the Same Manifest to Both Clusters

Because both contexts point into the same kubeconfig, the exact same commands apply to whichever cluster is current. First, ensure we are on `kind-cluster-us`:

```bash
kubectl config use-context kind-cluster-us
```

Deploy a workload to the US cluster:

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: nginx:alpine
        ports:
        - containerPort: 80
EOF
```

Verify the pods in the US cluster:

```bash
kubectl get pods -l app=web-app
```

Expected Output:

```
NAME                       READY   STATUS    RESTARTS   AGE
web-app-5d7cc8d6d5-9c2xw   1/1     Running   0          20s
web-app-5d7cc8d6d5-pkx7y   1/1     Running   0          20s
```

Now switch to the EU cluster. Note that the EU cluster is empty because it is a separate control plane:

```bash
kubectl config use-context kind-cluster-eu
kubectl get pods
```

Expected Output:

```
No resources found in default namespace.
```

Deploy the same manifest to the EU cluster:

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: nginx:alpine
        ports:
        - containerPort: 80
EOF
```

Naming the second deployment is optional because the EU cluster is empty; however, give it a distinct name to keep it readable in the output below. If you prefer a unique-name approach, apply this instead:

```bash
kubectl create deployment web-app-eu --image=nginx:alpine --replicas=2
kubectl get pods
```

Expected Output:

```
NAME                          READY   STATUS    RESTARTS   AGE
web-app-eu-7545d5f76c-7sb5d   1/1     Running   0          12s
web-app-eu-7545d5f76c-m9qrz   1/1     Running   0          12s
```

You now have the same logical application running in two independent clusters, each with its own control plane and etcd store.

## Step 5: Demonstrate Cluster Isolation

Because the clusters share only the kubeconfig file (not their data), changes in one cluster do not affect the other.

Delete the deployment from the US cluster only:

```bash
kubectl config use-context kind-cluster-us
kubectl delete deployment web-app
kubectl get pods -l app=web-app
```

Expected Output:

```
No resources found in default namespace.
```

Now switch back to the EU cluster and confirm its workload is untouched:

```bash
kubectl config use-context kind-cluster-eu
kubectl get pods
```

Expected Output:

```
NAME                          READY   STATUS    RESTARTS   AGE
web-app-eu-7545f26f76c-9wxe3   1/1     Running   0          3m
web-app-eu-7545f26f76c-kr2yq   1/1     Running   0          3m
```

This proves that workloads are isolated per control plane. Deleting a Deployment in one cluster had zero effect on the other, which is the core value of a multi-cluster design: reduced blast radius.

## Step 6: Real Federation and Cross-Cluster Networking (Explained)

True federation means a single control plane coordinating multiple clusters and making them interoperable as one logical cluster. This is what the lesson refers to when it addresses "connectivity" and "registration" between clusters. In production this is implemented via:

- ArgoCD Hub + ApplicationSets: a central server reaches the API server of each target cluster using a kubeconfig and keeps them in sync with Git.
- Cluster API: provisions new clusters and registers them.
- Istio multi-cluster: establishes secure east-west traffic between Pods in different clusters over a shared mesh.

All of these rely on network reachability between the control plane (or mesh) and each cluster's API server. Locally, the two lost-kind clusters run in separate Docker containers on your machine with different IPs but no automatic federation. You can demonstrate the networking boundary by listing the API server addresses:

```bash
kubectl config use-context kind-cluster-us
kubectl cluster-info
```

Expected Output (API server address varies):

```
Kubernetes control plane is running at https://127.0.0.1:32769
```

```bash
kubectl config use-context kind-cluster-eu
kubectl cluster-info
```

Expected Output:

```
Kubernetes control plane is running at https://127.0.0.1:32217
```

Each cluster exposes a separate API server endpoint. There is no shared etcd and no automatic replication between them. To deploy the same app to both, you must either run the command twice (as you did here) or introduce an external coordinator such as ArgoCD. We will not install ArgoCD in this lab; the takeaway is the mechanism, not the deployment tool.

## Step 7: Demo GitOps ApplicationSet (Optional)

The production way to keep both clusters identical is declarative GitOps. The single object below asks ArgoCD to generate one Application per cluster:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: multi-cluster-app
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: https://cluster-us-api.example.com
        name: us
      - cluster: https://cluster-eu-api.example.com
        name: eu
  template:
    metadata:
      name: 'web-app-{{name}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/example/my-app
        targetRevision: HEAD
        path: manifests
      destination:
        server: '{{cluster}}'
        namespace: default
      syncPolicy:
        automated: {}
```

This YAML is not applied here because it requires a running ArgoCD instance and API servers that are reachable from the Hub. Refer to Lesson 36 for the full ApplicationSet explanation.

## Step 8: Cleanup

Delete the two clusters to free resources:

```bash
kind delete cluster --name cluster-us
kind delete cluster --name cluster-eu
```

Verify both are gone:

```bash
kind get clusters
```

Expected Output:

```
No kind clusters found.
```

Your kubeconfig is cleaned automatically; run the following to confirm the two host contexts are removed:

```bash
kubectl config get-clusters
```

Expected Output: the previous kind entries are no longer present.

---

## Expected Results

After completing this lab you will be able to:

- Create multiple kind clusters with distinct names.
- Verify and inspect contexts in a single kubeconfig.
- Switch between clusters using `kubectl config use-context`.
- Deploy the same manifest to different clusters.
- Demonstrate isolation between clusters.
- Explain why true cross-cluster federation and networking require external tools.

---

## Key Commands Reference

| Command | Purpose |
|---------|---------|
| `kind create cluster --name <name>` | Create an isolated cluster |
| `kind get clusters` | List all kind clusters |
| `kubectl config get-contexts` | List all contexts in the kubeconfig |
| `kubectl config use-context <name>` | Switch the active cluster |
| `kubectl config view` | Show the full kubeconfig |
| `kubectl cluster-info` | Show the API server endpoint |

---

## Next

- Return to the [Lesson 36 file](../docs/12-production/lesson-36-multi-cluster-kubernetes.md) to review the concepts
- Try the Mini Project: register two kind clusters into a small ArgoCD-managed namespace
- Proceed to the next lesson to learn about capacity planning and cost optimization
- Continue to the certificate: a kubeconfig with many clusters is a core CKA skill