---
title: Lesson 17 - Services and Cluster Networking
module: 04 Networking
lesson: 17
status: Complete
tags: [kubernetes, services, endpoints, clusterip, nodeport, kube-proxy, iptables, coreDNS]
---

# Lesson 17 - Services and Cluster Networking

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

- Explain why Pod IPs are unreliable and why a Service is required.
- Describe how a ClusterIP Service provides a stable virtual IP and DNS name.
- Explain how Endpoints link a Service to the actual Pods.
- Describe how kube-proxy uses iptables to load-balance traffic.
- Deploy, expose, and debug a Service using kubectl.
- Recognize when to use ClusterIP versus NodePort versus LoadBalancer.

## Prerequisites

- Completion of Lesson 10 (understanding of Pods, Deployments, and Labels).
- A running Kubernetes cluster (see [Lesson 01](../01-fundamentals/lesson-01-anatomy-of-a-container.md) for kind setup instructions).
- kubectl installed and configured.

## Real-world Motivation

### The Moving Target

Imagine your frontend application needs to talk to your backend API. The backend is managed by a Deployment with 3 replicas.

1. The frontend sends a request to Backend Pod 1 (IP: 10.1.0.5).
2. Pod 1 crashes due to a bug. The ReplicaSet instantly creates Pod 4 (IP: 10.1.0.9).
3. The frontend doesn't know about the new IP. It tries to send traffic to 10.1.0.5 again. The connection times out. Users see 502 Bad Gateway errors.

### Why This Exists

Kubernetes needed a way to decouple the consumer of an application from the location of the application. A Service provides a single, stable IP address (and DNS name) that acts as a load balancer. The frontend only talks to the Service. The Service automatically tracks the shifting Pod IPs behind the scenes.

### Real Company Examples

**Uber:** When a user requests a ride, the mobile app hits a gateway, which routes to the "Trip Management Service" (a Kubernetes Service). That Service load-balances traffic to hundreds of Trip Management Pods. If a Pod crashes, the Service instantly stops sending traffic to it, and the user experience is unaffected.

**DoorDash:** DoorDash uses Services to decouple their microservices. The order-placement service communicates with the restaurant-menu service purely via ClusterIP DNS names. This allows the restaurant-menu team to scale and restart their Pods without notifying the order-placement team.

## Core Concepts

### Explain Like I'm 12

Imagine a hotel. Guests (Pods) check in and out every day, changing room numbers (IP addresses). If you want to send a letter to your friend in the hotel, you don't send it to their room number, because they might have checked out. Instead, you send it to the hotel Receptionist (Service). The Receptionist knows exactly which room your friend is in right now and forwards the letter to them.

### Explain Like I'm a Junior Engineer

A Service is a Kubernetes object that gives you a static IP address and DNS name. It sits in front of your Pods. When traffic hits the Service IP, it acts as a load balancer and forwards it to one of the healthy Pods behind it. It uses Label Selectors (just like ReplicaSets) to find which Pods belong to it.

### Explain Technically

- A Service is defined by a ClusterIP (a virtual IP).
- The EndpointController runs in the background. It continuously watches for Pods whose labels match a Service's selector. It collects the IP addresses of those Pods and stores them in an Endpoints object.
- kube-proxy runs on every node as a DaemonSet. It watches the API Server for changes to Endpoints objects. When an Endpoint changes, kube-proxy updates the node's Linux iptables NAT rules.
- When a process on the node sends a packet to the Service IP, the kernel intercepts it, looks up the iptables rules, randomly picks a Pod IP from the Endpoints list, and rewrites the destination IP (DNAT).

### How Kubernetes Implements It Internally

Kubernetes relies on CoreDNS. When you create a Service named `db-svc`, CoreDNS automatically creates a DNS A-record mapping `db-svc.default.svc.cluster.local` to the Service's ClusterIP. When a Pod resolves that DNS name, it gets the Service IP. Traffic sent to the Service IP is then hijacked by the kernel and routed to a real Pod IP.

### Why Kubernetes Was Designed That Way

A Service is not a physical proxy server running in the middle of your cluster. It is a virtual concept implemented by Linux kernel rules on every node. This design avoids a single point of failure and a bottleneck. There is no "Service Pod" sitting in the middle routing traffic. The Linux kernel does the routing directly, which is extremely fast.

## Architecture

```
[ Frontend Pod ]
      |
      v (Sends traffic to Service IP: 10.96.0.10)
[ Service (ClusterIP) ]  <--- Stable IP & DNS Name (my-app.default.svc.cluster.local)
      |
      | (kube-proxy writes iptables rules on the node)
      |
      +----------------+----------------+
      v                v                v
[ Pod 1: 10.1.0.5 ] [ Pod 2: 10.1.0.6 ] [ Pod 3: 10.1.0.7 ]
```

### Terminology

| Term | Definition |
|------|------------|
| ClusterIP | A virtual IP address assigned to a Service, reachable only from within the cluster. |
| NodePort | A port (30000-32767) opened on all nodes to expose a Service externally. |
| Endpoints | A list of actual Pod IPs and ports that back a Service. |
| EndpointSlices | A scalable replacement for Endpoints, splitting the list into smaller chunks for large clusters. |
| kube-proxy | The component that programs network routing rules (iptables/IPVS) on every node. |
| CoreDNS | The default DNS server in Kubernetes that resolves Service names to ClusterIPs. |
| DNAT | Destination Network Address Translation. The kernel rewrites the destination IP of a packet. |

### How It Works Internally

When you create a Service, the API Server assigns it a ClusterIP. The EndpointController sees the Service and its selector. It searches the cluster for Pods matching that selector. If it finds 3 Pods, it creates an Endpoints object containing those 3 IPs.

kube-proxy on Node A sees the new Service and the Endpoints. It writes iptables rules on Node A that say: "If a packet is destined for the ClusterIP on port 80, use the statistic module to randomly route it to one of the 3 Pod IPs."

If a Pod dies, the EndpointController removes its IP from the list. kube-proxy sees the update and deletes that specific iptables rule. Traffic is no longer sent to the dead Pod.

### Step-by-Step Workflow

1. Developer creates a Deployment with 3 Pods (label: `app=web`).
2. Developer creates a Service (selector: `app=web`, port: 80, targetPort: 8080).
3. API Server assigns the Service a ClusterIP (e.g., 10.96.0.10).
4. CoreDNS creates a DNS record mapping the Service name to 10.96.0.10.
5. EndpointController finds the 3 Pods (IPs: .5, .6, .7) and creates an Endpoints object.
6. kube-proxy programs iptables on all nodes: "ClusterIP:80 -> .5:8080, .6:8080, or .7:8080".
7. A client Pod sends traffic to 10.96.0.10:80. The kernel intercepts it and routes it to .6:8080.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | Service is created. ClusterIP is assigned. Endpoints are populated if matching Pods exist. |
| Scaling | If the Deployment scales up, new Pod IPs are added to the Endpoints list automatically. |
| Pod Failure | If a Pod crashes, its IP is removed from the Endpoints list instantly. |
| Deletion | Service is deleted. iptables rules are flushed. ClusterIP is returned to the pool. |

### Service Types Comparison

| Feature | ClusterIP | NodePort | LoadBalancer |
|---------|-----------|----------|--------------|
| Reachable from | Inside cluster only | Outside cluster (NodeIP:Port) | Public Internet |
| Port Range | Any | 30000-32767 | 80, 443, etc. |
| Cloud Cost | Free | Free | Costs money (Provisions a Cloud LB) |
| Production Use | Internal microservices | Debugging / Ingress backend | Public-facing apps (often replaced by Ingress) |

### Common Myths

| Myth | Fact |
|------|------|
| "A Service is a physical proxy server running in the cluster." | False. A Service is just a virtual IP and a set of distributed iptables (or IPVS) rules on the nodes. There is no "Service Pod" sitting in the middle routing traffic. The Linux kernel does the routing directly. |
| "Services secure traffic." | False. Any Pod in the cluster can talk to any Service. To restrict traffic, you must use Network Policies. |
| "ClusterIP is routable from outside the cluster." | False. ClusterIP is only reachable from within the cluster. Use NodePort or LoadBalancer for external access. |

## ASCII Diagrams

Mental Model: The Service is a Traffic Cop standing at an intersection. Cars (traffic) arrive at the Cop (Service IP). The Cop looks at the available lanes (Pods) and waves the car into an open lane.

```
[ Client Pod ] 
      | (Resolves DNS 'web-svc' -> 10.96.0.10)
      v (Sends packet to 10.96.0.10:80)
[ Linux Kernel (Node) ]
      | (iptables PREROUTING hook intercepts)
      v (KUBE-SVC-XXXX Chain)
[ Service Routing Rule ] (Matches port 80)
      | (Randomly selects an Endpoint)
      v (DNAT: Rewrite destination IP)
[ Pod 1: 10.1.0.5:8080 ]
```

### DNS Resolution Flow

```
[ Pod A ] 
      | (Asks CoreDNS: "What is web-svc.default.svc.cluster.local?")
      v
[ CoreDNS ] 
      | (Returns ClusterIP: 10.96.0.10)
      v
[ Pod A sends packet to 10.96.0.10:80 ]
      |
      v
[ kube-proxy iptables rules on Node ]
      |
      v
[ Pod B: 10.1.0.6:8080 ] (Selected randomly from Endpoints)
```

## Hands-on

### Objective

Deploy an application, expose it via a Service, verify routing, and debug a broken Service with no Endpoints.

### Step 1: Create the Deployment and Service

Create `service-lab.yaml`:

```yaml
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
```

### Step 2: Deploy

```bash
kubectl apply -f service-lab.yaml
```

### Step 3: Verify the Service and Endpoints

```bash
kubectl get svc web-svc
kubectl get endpoints web-svc
```

Expected: You will see the Service has a ClusterIP (e.g., 10.96.0.10). The Endpoints output will show 3 IP addresses separated by commas. These are your 3 Nginx Pods.

### Step 4: Test Internal Connectivity

Spawn a temporary Pod to act as a client:

```bash
kubectl run test-client --rm -it --image=alpine -- /bin/sh
```

Inside the temporary Pod, use wget to connect to the Service using its DNS name:

```bash
wget -qO- http://web-svc
```

Expected: You will see the standard Nginx "Welcome to nginx!" HTML output. Type `exit` to leave the Pod.

### Step 5: Test Self-Healing

While the test-client is running, delete one of the Nginx Pods:

```bash
kubectl delete pod <POD_NAME>
```

The wget loop never fails; the Service instantly routes traffic to the remaining healthy Pods.

### Step 6: Test Scaling

```bash
kubectl scale deployment web-deploy --replicas=5
kubectl get endpoints web-svc
```

The Endpoints list now shows 5 IPs.

### Step 7: Debug a Broken Service

Create a Service with a mismatched selector:

```yaml
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
```

```bash
kubectl apply -f broken-svc.yaml
kubectl get endpoints broken-svc
```

The Endpoints column shows `<none>`. The selector (`app: frontend`) doesn't match any Pods.

### Step 8: Cleanup

```bash
kubectl delete -f service-lab.yaml
kubectl delete -f broken-svc.yaml
```

## Commands

```bash
# Create a Service imperatively
kubectl expose deployment web-deploy --port=80 --target-port=8080

# List Services
kubectl get svc

# List Endpoints
kubectl get endpoints web-svc

# Describe a Service (shows selector and endpoints)
kubectl describe svc web-svc

# Test connectivity from a temporary Pod
kubectl run test-client --rm -it --image=alpine -- wget -qO- http://web-svc

# Check CoreDNS resolution inside a Pod
kubectl exec <pod-name> -- nslookup web-svc.default.svc.cluster.local

# Check kube-proxy iptables rules (on a node)
iptables -t nat -L KUBE-SVC-* -n
```

## YAML Explanation

```yaml
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
```

### Field-by-Field Explanation

- `kind: Service`: Defines a Kubernetes Service object.
- `spec.type: ClusterIP`: The default. Creates a virtual IP reachable only from inside the cluster.
- `spec.selector`: Key-value pairs to match Pods. The Service uses this to populate its Endpoints list.
- `spec.ports.port`: The port the Service listens on (the port other Pods connect to).
- `spec.ports.targetPort`: The port the container is listening on (must match `containerPort` in the Pod spec).

## Production Notes

- **Always use named ports.** In the Service, define `targetPort: http` instead of `targetPort: 80`. This allows you to change the container port without breaking the Service.
- **Use CoreDNS names, not IPs.** In your application config, connect to `backend-svc`, not the ClusterIP. IP subnets can change; DNS names are stable.
- **Do not use NodePort for production web apps.** NodePorts bind to high ports (30000+). Users expect traffic on port 80/443. Use an Ingress Controller (Lesson 18) to route port 80 traffic to your Services.
- **Every Deployment should have a Service.** Even if you don't need external access yet, having a Service makes internal communication stable.
- **Use Network Policies** to restrict which Pods can talk to which Services. Services alone do not secure traffic.

### When to Use / When NOT to Use

**Use a ClusterIP Service when:**

- Internal microservices need to communicate.
- You want stable DNS-based service discovery.
- Every Deployment in production should have a ClusterIP Service.

**Use a NodePort Service when:**

- Debugging or testing external access.
- You have an Ingress Controller that needs to route to your Services.
- Never for production web applications.

**Use a LoadBalancer Service when:**

- You need to expose a service directly to the public internet on a cloud provider.
- Often replaced by Ingress for HTTP/HTTPS traffic.

### Performance and Security Considerations

**Performance:** The default kube-proxy mode is iptables. It routes traffic in O(1) time but randomly selects Pods. For massive clusters (10,000+ Services), iptables becomes slow to update. Production clusters often switch to IPVS mode or use eBPF (via Cilium) for faster, weighted load balancing.

**Security:** Services do not secure traffic. Any Pod in the cluster can talk to any Service. To restrict traffic (e.g., block the marketing namespace from talking to the payments namespace), you must use Network Policies.

## Best Practices

- Use named ports in Service definitions for flexibility.
- Use CoreDNS names for service discovery, not ClusterIPs.
- Every Deployment should have a corresponding Service.
- Use Network Policies to restrict traffic between Services.
- Prefer ClusterIP for internal communication.
- Use Ingress for external HTTP/HTTPS traffic instead of NodePort.
- Monitor Endpoints to ensure Services have healthy backends.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Selector Mismatch | Service selector doesn't match Pod labels | Always verify with `kubectl get endpoints` |
| TargetPort Mismatch | Service targets port 8080 but container listens on 80 | Ensure targetPort matches containerPort |
| Exposing DBs via NodePort | Accidentally exposing a database to the public internet | Use ClusterIP for databases, restrict with Network Policies |
| Using ClusterIP for external traffic | Trying to reach ClusterIP from outside the cluster | Use Ingress or LoadBalancer for external access |

## Troubleshooting

**Symptom: Service has no Endpoints (`<none>`)**

Cause: The Service selector doesn't match any Pod labels.

```bash
kubectl describe svc web-svc | grep Selector
kubectl get pods --show-labels
```

Fix: Update the Service selector to match the Pod labels.

**Symptom: Connection times out when connecting to Service**

Cause: Endpoints exist but Pods are not ready, or targetPort is wrong.

```bash
kubectl get endpoints web-svc
kubectl describe pod <pod-name> | grep -A 5 Events
```

Fix: Ensure Pods are in `Running` state and the targetPort matches the container's listening port.

**Symptom: DNS resolution fails inside a Pod**

Cause: CoreDNS pods are not running or not reachable.

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl exec <pod-name> -- nslookup web-svc.default.svc.cluster.local
```

Fix: Ensure CoreDNS pods are running. Check pod DNS settings.

## Interview Questions

**Q: What is the difference between a Service and a Pod?**

A: A Pod is the actual running application instance. A Service is an abstraction that provides a stable network identity (IP and DNS) and load balances traffic across multiple Pod instances.

**Q: How does a Service know which Pods to send traffic to?**

A: The Service uses a selector (key-value pairs). It looks for Pods that have matching labels. The IPs of those matching Pods are stored in the Service's Endpoints list.

**Q: What happens if a Pod dies that is backing a Service?**

A: The EndpointController notices the Pod is gone and removes its IP from the Endpoints list. kube-proxy updates the node's iptables rules to stop sending traffic to the dead IP. The ReplicaSet creates a new Pod, whose IP is then added to the Endpoints list.

**Q: You create a Service, but when you try to connect to it, the connection hangs and eventually times out. What is the first command you run to debug this?**

A: I would run `kubectl get endpoints <service-name>`. If the ENDPOINTS column is empty or `<none>`, it means the Service selector doesn't match any Pod labels, so no traffic is being routed. I would then compare the Service selector with the Pod labels.

**Q: Can a Service route traffic to Pods in a different namespace?**

A: No. Selectors are namespace-scoped. A Service can only route to Pods in the same namespace. For cross-namespace communication, you need a different approach (e.g., an external name Service or an Ingress).

**Q: What is the difference between `port` and `targetPort` in a Service?**

A: `port` is the port the Service listens on (what other Pods connect to). `targetPort` is the port the container is listening on (where traffic is forwarded to). They can be different.

## Scenario Questions

**Scenario 1:** You have a Deployment with 5 replicas running a Node.js app on port 3000. You create a Service with `port: 80` and `targetPort: 3000`. A client Pod tries to connect to the Service but gets "Connection Refused". What is wrong?

A: The most likely issue is that the Service selector doesn't match the Pod labels. Check `kubectl get endpoints <service-name>`. If empty, fix the selector. If Endpoints exist, the container might not be listening on port 3000, or the Pod is not ready.

**Scenario 2:** You need to expose a database Service to an application running in a different namespace. How do you do this?

A: Services are namespace-scoped. You cannot directly route to a Service in another namespace using its short DNS name. Use the full DNS name: `<service-name>.<namespace>.svc.cluster.local`. Or use an ExternalName Service to alias it.

**Scenario 3 (Mini Project - The Self-Healing Network):**

Deploy an Nginx Deployment with 3 replicas. Create a ClusterIP Service for it. Start a test-client Pod. In the test-client Pod, run a continuous wget loop. While that is running, delete one of the Nginx Pods. Observe that the wget loop never fails; the Service instantly routes traffic to the remaining healthy Pods.

```bash
kubectl run test --image=alpine -- sh -c "while true; do wget -qO- http://web-svc; sleep 1; done"
```

## Quiz

1. What is a ClusterIP?
   - A. A public IP address
   - B. A virtual IP reachable only from inside the cluster
   - C. A physical proxy server
   - D. A DNS name

2. What does kube-proxy program on each node?
   - A. DNS records
   - B. iptables rules
   - C. Pod manifests
   - D. Network interfaces

3. What happens when a Pod backing a Service dies?
   - A. The Service stops working
   - B. The Pod's IP is removed from the Endpoints list
   - C. The ClusterIP changes
   - D. kube-proxy is restarted

4. What is the first thing to check when a Service has no traffic?
   - A. Pod logs
   - B. `kubectl get endpoints`
   - C. Node status
   - D. CoreDNS logs

5. Which Service type is used for internal microservice communication?
   - A. NodePort
   - B. LoadBalancer
   - C. ClusterIP
   - D. ExternalName

Answers: 1-B, 2-B, 3-B, 4-B, 5-C.

## Revision

One-minute revision:

- Pod IPs change constantly. You cannot rely on them.
- A Service provides a stable IP and DNS name.
- Services use Selectors to find Pods, and Endpoints to store their actual IPs.
- kube-proxy programs iptables on every node to intercept traffic sent to the Service IP and route it directly to a Pod IP.
- If a Service has no Endpoints, your selector and Pod labels don't match.

Memory trick:

- Service: The hotel receptionist.
- Endpoints: The guest list of who is currently in the hotel.
- kube-proxy: The mail carrier who reads the guest list to deliver letters.

Key facts:

- ClusterIP: internal only.
- NodePort: opens port 30000-32767 on every node.
- LoadBalancer: provisions a cloud load balancer.
- DNS: `<service-name>.<namespace>.svc.cluster.local`.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl expose deploy <name> --port=80` | Creates a Service imperatively |
| `kubectl get svc` | Lists Services |
| `kubectl get endpoints <name>` | Shows the Pod IPs backing a Service |
| `kubectl describe svc <name>` | Shows selectors and endpoints |
| `kubectl run test --rm -it --image=alpine -- sh` | Spawns a temporary test Pod |
| `nslookup <svc-name>.<ns>.svc.cluster.local` | Tests DNS resolution |

## References

- [Kubernetes Documentation: Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes Documentation: Service Networking](https://kubernetes.io/docs/concepts/services-networking/)
- [Kubernetes Documentation: EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/)
- [Kubernetes Documentation: DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Kubernetes Documentation: kube-proxy](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/)

## Related Lessons

- [Lesson 10 - Pods, ReplicaSets, and Deployments](../03-workloads/lesson-10-pods-replicasets-and-deployments.md) - how Pods and Deployments work.
- [Lesson 18 - Ingress and Ingress Controllers](lesson-18-ingress-and-ingress-controllers.md) - routing external HTTP traffic to Services.
- [Lesson 19 - Network Policies](lesson-19-network-policies.md) - restricting traffic between Services.
- [Module 07 - Security](../07-security/README.md) - RBAC and network security.

## Coming Next

Now that you understand how Services provide stable networking for Pods, the next lesson covers Ingress and Ingress Controllers, which route external HTTP/HTTPS traffic to your Services. You will learn how to expose your applications to the internet securely.
