# Lab 17 - Services and Cluster Networking

## Objective

Deploy an application, expose it via a ClusterIP Service, verify routing, test self-healing, and debug a broken Service with no Endpoints.

## Prerequisites

- Lesson 17 - Services and Cluster Networking.
- A running kind cluster.
- kubectl installed and configured.

### Quick Cluster Setup (kind)

```bash
kind create cluster --name learning
kubectl cluster-info --context kind-learning
```

## Steps

### 1. Create the Deployment and Service

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: web-svc
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-deploy
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

### 2. Verify the Service and Endpoints

```bash
kubectl get svc web-svc
kubectl get endpoints web-svc
```

Expected: The Service has a ClusterIP. The Endpoints output shows 3 IP addresses.

### 3. Test Internal Connectivity

```bash
kubectl run test-client --rm -it --image=alpine -- wget -qO- http://web-svc
```

Expected: You see the Nginx welcome page HTML.

### 4. Test Self-Healing

```bash
# In one terminal, watch the Pods
kubectl get pods -l app=web --watch

# In another terminal, delete a Pod
kubectl delete pod <POD_NAME>
```

The Service instantly routes traffic to the remaining healthy Pods.

### 5. Test Scaling

```bash
kubectl scale deployment web-deploy --replicas=5
kubectl get endpoints web-svc
```

The Endpoints list now shows 5 IPs.

### 6. Debug a Broken Service

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: broken-svc
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
EOF

kubectl get endpoints broken-svc
```

The Endpoints column shows `<none>` because the selector doesn't match any Pods.

### 7. Cleanup

```bash
kubectl delete svc web-svc
kubectl delete svc broken-svc
kubectl delete deployment web-deploy
```

## Verification

- Service has a ClusterIP and Endpoints with Pod IPs.
- Traffic to the Service DNS name reaches healthy Pods.
- Deleting a Pod does not break connectivity.
- A Service with a mismatched selector has empty Endpoints.

## Expected Output Snapshot

```text
NAME       TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
web-svc    ClusterIP   10.96.0.10      <none>        80/TCP    30s

NAME         ENDPOINTS                                    AGE
web-svc      10.244.0.5:80,10.244.0.6:80,10.244.0.7:80   30s
```

## Related

- Lesson file: [lesson-17-services-and-cluster-networking.md](../docs/04-networking/lesson-17-services-and-cluster-networking.md)
