---
title: Lab 34 - Operators in Practice
lesson: 34
module: 11 Operators
tags: [kubernetes, operators, crd, controller, stateful]
---

# Lab 34 - Operators in Practice

## Objective

In this lab you will learn how Operators extend Kubernetes by building and running a custom CRD plus controller, then installing a battle-tested Operator (the Redis Operator) to manage a real stateful workload. You will observe the reconciliation loop in action and prove that the Operator enforces the desired state after failures.

## Prerequisites

- A running kind cluster
- kubectl installed and configured
- Helm CLI installed
- Completion of Lessons 1 through 33, specifically Lesson 32 on CRDs

## Pre-Lab Checklist

- [ ] kind cluster running
- [ ] `kubectl get nodes` shows Ready status
- [ ] `helm version` returns a valid version
- [ ] Understand the difference between a CRD, a CR, and a controller

---

## Step 1: Create a Simple CRD

A CRD provides the schema for a new API resource. Kubernetes stores instances of it, but nothing reacts to it until a controller watches it.

Create `website-crd.yaml`:

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: websites.example.com
spec:
  group: example.com
  names:
    kind: Website
    listKind: WebsiteList
    singular: website
    plural: websites
    shortNames:
    - web
  scope: Namespaced
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              host:
                type: string
              replicas:
                type: integer
                minimum: 1
                maximum: 10
```

Apply it:

```bash
kubectl apply -f website-crd.yaml
```

Expected output:

```text
customresourcedefinition.apiextensions.k8s.io/websites.example.com created
```

## Step 2: Inspect the CRD

Verify the CRD is registered and explore its schema:

```bash
kubectl get crd websites.example.com
```

Expected output:

```text
NAME                   CREATED AT
websites.example.com   <current-time>
```

Inspect the full schema:

```bash
kubectl describe crd websites.example.com
```

**Your Task:**

- What is the API group for this custom resource?
- What are the short names you can use to list instances of it?
- Is the resource cluster-scoped or namespace-scoped?

## Step 3: Apply a Custom Resource

Create `website-cr.yaml`:

```yaml
apiVersion: example.com/v1
kind: Website
metadata:
  name: shop-demo
spec:
  host: shop.demo.local
  replicas: 2
```

Apply it:

```bash
kubectl apply -f website-cr.yaml
```

Expected output:

```text
website.example.com/shop-demo created
```

List all instances using the short name:

```bash
kubectl get websites
```

Expected output:

```text
NAME        HOST            REPLICAS   AGE
shop-demo   shop.demo.local   2        <age>
```

## Step 4: Observe the Controller Behavior

A CRD alone does nothing. No Pods, Services, or ConfigMaps are created automatically. Verify the cluster is idle:

```bash
kubectl get configmaps,deployments,pods
```

Expected output:

```text
No resources found
```

This proves the CR is inert until a controller watches it. Now deploy a controller that reacts to the `website` custom resource. The controller watches the API Server and reconciles each CR by creating a ConfigMap encoding its declared host. If the ConfigMap is removed, the controller recreates it on the next reconcile.

Create `website-controller.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: website-controller
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: website-controller
rules:
- apiGroups: ["example.com"]
  resources: ["websites"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: website-controller
subjects:
- kind: ServiceAccount
  name: website-controller
  namespace: default
roleRef:
  kind: ClusterRole
  name: website-controller
  apiGroup: rbac.authorization.k8s.io/v1
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: website-controller
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: website-controller
  template:
    metadata:
      labels:
        app: website-controller
    spec:
      serviceAccountName: website-controller
      containers:
      - name: controller
        image: bitnami/kubectl:1.28
        command:
        - /bin/bash
        - -c
        - |
          while true; do
            for cr in $(kubectl get websites.example.com -o name 2>/dev/null); do
              name="${cr##*/}"
              if ! kubectl get configmap "web-$name" >/dev/null 2>&1; then
                host=$(kubectl get websites.example.com "$name" -o jsonpath='{.spec.host}')
                kubectl create configmap "web-$name" --from-literal=host="$host"
              fi
            done
            sleep 5
          done
```

Apply it:

```bash
kubectl apply -f website-controller.yaml
```

Wait for the controller to reconcile, then verify:

```bash
kubectl get configmap web-shop-demo -o yaml
```

Expected output:

```text
apiVersion: v1
data:
  host: shop.demo.local
kind: ConfigMap
metadata:
  name: web-shop-demo
  ...
```

## Step 5: Watch the Controller Reconcile a Change

Delete the ConfigMap the controller created, then watch the reconciliation loop restore it:

```bash
kubectl delete configmap web-shop-demo
```

Wait five to ten seconds for the next reconcile cycle, then check:

```bash
kubectl get configmaps
```

Expected output:

```text
NAME              DATA   AGE
web-shop-demo     1      <short-age>
```

The ConfigMap came back because the controller continuously compares Live State (no ConfigMap) with Desired State (the CR) and creates the missing piece. Now remove the custom resource and watch the effect:

```bash
kubectl delete website shop-demo
```

The controller creates nothing new because the desired state no longer exists. This mirrors how Operators handle lifecycle management.

## Step 6: Install the Redis Operator

Now use a real, battle-tested Operator to manage a stateful application. Add the OT Container Kit Helm repository and install the Redis Operator:

```bash
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/
helm repo update
helm install redis-operator ot-helm/redis-operator --namespace redis-operator-system --create-namespace
```

Wait for the Operator Pod to be running:

```bash
kubectl get pods -n redis-operator-system
```

Expected output:

```text
NAME                              READY   STATUS    RESTARTS   AGE
redis-operator-<hash>-<pod>        1/1     Running   0          <age>
```

## Step 7: Create a Redis Cluster and Observe Reconciliation

Create `redis-cluster.yaml`:

```yaml
apiVersion: redis.opstreelabs.in/v1beta2
kind: Redis
metadata:
  name: my-redis
spec:
  redis:
    replicas: 3
    image: redis:7.0-alpine
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
  kubernetesConfig:
    imagePullPolicy: IfNotPresent
    updateStrategy:
      type: RollingUpdate
```

Apply it:

```bash
kubectl apply -f redis-cluster.yaml
```

Watch the Operator create the Pods automatically:

```bash
kubectl get pods -l app=my-redis -w
```

Press Ctrl+C when all three Pods are `Running`. Then inspect the StatefulSet the Operator created:

```bash
kubectl get statefulset
```

Expected output:

```text
NAME        READY   AGE
my-redis    3/3     <age>
```

Inspect the Operator's view of the custom resource status:

```bash
kubectl describe redis my-redis
```

## Step 8: Confirm the Reconciliation Loop Recovers State

Simulate a crash by deleting a Redis Pod, then watch the StatefulSet controller recreate it:

```bash
kubectl delete pod my-redis-0
kubectl get pods -l app=my-redis -w
```

Press Ctrl+C once all Pods are `Running` again.

Now delete the entire StatefulSet to prove the Operator re-provisions managed resources:

```bash
kubectl delete statefulset my-redis
```

Watch the Pods return:

```bash
kubectl get pods -l app=my-redis -w
```

**Your Task:**

1. What happened when you deleted the `my-redis-0` Pod? Did it come back?
2. What happened when you deleted the entire StatefulSet? Did the Pods come back?
3. Based on the reconciliation loop, explain exactly what the Operator did when you deleted the StatefulSet.

Answer: 1. Yes, the StatefulSet controller recreated it. 2. Yes, the Pods came back. 3. The Operator's reconciliation loop detected that the Live state (zero StatefulSets) did not match the Desired state (the CR still declares 3 replicas). It immediately constructed a new StatefulSet YAML and sent it to the API Server, which recreated the Pods.

## Step 9: Prove the Operator Drives State (Optional)

Scale the Operator to zero to simulate an unavailable Operator, then try to scale the Redis cluster:

```bash
kubectl scale deployment redis-operator -n redis-operator-system --replicas=0
kubectl patch redis my-redis --type='json' -p='[{"op": "replace", "path": "/spec/redis/replicas", "value": 1}]'
kubectl get statefulset my-redis
```

The StatefulSet still shows 3 replicas because the Operator is dead and nothing reconciles the change. Bring the Operator back and watch it converge:

```bash
kubectl scale deployment redis-operator -n redis-operator-system --replicas=1
sleep 30
kubectl get statefulset my-redis
```

Expected output now shows `my-redis` scaled to 1 replica.

## Cleanup

Remove the custom resources and all controllers:

```bash
kubectl delete website shop-demo
kubectl delete configmap web-shop-demo 2>/dev/null
kubectl delete -f website-controller.yaml
kubectl delete -f website-crd.yaml
kubectl delete redis my-redis
helm uninstall redis-operator -n redis-operator-system
kubectl delete namespace redis-operator-system
```

Verify nothing remains:

```bash
kubectl get crd | grep -i example.com
kubectl get pods -n redis-operator-system
```

Both commands should return no results.

---

## Expected Results

After completing this lab:

- You can create a CRD, apply a custom resource, and inspect its schema
- You understand that a CRD is inert until a controller watches it
- You can run a lightweight controller that reconciles desired state
- You can install a real Operator with Helm and let it manage a stateful application
- You can demonstrate how an Operator reconciles state after failures

## Key Commands Reference

| Command | Purpose |
|---------|---------|
| `kubectl apply -f website-crd.yaml` | Register a custom resource definition |
| `kubectl get websites` | List instances of a custom resource |
| `kubectl describe redis my-redis` | Inspect the Operator's status and errors |
| `kubectl get statefulset` | Verify resources the Operator created |
| `kubectl logs -n redis-operator-system <pod>` | Read Operator logs to diagnose issues |

---

## Next

- Return to the [Lesson 34 file](../docs/11-operators/lesson-34-operators-in-practice.md) to review the concepts
- Try the Mini Project: Install the Prometheus Operator via Helm, create a `Prometheus` CR, delete its Pod, and watch it recover
- Proceed to the next lesson to learn about packaging with Helm