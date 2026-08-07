# Lab 41 - Cluster Architecture and the Kubeconfig File

## Prerequisite

- Completion of [Lesson 41 - Cluster Architecture and the Kubeconfig File](../docs/14-certifications/lesson-41-cluster-architecture-and-the-kubeconfig-file.md).
- A running kind cluster (context `kind-prod-mindset`).

## Objective

Inspect a real kubeconfig, manipulate contexts and namespaces, deliberately break the config, and restore it. Finish with a second kind cluster to practice multi-context switching.

## Estimated Time

20 minutes.

---

## Step 1: Inspect the generated kubeconfig

```bash
cat ~/.kube/config
kubectl config view
kubectl config get-contexts
```

Expected: the `clusters`, `users`, and `contexts` sections are visible; the active context (kind show with `*`) is `kind-prod-mindset`.

## Step 2: Change the default namespace of the current context

```bash
kubectl config set-context --current --namespace=kube-system
kubectl get pods
kubectl config set-context --current --namespace=default
```

Expected: `kubectl get pods` lists kube-system Pods without `-n`.

## Step 3: Break the config and observe the failure

```bash
sed -i 's|https://127.0.0.1:[0-9]*|https://192.168.99.99:6443|g' ~/.kube/config
kubectl get nodes
```

Expected output: `Unable to connect to the server: dial tcp 192.168.99.99:6443: ...` (refused or i/o timeout). It fails because the context points to `192.168.99.99`, where no API server exists.

## Step 4: Restore the config from kind

```bash
kind get kubeconfig --name prod-mindset > ~/.kube/config
kubectl get nodes
```

Expected: control plane node listed, command succeeds.

## Step 5: Add a second cluster (multi-context)

```bash
kind create cluster --name dev-cluster
kubectl config get-contexts
```

Expected: two contexts now present: `kind-prod-mindset` and `kind-dev-cluster`.

## Step 6: Switch and verify isolation

```bash
kubectl config use-context kind-dev-cluster
kubectl run test-pod --image=nginx
kubectl get pods

kubectl config use-context kind-prod-mindset
kubectl get pods
```

Expected: `test-pod` exists only in the dev context; switching back to prod-mindset shows no `test-pod`.

## Step 7: Cleanup

```bash
kubectl config use-context kind-dev-cluster
kubectl delete pod test-pod
kind delete cluster --name dev-cluster
kubectl config delete-context kind-dev-cluster
kubectl config current-context
```

Expected: only `kind-prod-mindset` remains and is current.

## Summary

You read a real kubeconfig, pinned a default namespace per context, introduced and diagnosed a broken `server` URL, restored it, and switched between two independent clusters to confirm workloads isolate by context.