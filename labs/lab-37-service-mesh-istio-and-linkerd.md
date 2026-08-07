---
title: Lab 37 - Service Mesh (Istio and Linkerd)
lesson: 37
module: 04 Networking
tags: [kubernetes, service-mesh, istio, linkerd, sidecar, mTLS]
---

# Lab 37 - Service Mesh (Istio and Linkerd)

## Objective

In this lab you will install a lightweight Service Mesh on a running kind cluster, inject sidecar proxies into a sample deployment, verify the sidecar containers with kubectl, enable mTLS, and observe mesh traffic with the mesh-specific command line tools. The lab uses Linkerd stable as the default path because it installs and runs quickly on kind, with Istio noted as an alternative for the same steps.

## Prerequisites

- A running kind cluster
- kubectl installed and configured
- Completion of Lessons 1 through 36

## Pre-Lab Checklist

- [ ] kind cluster running
- [ ] `kubectl get nodes` shows Ready status
- [ ] A default namespace to work in
- [ ] `curl` available for downloading the mesh CLI

---

## Step 1: Install Linkerd CLI and Control Plane

Download the Linkerd CLI and verify the installation:

```bash
curl -sSfL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin
linkerd version
```

Expected output:

```text
Client version: stable-2.x.y
Server version: unavailable
```

Install the Linkerd control plane into your kind cluster:

```bash
linkerd install | kubectl apply -f -
```

Wait for the control plane to become healthy and validate it:

```bash
linkerd check
```

The check runs a series of pre- and post-install diagnostics. When all checks pass, the final summary shows:

```text
Status check results are OK
```

## Step 2: Deploy the Sample Application

Create a sample deployment named `sample-app.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: demo
spec:
  selector:
    app: demo
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: demo
  template:
    metadata:
      labels:
        app: demo
    spec:
      containers:
      - name: demo
        image: nginx:stable-alpine
        ports:
        - containerPort: 80
```

Apply it and confirm the Pods are running before injection:

```bash
kubectl apply -f sample-app.yaml
kubectl get pods
```

Expected output (one container per Pod):

```text
NAME                    READY   STATUS    RESTARTS   AGE
demo-7f6d6c5d6c-abc12   1/1     Running   0          12s
demo-7f6d6c5d6c-def34   1/1     Running   0          12s
demo-7f6d6c5d6c-ghi56   1/1     Running   0          12s
```

## Step 3: Inject Sidecars into the Deployment

Enable automatic injection on the `default` namespace so future Pods get a sidecar, and inject into the already-running Deployment:

```bash
kubectl annotate namespace default linkerd.io/inject=enabled
kubectl rollout restart deployment demo
```

Wait for the rollout to finish:

```bash
kubectl rollout status deployment/demo
```

## Step 4: Verify Sidecar Proxy Containers

List the Pods and notice that each now reports two containers:

```bash
kubectl get pods
```

Expected output:

```text
NAME                    READY   STATUS    RESTARTS   AGE
demo-7f6d6c5d6c-abc12   2/2     Running   0          20s
demo-7f6d6c5d6c-def34   2/2     Running   0          20s
demo-7f6d6c5d6c-ghi56   2/2     Running   0          20s
```

Confirm the proxy container name inside the Pod:

```bash
kubectl get pod -l app=demo -o jsonpath='{.items[0].spec.containers[*].name}'
```

Expected output:

```text
demo linkerd-proxy
```

If you chose Istio instead, the equivalent cluster with an exposed port is:

```bash
istioctl proxy-status
```

It lists the control plane and the sync state for each injected Pod.

## Step 5: Run Mesh Verification and View mTLS

Run the Linkerd traffic check to confirm that the data plane proxies are healthy and that all live traffic is being automatically secured:

```bash
linkerd check
```

To confirm the proxies are using mTLS and to observe per-route traffic, install and view the web dashboard and live metrics:

```bash
linkerd viz install | kubectl apply -f -
kubectl -n linkerd-viz rollout status deploy --timeout=120s
linkerd viz top -n default deploy
```

Generate sustained traffic against the demo Service so the top view has data to show:

```bash
kubectl run -it --rm traffic --image=curlimages/curl --restart=Never -- sh -c 'while true; do curl -s http://demo.default.svc:80 >/dev/null; done'
```

Expected output from with `linkerd top`:

```text
ROUTE       SERVICE     START_TIME   SUCCESS   L5D_IN       L5D_OUT
/           demo        20s          100%      1ms          1ms
```

## Step 6: Confirm mTLS Between Proxies

The `linkerd check` post-install also verifies that the proxies can perform mTLS handshakes with the control plane's certificate authority. To demonstrate mTLS between two injected workloads, exec into a Proxy container and confirm the identity:

```bash
kubectl exec deploy/demo -c linkerd-proxy -- /bin/sh -c 'echo ok'
```

For a stronger proof, open the data plane table in the dashboard:

```bash
linkerd viz table
```

It shows the source, destination, workload, and mesh identity (For example, `default:...demo`): which is the certificate identity used for mutual TLS.

## Step 7: Istio Alternative Commands

If you chose Istio, the equivalent sidecar and traffic observability commands are:

```bash
istioctl proxy-config routes deploy/istio-demo
istioctl analyze
istioctl verify-install
istioctl istiod-status
```

## Step 8: Cleanup

Remove the injected namespace annotation, the sample workload, and the entire mesh. First remove the dashboard extensions node, then server (or linkerd) itself:

For Linkerd:

```bash
kubectl delete -f sample-app.yaml
kubectl annotate namespace default linkerd.io/inject-
linkerd uninstall | kubectl delete -f -
```

Re-verify the cluster returns to a clean state:

```bash
kubectl get pods
kubectl get ns
```

For Istio, the equivalent end-to-end teardown is:

```bash
kubectl delete -f sample-app.yaml
kubectl label namespace default istio-injection-
istioctl x uninstall --purge
```

---

## Lab Questions

1. How can you tell that the sidecar proxy was successfully injected into a Pod after completing Step 4?
2. What does the default-namespace annotation/`linkerd x inject` actually modify in the Pod spec when it injects the proxy?
3. Why is the `linkerd check` useful both before and after workload injection?
4. What is the observable difference between a mesh-protected and a non-protected Pipeline deployment?

---

## Expected Results

After completing this lab:

- You can install a lightweight Service mesh (Linkerd) on a kind cluster
- You can inject sidecar proxies into a Deployment and verify them with kubectl
- You can enable and verify mTLS between workloads
- You can observe mesh traffic and proxy status with `linkerd check` and `linkerd viz top`
- You understand the equivalent Istio workflow with `istioctl`

---

## Key Commands Reference

| Command | Purpose |
|---------|---------|
| `linkerd check` | Pre- and post-install health and config validation |
| `kubectl get pods` | Verify sidecar injection (READY `2/2`) |
| `kubectl get pod <pod> -o jsonpath='{.spec.containers[*].name}'` | List containers inside a Pod |
| `linkerd viz top deployment/demo` | Aggregate live L7 traffic by route |
| `linkerd viz table` | Show per-workload mesh and mTLS traffic |
| `istioctl proxy-status` | Istio: review proxy config sync status |

---

## Next

- Return to the [Lesson 37 file](../docs/04-networking/lesson-37-service-mesh-istio-and-linkerd.md) to review the concepts
- Try the Mini Project: Deploy two services and verify that only mesh-injected workloads can communicate when mTLS is set to STRICT
- Proceed to the next lesson to learn about eBPF and Cilium in Module 04