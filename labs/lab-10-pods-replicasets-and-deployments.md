# Lab 10 - Pods, ReplicaSets, and Deployments

## Objective

Deploy an Nginx application using a declarative Deployment. Observe the Deployment -> ReplicaSet -> Pod hierarchy, test self-healing, scaling, rolling updates, and rollbacks.

## Prerequisites

- Lesson 10 - Pods, ReplicaSets, and Deployments.
- A running kind, minikube, or k3s cluster.
- kubectl installed and configured.

### Quick Cluster Setup (kind)

If you do not have a cluster running, use kind:

```bash
# Create a cluster
kind create cluster --name learning

# Verify
kubectl cluster-info --context kind-learning
kubectl get nodes
```

When finished:

```bash
kind delete cluster --name learning
```

## Target Environment

Any local Kubernetes cluster (kind, minikube, k3s, Docker Desktop Kubernetes).

## Steps

### 1. Create the Deployment

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deploy
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
EOF
```

### 2. Verify the hierarchy

```bash
kubectl get deployments
kubectl get replicasets
kubectl get pods -l app=web
```

Expected: 1 Deployment, 1 ReplicaSet, and 3 Pods.

### 3. Test self-healing

```bash
# Pick one Pod name from the list
kubectl delete pod <POD_NAME>

# Immediately check the Pod list
kubectl get pods -l app=web
```

The deleted Pod terminates, and a brand new Pod is created to maintain the count of 3.

### 4. Test scaling

```bash
kubectl scale deployment nginx-deploy --replicas=5
kubectl get pods -l app=web
```

Now 5 Pods are running.

### 5. Test rolling update

```bash
kubectl set image deployment/nginx-deploy nginx=nginx:1.26-alpine
kubectl rollout status deployment/nginx-deploy
kubectl get replicasets
```

A new ReplicaSet appears and scales up while the old one scales down.

### 6. Test rollback

```bash
kubectl rollout undo deployment/nginx-deploy
kubectl rollout status deployment/nginx-deploy
```

Traffic shifts back to the previous version.

### 7. Inspect the deployment history

```bash
kubectl rollout history deployment/nginx-deploy
```

### 8. Cleanup

```bash
kubectl delete deployment nginx-deploy
```

## Verification

- The Deployment creates a ReplicaSet, which creates Pods.
- Deleting a Pod triggers immediate recreation (self-healing).
- Scaling changes the Pod count.
- Rolling update shifts traffic gradually between ReplicaSets.
- Rollback restores the previous version.

## Expected Output Snapshot

```text
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deploy   3/3     3            3           30s

NAME                      DESIRED   CURRENT   READY   AGE
nginx-deploy-7c5bdf7458   3         3         3       30s

NAME                            READY   STATUS    RESTARTS   AGE
nginx-deploy-7c5bdf7458-abc12   1/1     Running   0          30s
nginx-deploy-7c5bdf7458-def34   1/1     Running   0          30s
nginx-deploy-7c5bdf7458-ghi56   1/1     Running   0          30s
```

## Related

- Lesson file: [lesson-10-pods-replicasets-and-deployments.md](../docs/03-workloads/lesson-10-pods-replicasets-and-deployments.md)