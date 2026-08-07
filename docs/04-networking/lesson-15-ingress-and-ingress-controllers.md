---
title: Lesson 15 - Ingress and Ingress Controllers
module: 04 Networking
lesson: 15
status: Complete
tags: [kubernetes, ingress, ingress-controller, nginx, layer7, http, tls, routing]
---

# Lesson 15 - Ingress and Ingress Controllers

## Table of Contents

- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Real-world Motivation](#real-world-motivation)
- [Core Concepts](#core-concepts)
- [Architecture](#architecture)
- [ASCII Diagrams](#ascii-diagrams)
- [Hands-on](#hands-on)
- [Commands](#commands)
- [YAML Explanation](#yaml-explanation)
- [Production Notes](#production-notes)
- [Best Practices](#best-practices)
- [Common Mistakes](#common-mistakes)
- [Troubleshooting](#troubleshooting)
- [Interview Questions](#interview-questions)
- [Scenario Questions](#scenario-questions)
- [Quiz](#quiz)
- [Revision](#revision)
- [Cheat Sheet](#cheat-sheet)
- [References](#references)
- [Related Lessons](#related-lessons)
- [Coming Next](#coming-next)

---

## Learning Objectives

By the end of this lesson you will be able to:

- Explain the limitations of using LoadBalancer or NodePort Services for production web traffic.
- Describe what an Ingress and an Ingress Controller are.
- Distinguish between Layer 4 (TCP/UDP) and Layer 7 (HTTP) routing.
- Route HTTP traffic based on domain names (hosts) and URL paths.
- Install an NGINX Ingress Controller on kind and configure routing rules.

## Prerequisites

- Completion of Lesson 17 (understanding of Services, ClusterIP, and Pods).
- A running kind cluster (see setup instructions below).
- kubectl installed and configured.

### Setting Up kind for Ingress

kind needs a special configuration to allow port 80 traffic from your host machine into the cluster node:

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

## Real-world Motivation

### The Cost and Port Problem

Imagine you have 50 microservices (frontend, auth, billing, search).

- If you use a LoadBalancer Service for each, your cloud provider (AWS/GCP) provisions 50 separate Cloud LoadBalancers. This costs a fortune.
- If you use a NodePort Service for each, users have to type `http://myapp.com:30001` for auth and `http://myapp.com:30002` for billing. Users expect traffic on standard ports 80 (HTTP) and 443 (HTTPS).

### The SSL Termination Problem

You want your traffic to be encrypted (HTTPS). If you rely on Services, every single Pod must contain the SSL certificate and handle the CPU-heavy encryption/decryption process.

### Why This Exists

Kubernetes needed a way to centralize external access to the cluster. Ingress was created to act as a single "front door" for HTTP/HTTPS traffic. It allows you to route traffic to different internal Services based on the URL path (e.g., `/api` goes to the backend, `/` goes to the frontend) or the domain name (e.g., `api.myapp.com` vs `blog.myapp.com`).

### Real Company Examples

**Netflix:** Netflix uses an Ingress-like edge routing layer (Zuul) to handle all incoming traffic from their global users. When you open the Netflix app, one single IP receives your request. The Ingress controller reads your HTTP request and routes you to the "Profiles Service" if you're logging in, or the "Streaming Service" if you're watching a movie.

## Core Concepts

### Explain Like I'm 12

Imagine a large apartment building.

- A NodePort/LoadBalancer is like giving every resident their own external door to the street. It's expensive and takes up too much sidewalk space.
- An Ingress is the main lobby door. Everyone enters through the same door (Port 80).
- The Ingress Controller is the receptionist at the front desk. You walk in and say, "I'm here for the API apartment." The receptionist looks at their rulebook (Ingress Resource) and directs you to the correct elevator (Service).

### Explain Like I'm a Junior Engineer

You create an Ingress YAML that says, "If traffic comes for `example.com/api`, send it to the `api-svc` Service." For this to work, you must have an Ingress Controller running. The Controller continuously watches the Kubernetes API for new Ingress rules. When it finds one, it dynamically updates its internal configuration (e.g., writing an `nginx.conf` file) and reloads.

### Explain Technically

- The Ingress object is stored in etcd.
- The Ingress Controller (e.g., NGINX) runs as a Deployment or DaemonSet, exposed via a LoadBalancer or NodePort Service.
- The Controller uses a SharedInformer to watch the API Server for Ingress objects.
- When a new Ingress is created, the Controller translates the HTTP routing rules into its native proxy configuration.
- When a user hits the Controller's IP, the Controller inspects the HTTP Host header and Path. It then proxies the request to the ClusterIP of the backend Service.

### How Kubernetes Implements It Internally

Kubernetes intentionally left Ingress controllers out of the core. The Ingress object is just a standard API interface. By using an IngressClass, you can route rules to NGINX, Traefik, or cloud-native controllers like the AWS ALB Controller. This allows the ecosystem to innovate without changing the core Kubernetes codebase.

### Why Kubernetes Was Designed That Way

By keeping the Ingress resource separate from the controller, Kubernetes allows you to swap controllers without changing your Ingress rules. You can move from NGINX to Traefik to a cloud-native controller by changing a single field (`ingressClassName`).

## Architecture

```
[ Internet User ]
      |
      | (GET http://myapp.com/api)
      v
[ Cloud LoadBalancer ] (Provisions 1 IP, forwards port 80)
      |
      v
[ Ingress Controller Pod ] (NGINX reads the HTTP request)
      |
      | (Matches rule: path /api -> backend-svc)
      v
[ Backend Service (ClusterIP) ]
      |
      v
[ Backend Pods ]
```

### Terminology

| Term | Definition |
|------|------------|
| Ingress | A Kubernetes API object that manages external access to the services in a cluster, typically HTTP. |
| Ingress Controller | The actual application (like NGINX) that fulfills the Ingress rules. |
| Layer 7 Routing | Routing traffic based on application-level data (HTTP headers, URLs, cookies). |
| IngressClass | A Kubernetes object that specifies which Ingress Controller is responsible for handling a specific Ingress resource. |
| TLS Termination | The process of decrypting HTTPS traffic at the Ingress Controller, forwarding plain HTTP to backend Pods. |
| rewrite-target | An NGINX Ingress annotation that rewrites the URL path before forwarding to the backend Service. |

### How It Works Internally

1. You install the NGINX Ingress Controller. It creates a Service of type LoadBalancer (or uses host ports).
2. You deploy two applications: frontend and backend, each with their own ClusterIP Service.
3. You apply an Ingress YAML to the cluster.
4. The NGINX Controller Pod notices the new Ingress object.
5. NGINX updates its internal `nginx.conf` file:
   ```
   location / { proxy_pass http://frontend-svc; }
   location /api { proxy_pass http://backend-svc; }
   ```
6. NGINX reloads its configuration.
7. When a request arrives at the NGINX Pod, it reads the URL path, matches it to its config, and proxies the request to the correct Service IP.

### Step-by-Step Workflow

1. User creates an Ingress resource pointing to `frontend-svc` and `backend-svc`.
2. API Server saves the Ingress to etcd.
3. NGINX Ingress Controller detects the new Ingress.
4. Controller validates that the referenced Services actually exist. If they do, it updates its internal proxy configuration and reloads.
5. User traffic hits the Cloud LoadBalancer -> hits the NGINX Pod.
6. NGINX inspects the HTTP request, routes it to the correct Service, which routes it to the Pod.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | YAML is applied. The Controller picks it up and configures the proxy. |
| Updating | If the rules or referenced Services change, the Controller reloads its config. |
| Deletion | The Ingress is deleted. The Controller removes the routing rules from its config and reloads. |

### Service vs Ingress

| Feature | Service (LoadBalancer) | Ingress |
|---------|------------------------|---------|
| OSI Layer | Layer 4 (TCP/UDP) | Layer 7 (HTTP/HTTPS) |
| Routing Logic | None (just opens a pipe) | URL Paths, Hostnames, Headers |
| Cost | High (1 Cloud LB per Service) | Low (1 Cloud LB for many apps) |
| SSL Termination | Can do L4, but L7 is complex | Native, centralized |
| Use Case | Exposing a TCP database or a single app | Exposing multiple web microservices |

### Common Myths

| Myth | Fact |
|------|------|
| "Ingress replaces Services." | Ingress relies on Services. The Ingress Controller reads the HTTP request and proxies it to a ClusterIP Service. The Service then routes it to the Pod. |
| "Kubernetes includes an Ingress Controller by default." | No. You must install one (like NGINX, Traefik, or AWS ALB Controller) for Ingress rules to actually work. |
| "Ingress can route any type of traffic." | Ingress is designed for HTTP/HTTPS traffic. For raw TCP/UDP, use a LoadBalancer Service. |

## ASCII Diagrams

Mental Model: The Ingress Controller is a Traffic Cop standing at the only entrance to the building. You hand the Cop your request ("I need to see /billing"). The Cop looks at the rulebook (Ingress) and says, "Go down the hall to Room 80."

```
[ User Browser ] 
      | (HTTP GET /api/v1)
      v
[ NGINX Ingress Controller ] (Matches rule: path /api -> svc api-svc)
      | (Forwards to ClusterIP 10.96.0.20:80)
      v
[ Service: api-svc ] (kube-proxy DNAT)
      | (Rewrites to Pod IP 10.1.0.5:8080)
      v
[ Pod: api-server ]
```

### Host-Based Routing Flow

```
[ User: curl -H "Host: app1.local" http://loadbalancer-ip ]
      |
      v
[ NGINX Ingress Controller ]
      | (Matches Host header: app1.local)
      v
[ Service: app1-svc ]
      |
      v
[ Pod: app1 ]
```

### Path-Based Routing Flow

```
[ User: curl http://loadbalancer-ip/api ]
      |
      v
[ NGINX Ingress Controller ]
      | (Matches path: /api)
      v
[ Service: api-svc ]
      |
      v
[ Pod: api-server ]
```

## Hands-on

### Objective

Install an NGINX Ingress Controller in kind, deploy two applications, and route traffic to them based on the URL path.

### Step 1: Recreate kind with Port Mappings

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

### Step 2: Install the NGINX Ingress Controller

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

### Step 3: Deploy Two Applications

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

### Step 4: Create the Ingress Rule

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

### Step 5: Test the Routing

```bash
curl http://localhost/app1
curl http://localhost/app2
```

Expected: "Hello from App 1" and "Hello from App 2" respectively.

### Step 6: Test Host-Based Routing

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

### Step 7: Cleanup

```bash
kind delete cluster
```

## Commands

```bash
# List Ingress rules
kubectl get ingress

# Describe an Ingress (shows routing rules and backend validation)
kubectl describe ingress my-ingress

# Show NGINX access logs (great for 503 debugging)
kubectl logs -n ingress-nginx <pod-name>

# Check if the Ingress Controller is running
kubectl get pods -n ingress-nginx

# Test routing
curl http://localhost/app1
curl -H "Host: app1.local" http://localhost
```

## YAML Explanation

```yaml
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
```

### Field-by-Field Explanation

- `kind: Ingress`: Defines a Kubernetes Ingress object.
- `metadata.annotations`: Configuration hints for the Ingress Controller. `rewrite-target: /` strips the path prefix before forwarding.
- `spec.ingressClassName: nginx`: Tells Kubernetes which controller should process this Ingress.
- `spec.rules`: Defines HTTP routing rules.
- `path: /app1`: The URL path to match.
- `pathType: Prefix`: Matches any URL that starts with `/app1`.
- `backend.service`: The target Service and port.

## Production Notes

- **TLS Termination at the Ingress.** Terminate SSL/TLS at the Ingress Controller (using a certificate). The Controller handles the HTTPS decryption and forwards plain HTTP internally to the Pods. This saves CPU on your application Pods and centralizes certificate management.
- **Use rewrite-target carefully.** If your app doesn't understand the `/api` prefix, strip it at the Ingress level using annotations.
- **Always define ingressClassName.** In modern Kubernetes, an Ingress without a class might be ignored by all controllers.
- **Run multiple Ingress Controller replicas** for high availability. If the single NGINX Pod dies, all external traffic stops.
- **Set CPU/Memory requests and limits** on the Ingress Controller. It is the bottleneck for your entire cluster's external traffic.
- **Use Network Policies** to restrict which Pods the Ingress Controller can talk to.

### When to Use / When NOT to Use

**Use Ingress when:**

- Exposing HTTP/HTTPS web applications to the internet.
- You have multiple microservices and want to route traffic based on `/api`, `/auth`, etc.
- You want to centralize TLS certificate management.

**Do NOT use Ingress when:**

- Exposing non-HTTP protocols (like raw TCP for a database, SSH, or a game server). Use a LoadBalancer Service instead.

### Performance and Security Considerations

**Performance:** The Ingress Controller is the bottleneck for your entire cluster. If the NGINX Pod is overloaded, all apps go down. Always set CPU/Memory requests and limits on the Controller, and consider running multiple replicas across different nodes.

**Security:** Do not expose your internal microservices directly via LoadBalancers. Force all external traffic through the Ingress Controller so you can implement Web Application Firewalls (WAF), rate-limiting, and SSL inspection at a single point.

## Best Practices

- Install an Ingress Controller before creating Ingress resources.
- Always define `ingressClassName` in your Ingress specs.
- Terminate TLS at the Ingress Controller, not at individual Pods.
- Use `rewrite-target` annotation when backend services don't understand URL prefixes.
- Run multiple Ingress Controller replicas for high availability.
- Set resource requests and limits on the Ingress Controller.
- Use Network Policies to restrict Ingress Controller access to backend Pods.
- Monitor Ingress Controller logs for 503 errors and latency.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Forgetting to install an Ingress Controller | Ingress object alone does nothing | Install NGINX or another controller before creating Ingress resources |
| Typo in Service Name/Port | Ingress points to wrong backend | Verify with `kubectl describe ingress` |
| Terminating SSL at the Pod | Not understanding TLS termination | Terminate TLS at the Ingress Controller to save Pod CPU |
| Missing ingressClassName | Old Kubernetes behavior | Always define `ingressClassName` in modern clusters |
| Not using rewrite-target | Backend doesn't understand URL prefix | Add `nginx.ingress.kubernetes.io/rewrite-target: /` annotation |

## Troubleshooting

**Symptom: 404 Not Found**

Cause: Ingress path doesn't match the request, or the Ingress Controller hasn't picked up the rules yet.

```bash
kubectl describe ingress my-ingress
kubectl logs -n ingress-nginx <controller-pod> | grep -i "reload"
```

Fix: Verify the Ingress rules and ensure the Controller has reloaded.

**Symptom: 503 Service Unavailable**

Cause: The Ingress points to a Service that has no Endpoints (no healthy Pods).

```bash
kubectl get endpoints <service-name>
kubectl describe ingress my-ingress | grep -A 5 "Backend"
```

Fix: Ensure the backend Service has healthy Pods. Check selector labels.

**Symptom: Connection Refused**

Cause: The Ingress Controller Pod is not running or not reachable.

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

Fix: Ensure the Ingress Controller is running and exposed via LoadBalancer or NodePort.

## Interview Questions

**Q: What is the difference between a Service and an Ingress?**

A: A Service routes traffic to Pods (Layer 4). An Ingress routes HTTP traffic to Services based on URL paths and hostnames (Layer 7).

**Q: Does Kubernetes come with an Ingress Controller built-in?**

A: No. You must install one (like NGINX, Traefik, or AWS ALB Controller) for Ingress rules to actually work.

**Q: What happens if an Ingress points to a Service that has no Endpoints?**

A: The Ingress Controller cannot proxy the traffic. It will typically return a 503 Service Unavailable error to the user.

**Q: You have 50 web microservices. How do you expose them to the internet without spending a fortune on AWS?**

A: I would install an Ingress Controller (like NGINX) and expose it via a single AWS LoadBalancer. Then, I would create Ingress rules for each microservice, routing traffic based on URL paths (e.g., `/api/auth`, `/api/billing`) to their respective internal ClusterIP Services.

**Q: What is the difference between Layer 4 and Layer 7 routing?**

A: Layer 4 routing (LoadBalancer/NodePort) works at the TCP/UDP level. It just opens a network pipe. Layer 7 routing (Ingress) works at the HTTP level. It can read HTTP headers, URLs, and hostnames to make smart routing decisions.

**Q: What is TLS termination and why do it at the Ingress?**

A: TLS termination is the process of decrypting HTTPS traffic. Doing it at the Ingress Controller centralizes certificate management and saves CPU on individual application Pods, which would otherwise need to handle encryption/decryption.

## Scenario Questions

**Scenario 1:** You apply an Ingress but `curl http://localhost/app1` returns a 404. What do you check first?

A: First, check if the Ingress Controller is running: `kubectl get pods -n ingress-nginx`. Then check the Ingress rules: `kubectl describe ingress my-ingress`. Verify the backend Services exist and have Endpoints.

**Scenario 2:** You need to route traffic to a gRPC service. Can you use Ingress?

A: Standard NGINX Ingress handles HTTP/HTTPS. For gRPC, you need an Ingress Controller that supports gRPC (NGINX Ingress does with specific annotations) or use a Service of type LoadBalancer for TCP passthrough.

**Scenario 3 (Mini Project - Host-Based Routing):**

Modify the ingress.yaml to use hostnames instead of URL paths. Make it so that `curl -H "Host: app1.local" http://localhost` goes to App 1, and `curl -H "Host: app2.local" http://localhost` goes to App 2.

## Quiz

1. What layer does Ingress operate at?
   - A. Layer 3 (Network)
   - B. Layer 4 (Transport)
   - C. Layer 7 (Application)
   - D. Layer 2 (Data Link)

2. What must you install before Ingress rules work?
   - A. A LoadBalancer
   - B. An Ingress Controller
   - C. CoreDNS
   - D. kube-proxy

3. What does the `rewrite-target` annotation do?
   - A. Rewrites the DNS name
   - B. Rewrites the URL path before forwarding to the backend
   - C. Rewrites the IP address
   - D. Rewrites the HTTP method

4. What happens if an Ingress points to a Service with no Endpoints?
   - A. 200 OK
   - B. 404 Not Found
   - C. 503 Service Unavailable
   - D. 301 Redirect

5. Can Ingress route raw TCP database traffic?
   - A. Yes
   - B. No, use a LoadBalancer Service instead
   - C. Only with annotations
   - D. Only with Istio

Answers: 1-C, 2-B, 3-B, 4-C, 5-B.

## Revision

One-minute revision:

- Services operate at Layer 4 (TCP). Ingress operates at Layer 7 (HTTP).
- An Ingress is just a set of rules. An Ingress Controller is the software that executes them.
- Ingress allows you to route many domains/paths through a single Cloud LoadBalancer, saving money.
- If an Ingress points to a Service that doesn't exist or has no Pods, the Controller returns a 404 or 503.
- You must install an Ingress Controller (NGINX, Traefik, etc.) before Ingress rules work.

Memory trick:

- Ingress: The hotel receptionist's rulebook.
- Ingress Controller: The receptionist's brain that reads the rules.
- Service: The elevator that takes you to the specific floor.

Key facts:

- Ingress = L7 HTTP routing.
- Controller = NGINX/Traefik reading the rules.
- Must install a controller for Ingress to work.
- Routes to Services, not Pods.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl get ingress` | Lists Ingress rules |
| `kubectl describe ingress <name>` | Shows routing rules and backend validation |
| `kubectl logs -n ingress-nginx <pod>` | Shows NGINX access logs (great for 503 debugging) |
| `kubectl get pods -n ingress-nginx` | Checks if the Ingress Controller is running |
| `curl -H "Host: app1.local" http://localhost` | Tests host-based routing |

## References

- [Kubernetes Documentation: Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Kubernetes Documentation: Ingress Controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
- [NGINX Ingress Controller Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes Documentation: IngressClass](https://kubernetes.io/docs/concepts/services-networking/ingressclass/)
- [Kubernetes Documentation: TLS Management](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls)

## Related Lessons

- [Lesson 9 - Services and Cluster Networking](lesson-14-services-and-cluster-networking.md) - how Services provide stable internal networking.
- [Lesson 13 - Network Policies](lesson-16-network-policies.md) - restricting traffic between Services.
- [Module 07 - Security](../07-security/README.md) - TLS certificates and RBAC.
- [Module 12 - Production](../12-production/README.md) - production hardening and high availability.

## Coming Next

Now that you understand how Ingress routes HTTP traffic to Services, the next lesson covers Network Policies, which restrict which Pods can talk to which Services. You will learn how to implement zero-trust networking inside your cluster.
