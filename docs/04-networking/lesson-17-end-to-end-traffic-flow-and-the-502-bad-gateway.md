---
title: Lesson 17 - End-to-End Traffic Flow and the 502 Bad Gateway
module: 04 Networking
lesson: 17
status: Complete
tags: [kubernetes, ingress, service, kube-proxy, networking, 502, bad-gateway, troubleshooting, l4, l7]
---

# Lesson 33 - End-to-End Traffic Flow and the 502 Bad Gateway

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

- Describe the complete path of an HTTP request in a production Kubernetes cluster.
- Name the steps a packet takes from the browser to the container.
- Trace a packet through Layer 4 (TCP) and Layer 7 (HTTP) routing.
- Systematically debug a `502 Bad Gateway` error.

## Prerequisites

- Completion of Lessons 1 through 32.
- A running kind cluster.
- The NGINX Ingress Controller installed (from Lesson 15). If you deleted it, reinstall:
  ```bash
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
  ```
- `kubectl` installed and configured.

## Real-world Motivation

### The Mysterious 502

A user types `www.mycompany.com` into their browser and gets a `502 Bad Gateway`. As the on-call engineer you have minutes to fix it before the company loses money. You cannot panic. You must know exactly which component in the traffic flow is broken: the Cloud LoadBalancer, the Ingress Controller, the ClusterIP Service, or the Pod.

### Why This Exists

Kubernetes heavily abstracts networking. The Ingress handles L7 routing, the Service handles L4 load balancing, and the Pod runs the application. This separation of concerns is great for architecture but creates a black box when a connection fails. Understanding the end-to-end flow is the only way to operate a cluster under pressure.

### Real Company Examples

**Shopify:** Shopify uses an Ingress-like edge routing layer for all incoming traffic. When they deploy a new version, they occasionally see 502s for a couple of seconds. This happens because the Ingress Controller still has old Pod IPs cached as upstreams while those old Pods are being terminated. They use connection draining and Readiness probes to smooth this to zero downtime.

## Core Concepts

### Explain Like I'm 12

Imagine a package delivery service.

- A truck (Internet traffic) arrives at the city gate (Ingress Controller).
- The guard checks the address label and decides, "This goes to the Frontend Office" (Ingress Rule).
- The package is put on an internal conveyor belt (Service).
- The conveyor belt drops it at a specific worker's desk (Pod).
- If the worker's desk is empty or the worker is asleep, the conveyor breaks and the guard returns a "502 Bad Gateway" note to the sender.

### Explain Like I'm a Junior Engineer

When a user hits your application, traffic first hits the Ingress Controller. The Ingress Controller reads the HTTP request (for example, `GET /api`) and matches it to an Ingress rule that points to a Service. The Ingress Controller then sends traffic to the Service's ClusterIP. `kube-proxy` intercepts it and uses iptables to rewrite the destination IP to a real Pod IP. If the Pod is not listening on the expected port, the Pod's kernel rejects the connection and the Ingress Controller returns a `502`.

### Explain Technically

A request flows through multiple layers:

1. The Cloud LoadBalancer routes TCP/80 to the Ingress Controller's Service.
2. The Ingress Controller (NGINX) reads the HTTP Host header and matches an Ingress rule.
3. The rule points to a Service (for example, `frontend-svc:80`).
4. NGINX resolves the Service, then `kube-proxy`'s iptables rules DNAT the packet to a Pod IP.
5. If the Pod is down or the target port is wrong, the TCP handshake fails and NGINX returns `502 Bad Gateway`.

### How Kubernetes Implements It Internally

The Ingress Controller routes through the Service to the Pods, not directly to them. NGINX maintains an upstream list of Pod IPs extracted from the Service's Endpoints. If the Endpoints list is empty, NGINX has no upstream targets and instantly returns a `502` or `503`.

### Why Kubernetes Was Designed That Way

By placing a Service between the Ingress and Pods, Kubernetes decouples a stable routing target (the Service ClusterIP and DNS name) from the ephemeral Pod IPs. Pods come and go, but the Service name and ClusterIP stay constant. This lets controllers replace Pods freely without breaking routing.

## Architecture

```
[ User Browser ]
      |  (GET http://localhost/)
      v
[ Ingress Controller (NGINX) ] (Matches rule: path / -> svc frontend)
      |  (Forwards to ClusterIP 10.96.0.10:80)
      v
[ Service: frontend ] (kube-proxy DNAT)
      |  (Rewrites to Pod IP 10.244.1.5:8080)
      v
[ Pod: frontend ] (Container listening on 8080)
```

### Terminology

| Term | Definition |
|------|------------|
| Layer 4 (TCP/UDP) | Routing based on ports and IPs. Services and LoadBalancers operate here. |
| Layer 7 (HTTP/HTTPS) | Routing based on HTTP headers, URLs, and hostnames. Ingress Controllers operate here. |
| 502 Bad Gateway | A proxy received an invalid response (or a refused connection) from the upstream. |
| 503 Service Unavailable | The proxy has no upstream Pods to route traffic to (Endpoints are empty). |
| Upstream | The target server the proxy forwards traffic to (usually a Pod). |
| Downstream | The client making the request (the user's browser). |
| DNAT | Destination Network Address Translation: rewriting the destination IP of a packet. |

### How It Works Internally

1. The user hits `http://localhost/`.
2. The request hits the NGINX Ingress Controller.
3. NGINX checks `nginx.conf` for a rule matching `/`.
4. NGINX sees `proxy_pass http://frontend-svc.default.svc.cluster.local:80;`.
5. NGINX resolves the DNS name to the Service's ClusterIP.
6. NGINX sends the packet. iptables intercepts it and rewrites the destination to the Pod IP and port.
7. The Pod receives the packet and responds.

### Step-by-Step Workflow

1. Developer creates a Deployment, Service, and Ingress.
2. A user sends traffic to the Ingress Controller.
3. The Ingress Controller evaluates L7 rules and proxies to the Service.
4. `kube-proxy` routes traffic to a Pod.
5. The Pod processes the request and responds; the Ingress returns the result to the user.

### Lifecycle

| State | Description |
|-------|-------------|
| Connection Establishment | TCP handshake between the Ingress and the Pod. |
| Request | HTTP request sent to the Pod. |
| Response | The Pod sends an HTTP response back. |
| Teardown | The TCP connection is closed or kept alive. |

### Communication Patterns

| Communication | Mechanism | Example |
|---------------|-----------|---------|
| Browser -> Ingress | L7 HTTP | `GET /` over TCP/80 |
| Ingress -> Service | DNS + ClusterIP | `frontend-svc.default.svc.cluster.local:80` |
| kube-proxy -> iptables | DNAT | Rewrites ClusterIP -> Pod IP |
| Ingress -> Pod | Upstream proxy | `proxy_pass` to Pod IP:port |

### Common Myths

| Myth | Fact |
|------|------|
| "A 502 means my application code is crashing." | False. A 502 usually means the network routing is broken (for example, a port mismatch). A crashing app produces a 503 because the Endpoints are empty. |
| "Ingress routes traffic directly to Pods." | False. Ingress routes to Services; the Service (via kube-proxy) routes to Pods. |

## ASCII Diagrams

Mental Model: The traffic flow is a relay race. If a runner drops the baton (for example, a Service has no Endpoints), the race stops and the crowd sees an error (502). Check each runner to see who dropped it.

```text
[ Internet ] -> http://localhost/
      |
      v
[ NGINX Ingress Controller ] (Ingress rule: path / -> svc frontend-svc:80)
      |
      v
[ Service: frontend-svc ] (ClusterIP: 10.96.0.10, Port 80 -> TargetPort 8080)
      |
      | (kube-proxy DNAT)
      v
[ Pod: frontend-app ] (IP: 10.1.0.5, Listening on Port 8080)
```

## Hands-on

### Objective

Deploy an app, expose it via Ingress, then intentionally break the port mapping to cause a `502 Bad Gateway`.

### Step 1: Create the App, Service, and Ingress

Create `full-stack.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo
        args: ["-listen=:8080", "-text='Hello from the Frontend!'"]
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
spec:
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-ingress
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-svc
            port:
              number: 80
```

Apply it:

```bash
kubectl apply -f full-stack.yaml
```

Wait for the Pod to be `Running`.

### Step 2: Verify It Works

```bash
curl http://localhost/
```

You should see `Hello from the Frontend!`.

### Step 3: Break Things on Purpose

Simulate a developer updating the app to listen on port 9090 but forgetting to update the Service's `targetPort`.

```bash
cat <<EOF > broken-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
spec:
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 9090  # WRONG PORT
EOF
kubectl apply -f broken-svc.yaml
```

Wait 10 seconds for NGINX to reload, then test:

```bash
curl -v http://localhost/
```

You should get a `502 Bad Gateway` from NGINX.

### Step 4: Investigate the Failure

Check the Endpoints:

```bash
kubectl get endpoints frontend-svc
```

Check the Pod's actual port:

```bash
kubectl get pod -l app=frontend -o yaml | grep containerPort
```

**Your Task:**

1. Were there IPs listed in `kubectl get endpoints frontend-svc`? (There should be, because the Service selector still matches the Pod label.)
2. What error did `curl` return?
3. Based on the full flow, where exactly did the connection break?

(Answer: 1. Yes, the IP was listed. 2. `502 Bad Gateway`. 3. The connection broke at the Ingress -> Pod hop. The Service routed traffic to the Pod on port 9090 (the `targetPort`), but the app listens on 8080. The Pod's kernel received the packet on 9090, no application was listening, so it refused the connection. NGINX interpreted this as a bad gateway and returned 502.)

### Cleanup

```bash
kubectl delete -f full-stack.yaml
kubectl delete -f broken-svc.yaml
```

## Commands

```bash
# Verify the app is reachable through the full flow
curl -v http://localhost/

# Check the Ingress backend Service and port
kubectl describe ingress <name>

# Check if the Service knows about the Pods
kubectl get endpoints <svc>

# Check the port the app actually listens on
kubectl get pod -l app=frontend -o yaml | grep containerPort

# Resolve/confirm the Service record via DNS
kubectl exec <any-pod> -- nslookup frontend-svc.default.svc.cluster.local
```

## YAML Explanation

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo
        args: ["-listen=:8080", "-text='Hello from the Frontend!'"]
        ports:
        - containerPort: 8080
```

The app listens on port 8080. The `containerPort` field documents this, but the real listening port is determined by the app itself.

### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
spec:
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 8080
```

- `spec.ports[].port`: the port the Service exposes (what the Ingress uses).
- `spec.ports[].targetPort`: the port on the Pods to reach. **This must match the container's real listening port.**

### Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-ingress
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-svc
            port:
              number: 80
```

- `ingressClassName: nginx`: selects the NGINX Ingress Controller.
- `backend.service.name`: the target Service.
- `backend.service.port.number`: the Service's `port` (80), which forwards to `targetPort`.

### Field-by-Field Explanation

- The app listens on 8080; the Service targets port 8080; the Ingress routes to the Service on port 80. These three ports must line up.
- A mismatch between `Service.targetPort` and the container's listening port produces `502`.

## Production Notes

- **Match ports carefully:** mismatches between `containerPort` and `targetPort` are the #1 cause of 502s.
- **Use Readiness probes:** Ingress Controllers only route to Pods that pass readiness (Pods present in the Service Endpoints), preventing 502s during rolling updates.
- **Use named ports:** define `targetPort: http` instead of a number so you can change the container port without breaking the Service.
- **Ingress Controller is the bottleneck:** set CPU/memory requests and limits on the Controller and run multiple replicas across nodes.
- **Force external traffic through the Ingress:** apply WAF, rate-limiting, and SSL inspection at a single point rather than exposing services directly.

### When to Use / When NOT to Use

**Use an Ingress Controller when:**

- Exposing HTTP/HTTPS web applications.
- Needing L7 routing based on URLs or hostnames.

**Avoid an Ingress Controller when:**

- Handling raw TCP/UDP traffic (databases, game servers). Use a LoadBalancer Service instead.

### Performance and Security Considerations

**Performance:** The Ingress Controller is the bottleneck for the whole cluster. Set CPU/memory limits and requests, run multiple replicas, and monitor connection metrics.

**Security:** Do not expose internal microservices directly via LoadBalancers. Force external traffic through the Ingress so you apply WAF, rate-limiting, and TLS at a single point.

## Best Practices

- Match `containerPort`, `targetPort`, and Ingress backend ports exactly.
- Use Readiness probes on workloads so traffic only reaches healthy Pods.
- Use named ports in Services.
- Run NGINX Ingress Controller with resource requests/limits and multiple replicas.
- Route all external traffic through the Ingress and terminate TLS there.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| App listening on `localhost` (127.0.0.1) | The app rejects traffic from outside the container | Bind to `0.0.0.0:8080` |
| Typo in Ingress backend name | Ingress points to a Service that does not exist | Verify `kubectl get svc` and the Ingress backend |
| Terminating SSL at the Pod | Ingress passes HTTPS to the Pod but the Pod has no cert | Terminate TLS at the Ingress, not the Pod |
| `Service.targetPort` mismatch | The Service routes to a port the app does not listen on | Match `targetPort` to the real container port |

## Troubleshooting

**Symptom: 502 Bad Gateway**

1. Check the Ingress backend: `kubectl describe ingress <name>` — does it point to the right Service and port?
2. Check Endpoints: `kubectl get endpoints <svc-name>` — empty means the selector mismatch or failing readiness probes.
3. Check the TargetPort — does the Service `targetPort` match the Pod's `containerPort`?
4. Check the app: exec into a utility pod and `curl <pod-ip>:<port>`.

**Symptom: 503 Service Unavailable**

The Ingress has no endpoints to route to. Verify the Service selector matches a Pod label, and that the Pod is `Running` with a passing readiness probe.

**Symptom: 404 Not Found**

The Ingress matched but no rule matches the requested path. Check the `path` and `pathType` in the Ingress rule.

## Comparison Table

| HTTP Error | Meaning | Kubernetes Cause |
|-----------|---------|------------------|
| 404 Not Found | Ingress matches but no rule for path | Ingress path mismatch |
| 502 Bad Gateway | Ingress reached Pod but it refused the connection | `targetPort` mismatch, or app bound to localhost |
| 503 Service Unavailable | Ingress has no Pods to route to | Endpoints empty (label mismatch or Pod crashing) |
| 504 Gateway Timeout | Ingress reached the Pod but no response in time | App is hung or overwhelmed |

## Interview Questions

**Q: Walk me through how a user's HTTP request reaches a Pod in Kubernetes.**

A: The user hits the Cloud LoadBalancer, which routes to the Ingress Controller. The Ingress Controller reads the HTTP Host/Path, matches an Ingress rule, and forwards to a Service. The Service's ClusterIP is intercepted by `kube-proxy`, which rewrites the destination IP to a healthy Pod IP. The Pod receives the traffic.

**Q: What is a 502 Bad Gateway in Kubernetes, and how do you troubleshoot it?**

A: A 502 means the Ingress Controller proxied the request but the upstream Pod refused the connection. I check `kubectl get endpoints` to confirm the Pod is registered, then check for a port mismatch between the Service `targetPort` and the Pod's `containerPort`.

**Q: What is the difference between a 502 and a 503 in Kubernetes?**

A: A 502 means the Ingress reached the Pod but the Pod refused the connection (usually a port mismatch). A 503 means the Ingress Controller has no Pods to route to because the Service Endpoints are empty (label mismatch or crashing Pods).

**Q: True or False: Ingress routes traffic directly to Pods.**

A: False. It routes to Services; the Service routes to Pods.

## Scenario Questions

**Scenario 1:** You deploy a new version. Users get 502s. The Pods are `Running` and `Ready`. What is the likely cause?

A: Since the Pods are Ready, Endpoints are populated. The issue is likely a port mismatch: the developer changed `containerPort` (for example, 8080 to 3000) but forgot to update the Service `targetPort`. The Ingress is sending traffic to the old port and the Pod refuses it.

**Scenario 2 (Mini Project - The 503 Simulator):**

1. Deploy an Nginx app with an Ingress and a Service; verify `curl` works.
2. Change the Service selector to a label that does not exist (e.g., `app: backend`).
3. Apply the broken Service and `curl` again — you should see `503 Service Unavailable`.
4. Fix the selector back to `app: frontend` and verify it works.

## Quiz

1. Which layer does an Ingress Controller operate at?
   - A. Layer 2
   - B. Layer 4 (TCP)
   - C. Layer 7 (HTTP)
   - D. Layer 8

2. What is the #1 cause of a 502 Bad Gateway in Kubernetes?
   - A. MySQL down
   - B. A `targetPort` and `containerPort` mismatch
   - C. A DNS TTL issue
   - D. Certificate expiry only

3. A 503 Service Unavailable in Kubernetes usually means:
   - A. A port mismatch
   - B. A certificate expired
   - C. The Service has no Endpoints
   - D. The load balancer is overloaded

4. Where does `kube-proxy` route the packet?
   - A. Directly to a Service
   - B. To the Ingress Controller
   - C. To the Pod IP behind the Service
   - D. To the cloud provider

5. True or False: Ingress routes traffic directly to Pods.
   - A. True
   - B. False

Answers: 1-C, 2-B, 3-C, 4-C, 5-B.

## Revision

One-minute revision:

- Cloud LB -> Ingress (L7) -> Service (L4) -> Pod.
- `502` = the Pod refused the connection (often a port mismatch).
- `503` = no Endpoints (Pods missing or crashing).
- Match `targetPort` to `containerPort`.

Memory trick:

- Ingress = the hotel receptionist.
- Service = the elevator.
- Pod = the guest room.
- `502` = you reached the right room but the door was locked (wrong port).

Key facts:

- Ingress routes to Services, not directly to Pods.
- Ingress Controllers only route to Pods that pass Readiness.
- Use named `targetPort` for flexibility.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl describe ingress <name>` | Check the backend Service and port |
| `kubectl get endpoints <svc>` | Check if the Service knows about the Pods |
| `kubectl get pod -l app=frontend -o yaml \| grep containerPort` | Check what port the app listens on |

## References

- [Kubernetes Documentation: Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Kubernetes Documentation: Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [NGINX Ingress Controller Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes Documentation: Ingress Concepts](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)

## Related Lessons

- [Lesson 8 - Networking Fundamentals and the CNI](lesson-13-networking-fundamentals-and-the-cni.md) - how Pod networking is created.
- [Lesson 9 - Services and Cluster Networking](lesson-14-services-and-cluster-networking.md) - the Service abstraction and kube-proxy.
- [Lesson 10 - Ingress and Ingress Controllers](lesson-15-ingress-and-ingress-controllers.md) - L7 routing and the NGINX controller.
- [Lesson 13 - Network Policies](lesson-16-network-policies.md) - how to segment traffic across Pods.

## Coming Next

In the next lesson we move to storage and persistent data, covering Volumes, Persistent Volumes, Persistent Volume Claims, and Storage Classes so stateful workloads survive rescheduling.