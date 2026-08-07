# Lab 16 - Network Policies

## Prerequisite

- Completion of [Lesson 16 - Network Policies](../docs/04-networking/lesson-16-network-policies.md).
- A running kind cluster (kindnetd supports Network Policies natively).
- kubectl installed and configured.

## Objective

Create two namespaces, prove they can talk, and then lock down the backend namespace with a Default Deny policy. Verify that traffic is blocked and understand the Timeout behavior.

## Estimated Time

15 minutes.

---

## Step 1: Create Namespaces

```bash
kubectl create namespace frontend
kubectl create namespace backend
```

Expected output:

```
namespace/frontend created
namespace/backend created
```

## Step 2: Deploy Pods

```bash
kubectl run web --image=nginx:alpine -n backend -l app=api
kubectl run client --image=alpine -n frontend -l app=web -- sleep 3600
```

Expected output:

```
pod/web created
pod/client created
```

## Step 3: Wait for Pods to Run

```bash
kubectl get pods -n frontend -n backend --wait
```

Wait until both pods show `Running` status.

## Step 4: Verify Default Connectivity

Get the IP of the web pod:

```bash
kubectl get pod web -n backend -o wide
```

Note the IP address (e.g., `10.244.1.5`).

Exec into the client pod:

```bash
kubectl exec -it client -n frontend -- sh
```

Inside the pod, run:

```sh
wget -qO- http://<web-pod-ip>
```

Replace `<web-pod-ip>` with the actual IP.

Expected output: The standard Nginx "Welcome to nginx!" HTML output.

Type `exit` to leave the pod.

## Step 5: Apply a Default Deny NetworkPolicy

Create `deny-all.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

Apply it:

```bash
kubectl apply -f deny-all.yaml
```

Expected output:

```
networkpolicy.networking.k8s.io/default-deny-ingress created
```

## Step 6: Verify the Block

Exec back into the client pod:

```bash
kubectl exec -it client -n frontend -- sh
```

Inside the pod, run:

```sh
wget -qO- http://<web-pod-ip>
```

Expected behavior: The command hangs. It does NOT fail instantly. Press Ctrl+C after 5-10 seconds.

**Analysis:**

1. Did it fail instantly (Connection Refused) or did it hang (Timeout)?
2. Why did it behave this way?

(Answer: It hung. Timeout. The CNI inserted iptables rules to DROP the packet. It does not send a rejection response back to the client, so the client waits for an acknowledgement until it times out).

Type `exit` to leave the pod.

## Step 7: Verify NetworkPolicy Exists

```bash
kubectl get networkpolicy -n backend
kubectl describe networkpolicy default-deny-ingress -n backend
```

Expected output:

```
NAME                     POD-SELECTOR   AGE
default-deny-ingress     <none>         2m

Name:         default-deny-ingress
Namespace:    backend
Created on:   2026-08-06 10:00:00 +0000 UTC
Labels:       <none>
Annotations:  <none>
Spec:
  PodSelector:     <none> (Selecting all pods in this namespace)
  Allowing ingress traffic:
    <none> (Selected pods are denied for all ingress traffic)
  Policy Types: Ingress
```

## Step 8: Cleanup

```bash
kubectl delete networkpolicy default-deny-ingress -n backend
kubectl delete namespace frontend backend
```

Expected output:

```
networkpolicy.networking.k8s.io "default-deny-ingress" deleted
namespace "frontend" deleted
namespace "backend" deleted
```

---

## What You Learned

- Kubernetes uses a flat network by default — any Pod can talk to any Pod.
- NetworkPolicies are firewalls that control ingress and egress traffic.
- A Default Deny policy blocks all traffic unless explicitly allowed.
- When a firewall drops a packet, the client experiences a Timeout, not a Connection Refused.
- The CNI plugin (not Kubernetes itself) enforces Network Policies.

## Next Steps

Proceed to [Lesson 19 - Persistent Storage (PVs, PVCs, and StorageClasses)](../docs/05-storage/lesson-19-persistent-storage-pv-pvc-sc.md) to learn about Volumes, Persistent Volumes, and Storage Classes.

---

[Back to Labs](README.md)
