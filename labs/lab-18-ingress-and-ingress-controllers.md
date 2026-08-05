# Lab 18 - Ingress and Ingress Controllers

## Objective

Install an NGINX Ingress Controller in kind, deploy two applications, and route traffic to them based on URL paths and hostnames.

## Prerequisites

- Lesson 18 - Ingress and Ingress Controllers.
- A running kind cluster with port mappings for Ingress.
- kubectl installed and configured.

### Quick Cluster Setup (kind with Ingress)

```bash
kind delete cluster

cat <<EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
EOF

kind create cluster --config kind-config.yaml
```

## Steps

### 1. Install the NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

Wait for it to be ready:

```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

### 2. Deploy Two Applications

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app1
  template:
    metadata:
      labels:
        app: app1
    spec:
      containers:
      - name: app1
        image: hashicorp/http-echo
        args: ["-text=Hello from App 1"]
---
apiVersion: v1
kind: Service
metadata:
  name: app1-svc
spec:
  type: ClusterIP
  selector:
    app: app1
  ports:
  - port: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app2
  template:
    metadata:
      labels:
        app: app2
    spec:
      containers:
      - name: app2
        image: hashicorp/http-echo
        args: ["-text=Hello from App 2"]
---
apiVersion: v1
kind: Service
metadata:
  name: app2-svc
spec:
  type: ClusterIP
  selector:
    app: app2
  ports:
  - port: 5678
EOF
```

### 3. Create Path-Based Ingress

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /app1
        pathType: Prefix
        backend:
          service:
            name: app1-svc
            port:
              number: 5678
      - path: /app2
        pathType: Prefix
        backend:
          service:
            name: app2-svc
            port:
              number: 5678
EOF
```

### 4. Test Path-Based Routing

```bash
curl http://localhost/app1
curl http://localhost/app2
```

Expected: "Hello from App 1" and "Hello from App 2".

### 5. Test Host-Based Routing

```bash
kubectl delete ingress my-ingress

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: app1.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app1-svc
            port:
              number: 5678
  - host: app2.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app2-svc
            port:
              number: 5678
EOF
```

```bash
curl -H "Host: app1.local" http://localhost
curl -H "Host: app2.local" http://localhost
```

### 6. Cleanup

```bash
kubectl delete ingress my-ingress
kubectl delete svc app1-svc app2-svc
kubectl delete deployment app1 app2
kind delete cluster
```

## Verification

- Ingress Controller is running in `ingress-nginx` namespace.
- Path-based routing works: `/app1` -> App 1, `/app2` -> App 2.
- Host-based routing works: `Host: app1.local` -> App 1, `Host: app2.local` -> App 2.

## Expected Output Snapshot

```text
$ curl http://localhost/app1
Hello from App 1

$ curl http://localhost/app2
Hello from App 2

$ curl -H "Host: app1.local" http://localhost
Hello from App 1
```

## Related

- Lesson file: [lesson-18-ingress-and-ingress-controllers.md](../docs/04-networking/lesson-18-ingress-and-ingress-controllers.md)
