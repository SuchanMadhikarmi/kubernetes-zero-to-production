# Lab 25 - Resource Management and the OOMKiller

## Objective

Deploy Pods with memory and CPU limits, trigger an OOMKilled event, observe CPU throttling, and verify QoS classes.

## Prerequisites

- Lesson 25 - Resource Management and the OOMKiller.
- A running kind cluster.
- kubectl installed and configured.

### Quick Cluster Setup (kind)

```bash
kind create cluster --name learning
kubectl cluster-info --context kind-learning
```

## Steps

### 1. Deploy a Pod That Gets OOMKilled

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: memory-hog
spec:
  containers:
  - name: app
    image: polinux/stress
    resources:
      requests:
        memory: "50Mi"
      limits:
        memory: "100Mi"
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "250M", "--vm-hang", "1"]
EOF
```

```bash
kubectl get pod memory-hog --watch
```

Expected: The Pod cycles through Running, OOMKilled, and CrashLoopBackOff.

### 2. Debug the OOMKilled

```bash
kubectl describe pod memory-hog | grep -A 5 "Last State"
```

Expected:

```
Last State: Terminated
  Reason: OOMKilled
  Exit Code: 137
```

### 3. Observe CPU Throttling

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cpu-hog
spec:
  containers:
  - name: app
    image: polinux/stress
    resources:
      requests:
        cpu: "100m"
      limits:
        cpu: "200m"
    command: ["stress"]
    args: ["--cpu", "2"]
EOF
```

```bash
kubectl top pod cpu-hog
```

The Pod uses 200m CPU (its limit) even though it's trying to use more.

### 4. Check QoS Classes

```bash
kubectl get pod memory-hog -o jsonpath='{.status.qosClass}'
kubectl get pod cpu-hog -o jsonpath='{.status.qosClass}'
```

Both show `Burstable` because requests != limits.

### 5. Test Guaranteed QoS

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: guaranteed-app
spec:
  containers:
  - name: app
    image: nginx:1.25-alpine
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "100m"
        memory: "128Mi"
EOF
```

```bash
kubectl get pod guaranteed-app -o jsonpath='{.status.qosClass}'
```

Shows `Guaranteed` because requests == limits.

### 6. Cleanup

```bash
kubectl delete pod memory-hog cpu-hog guaranteed-app
kind delete cluster --name learning
```

## Verification

- Pod with memory limit gets OOMKilled with Exit Code 137.
- Pod with CPU limit shows throttled CPU usage.
- QoS classes are correctly assigned (Burstable vs Guaranteed).

## Expected Output Snapshot

```text
$ kubectl describe pod memory-hog | grep -A 5 "Last State"
    Last State: Terminated
      Reason: OOMKilled
      Exit Code: 137

$ kubectl get pod memory-hog -o jsonpath='{.status.qosClass}'
Burstable

$ kubectl get pod guaranteed-app -o jsonpath='{.status.qosClass}'
Guaranteed
```

## Related

- Lesson file: [lesson-25-resource-requests-limits-and-quotas.md](../docs/06-configuration/lesson-25-resource-requests-limits-and-quotas.md)
