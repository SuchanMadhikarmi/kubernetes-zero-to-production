# Lab 23 - Namespaces and Contexts

## Prerequisite

- Completion of [Lesson 23 - Namespaces and Contexts](../docs/01-fundamentals/lesson-23-namespaces-and-contexts.md).
- A running kind cluster.
- kubectl installed and configured.

## Objective

Create a Namespace, lock it down with a ResourceQuota, set up a Context, and then try to exceed the quota.

## Estimated Time

15 minutes.

---

## Step 1: Create a Namespace and Context

```bash
kubectl create namespace team-alpha

kubectl config set-context alpha-context --namespace=team-alpha --cluster=kind-$(kind get clusters) --user=kind-$(kind get clusters)
kubectl config use-context alpha-context
```

Verify it worked:

```bash
kubectl config current-context
kubectl get pods
```

(It should say `alpha-context` and `No resources found in team-alpha namespace.`)

## Step 2: Apply a ResourceQuota

Create `quota.yaml`:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: team-alpha
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 1Gi
    limits.cpu: "2"
    limits.memory: 2Gi
```

Apply it:

```bash
kubectl apply -f quota.yaml
```

## Step 3: Test the Quota (The Good)

Deploy a Pod that requests 500m (half a CPU):

```bash
kubectl run good-pod --image=nginx:alpine --requests="cpu=500m,memory=256Mi" --limits="cpu=1,memory=512Mi"
```

Verify it's running:

```bash
kubectl get pods
```

## Step 4: Break Things on Purpose

Try to deploy a second Pod that requests 1 full CPU:

```bash
kubectl run bad-pod --image=nginx:alpine --requests="cpu=1,memory=256Mi" --limits="cpu=1,memory=512Mi"
```

**Your Task:**

- What happened when you tried to run the `bad-pod` command? Did it give you an error in the terminal immediately, or did it hang?
- Run `kubectl get pods`. Does `bad-pod` exist in the namespace?
- Based on the theory of Admission Controllers, at what exact point did Kubernetes reject this Pod, and why?

(Answer: 1. It gave an error immediately: `Error from server (Forbidden): pods "bad-pod" is forbidden: exceeded quota`. 2. No, it does not exist. 3. It was rejected at the API Server's Admission Control phase. The request was never saved to etcd, so the Scheduler and Kubelet never saw it).

## Step 5: Cleanup

```bash
kubectl config use-context kind-$(kind get clusters)
kubectl delete namespace team-alpha
kubectl config delete-context alpha-context
```

---

## What You Learned

- Namespaces provide logical grouping and isolation for resources within a single cluster.
- Contexts (stored in `~/.kube/config`) pair a user, cluster, and namespace so you don't have to type `-n` constantly.
- ResourceQuotas limit the total amount of CPU/Memory/Object count in a namespace.
- Quotas are enforced by the Admission Controller at the API Server level. If a Pod's requests would exceed the quota, the API Server returns 403 Forbidden instantly.

## Next Steps

Proceed to [Lesson 24 - kubectl Essentials and Cluster Access](../docs/01-fundamentals/README.md) to learn about kubectl.

---

[Back to Labs](README.md)
