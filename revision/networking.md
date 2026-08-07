---
title: Revision - Networking
module: 04 Networking
status: Complete
tags: [revision, networking, service, ingress, network-policy, cni, dns]
---

# Revision - Networking

## 1. The Mental Model

Kubernetes networking is five layers that each solve one problem:

1. **The CNI** builds the roads and gives every Pod its own unique IP address, so any Pod can reach any other directly (a flat network).
2. **The Service** is the receptionist. Pod IPs change, so it provides a stable virtual IP (ClusterIP) and DNS name in front of the shifting Pods.
3. **kube-proxy** is the mail sorter. It programs kernel rules (iptables/IPVS) that rewrite a packet's destination from the Service IP to a real Pod IP.
4. **The Ingress Controller** is the front-door for HTTP/HTTPS. It reads the Host header and URL path and routes each request to the right Service.
5. **NetworkPolicy** is the firewall. Kubernetes is allow-by-default, so restrict which Pods can talk to which by enabling policies via the CNI.

Traffic flows in order: Client -> Cloud LoadBalancer -> Ingress Controller (L7) -> Service (L4) -> kube-proxy DNAT -> Pod. When a hop breaks, the client sees an HTTP error like 502 or 503; your job is to walk each hop and find where it broke.

## 2. Core Concepts

### CNI and Pod IPs

The CNI is a plugin the kubelet calls when a Pod is created. It assigns the Pod its IP (IPAM), creates a virtual interface inside the Pod's network namespace, and programs the routing that lets Pods on different nodes talk. Common plugins:

- **Calico** - policy-focused, iptables or eBPF, strong NetworkPolicy support.
- **Cilium** - eBPF-based, fast, supports L7 NetworkPolicies and can even replace kube-proxy.
- **Flannel** - simple overlay only; does NOT enforce NetworkPolicies on its own.
- **kindnetd** - kind's minimal CNI for local clusters.

Key idea: Kubernetes does not route packets itself. The Linux kernel does; the CNI and kube-proxy only program the kernel's tables.

### Services and kube-proxy

A Service is not a physical proxy. It is a virtual IP plus distributed kernel rules on every node. The **EndpointController** watches for Pods whose labels match the Service selector and stores their IPs in an **Endpoints** object (scaled up via **EndpointSlices** in large clusters). **kube-proxy** watches those endpoints and writes rules:

- **iptables mode** (default): a `KUBE-SVC-XXXX` chain per Service matches the ClusterIP, then the `statistic` module picks a random `KUBE-SEP-YYYY` chain that performs DNAT (rewrites the destination to a real Pod IP). Evaluation is sequential, so huge clusters get slow.
- **IPVS mode**: Linux Virtual Server hash tables for O(1) lookups, faster for large clusters.
- **eBPF (Cilium)**: bypasses iptables entirely, the fastest option.

When a Service has **no Endpoints**, kube-proxy writes a REJECT rule, so the client gets an instant "Connection Refused" rather than a timeout.

Service types:

- **ClusterIP** (default) - internal-only virtual IP; use for microservice-to-microservice calls.
- **NodePort** - opens the same port from 30000-32767 on every node; use for debugging or as an Ingress backend, not for production web apps.
- **LoadBalancer** - provisions a cloud load balancer; one per Service, so expensive.
- **ExternalName** - returns a CNAME alias to an external DNS name; no ClusterIP, no selector.
- **Headless** (`clusterIP: None`) - no virtual IP; DNS resolves the actual Pod IPs, giving each Pod its own DNS name like `pod-0.db.default.svc.cluster.local`. This is how StatefulSets find their members.

### DNS and CoreDNS

CoreDNS runs in `kube-system` (as the `kube-dns` Service). It creates a record for every Service: `<name>.<namespace>.svc.cluster.local` resolves to the ClusterIP. Within a namespace use the short name `web-svc`; across namespaces use `web-svc.otherns.svc.cluster.local`.

### Ingress and Ingress Controllers

Ingress is a rules object; it does nothing by itself. You must install an **Ingress Controller** (NGINX, Traefik, AWS ALB, etc.) that watches for Ingress objects and programs its proxy. The controller routes by Host header and URL path (Layer 7) to a **Service** (Layer 4), which then routes to Pods. Ingress centralizes external HTTP/HTTPS access, TLS termination, and routing so you avoid one cloud load balancer per service.

### NetworkPolicy

A NetworkPolicy is enforced by the **CNI** (not the API server). The network is **allow all** by default. Listing a direction with no matching rules becomes **deny all** for that direction. `policyTypes: [Ingress]` governs incoming traffic to the selected Pods; `[Egress]` governs outgoing. A timeout usually means a policy is silently dropping packets; Connection Refused usually means the app is not listening.

### Service Mesh (Istio, Linkerd)

A Service Mesh moves network logic out of application code. An **init container** writes iptables rules that force all Pod traffic through a **sidecar proxy** (Envoy in Istio; a Rust proxy in Linkerd). The **data plane** is the proxies; the **control plane** (Istiod) distributes routing config and acts as a certificate authority. Features:

- **mTLS** - both client and server verify each other's certificates, so inter-service traffic is encrypted and authenticated (zero trust).
- **Weighted routing** - a VirtualService can send 90% to v1 and 10% to v2 for canary deployments.
- **Retries, timeouts, and tracing** - handled by the proxy, not the app code.

Start with PERMISSIVE mTLS (accepts encrypted and plain text) and move to STRICT only after every workload has a sidecar. The proxy adds 1-2ms latency and CPU/RAM per Pod, so it pays off mainly with many microservices.

## 3. Key Commands

```bash
# Services and Endpoints
kubectl get svc
kubectl get endpoints web-svc          # empty means selector mismatch or unhealthy Pods
kubectl describe svc web-svc
kubectl expose deployment web-deploy --port=80 --target-port=8080

# Test connectivity from a temporary client Pod
kubectl run test --rm -it --image=alpine -- wget -qO- http://web-svc

# DNS
kubectl exec <pod> -- nslookup web-svc.default.svc.cluster.local
kubectl get pods -n kube-system -l k8s-app=kube-dns

# kube-proxy internals (run inside a node, e.g. docker exec into a kind node)
iptables-save | grep KUBE-SVC
iptables-save | grep KUBE-SEP
kubectl get configmap -n kube-system kube-proxy -o yaml | grep mode

# Ingress
kubectl get ingress
kubectl describe ingress my-ingress
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx <controller-pod>

# NetworkPolicy
kubectl get networkpolicy -A
kubectl describe networkpolicy api-policy

# 502 flow
curl -v http://localhost/
kubectl get endpoints <svc>
kubectl get pod -l app=web -o yaml | grep containerPort
```

## 4. YAML Patterns (Service, Ingress, NetworkPolicy) with Field-by-Field Explanation

### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
```

- `spec.type` - `ClusterIP` (default), `NodePort`, `LoadBalancer`, `ExternalName`, or headless via `clusterIP: None`.
- `spec.selector` - the labels that identify the backing Pods. This is what populates the Endpoints list; a mismatch leaves Endpoints empty.
- `spec.ports[].port` - the port clients connect to on the Service IP.
- `spec.ports[].targetPort` - the port on the Pod the traffic is forwarded to. It must match the container's real listening port, or you get a 502.

### Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$1
spec:
  ingressClassName: nginx
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web
            port:
              number: 80
  tls:
  - hosts:
    - app.example.com
    secretName: web-tls
```

- `spec.ingressClassName` - selects which installed controller processes this Ingress.
- `spec.rules[].host` - optional; if present, only requests with that Host header match. Omit it to match all hosts.
- `path` and `pathType` - `Prefix` matches any URL starting with the path; `Exact` matches only that path.
- `backend.service.name` and `backend.service.port.number` - the target Service and its `port`. Ingress always routes to a Service, never directly to Pods.
- `spec.tls` - the host and the Kubernetes Secret holding the certificate; the controller terminates TLS here.
- `annotations` - controller hints; `rewrite-target: /$1` strips a captured path prefix before forwarding.

### NetworkPolicy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 8080
```

- `spec.podSelector` - the Pods this policy applies to. `{}` (empty) selects ALL Pods in the namespace.
- `spec.policyTypes` - the directions governed. If `Ingress` is listed but no `ingress` rules exist, incoming traffic is denied. Same logic for `Egress`.
- `spec.ingress[].from` - the allowed sources: `podSelector`, `namespaceSelector`, or `ipBlock`.
- `spec.ingress[].ports` - the allowed protocols and ports. If omitted from an ingress entry, all ports from the matched source are allowed.

To default-deny a whole namespace:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

## 5. How It Fits Together (traffic flow: pod->service->ingress, and DNS resolution)

### Pod to Service (internal)

1. Pod A asks CoreDNS for `web-svc.default.svc.cluster.local` and receives the ClusterIP (for example, 10.96.0.10).
2. Pod A sends a packet to 10.96.0.10:80. The kernel's PREROUTING hook intercepts it, matches the `KUBE-SVC` chain for that ClusterIP, and DNATs the destination to one of the Pod IPs from the Endpoints list.
3. The CNI routes the rewritten packet to the target Pod, which replies (source NAT returns the reply).

### External request through Ingress

1. Client resolves `app.example.com` and sends HTTP to the cloud load balancer, which forwards port 80/443 to the Ingress Controller Pods.
2. The controller reads the Host header and URL path, matches the Ingress rule, and proxies the request to the backend Service (`web:80`).
3. kube-proxy DNATs the ClusterIP to a healthy Pod; the Pod only receives traffic once it passes its readiness probe.

### DNS resolution chain

`Pod -> CoreDNS -> A record -> ClusterIP -> kube-proxy DNAT -> Pod IP`. If any egress NetworkPolicy blocks UDP/TCP port 53, DNS breaks and Pods cannot resolve Service names at all.

## 6. Common Mistakes and Gotchas

- **Selector mismatch** - Service selector does not match the Pod labels, so Endpoints is empty.
- **`targetPort` mismatch** - the Service targets a port the container does not listen on; the Pod refuses it and the Ingress returns 502.
- **App bound to `localhost`** - only accepts intra-container traffic; bind to `0.0.0.0` instead.
- **No Ingress Controller installed** - an Ingress object without a controller silently does nothing.
- **`ingressClassName` missing** - modern controllers may ignore Ingress resources without a class.
- **Default-deny Egress without DNS** - blocking all egress breaks CoreDNS on port 53; always allow DNS to kube-system.
- **Services do not provide security** - Services only load-balance; use NetworkPolicy to filter traffic.
- **Namespaces do not isolate traffic** - they are logical grouping, not a network boundary; Pods in different namespaces can talk unless a policy blocks them.
- **Selectors are namespace-scoped** - a Service only selects Pods in its own namespace; cross-namespace access needs the full DNS name.
- **Timeout vs Connection Refused** - a timeout is a firewall (NetworkPolicy) drop; Connection Refused means no app is listening.
- **iptables at scale** - sequential O(n) evaluation slows with many Services; use IPVS or Cilium eBPF.
- **STRICT mTLS too early** - STRICT drops plain-text traffic before every workload has a sidecar.
- **Ingress as a single bottleneck** - run multiple controller replicas with resource requests and limits.

## 7. Quick Troubleshooting (symptom -> cause -> fix, especially Services and 502)

**Symptom: `kubectl get endpoints web-svc` shows `<none>`**

- Cause: Service selector does not match the Pod labels, or the Pods are not Ready.
- Fix: compare `kubectl describe svc <name> | grep Selector` against `kubectl get pods --show-labels`, then align labels.

**Symptom: connection to a Service hangs then times out**

- Cause: Endpoints exist but Pods are not Ready, or a NetworkPolicy is silently dropping packets.
- Fix: check `kubectl get endpoints` and Pod readiness; review the namespace's NetworkPolicies.

**Symptom: DNS resolution fails inside a Pod**

- Cause: CoreDNS is down, or an egress policy blocks port 53.
- Fix: `kubectl get pods -n kube-system -l k8s-app=kube-dns`; add an egress rule allowing UDP/TCP 53 to kube-system.

**Symptom: 502 Bad Gateway from the Ingress**

- Cause: the Ingress reached the Pod but the Pod refused the connection, usually a `targetPort` mismatch or the app bound to localhost.
- Fix flow: (1) `kubectl describe ingress <name>` - confirm the right Service and port; (2) `kubectl get endpoints <svc>` - if populated, routing reaches the Pod; (3) compare Service `targetPort` with the Pod's real listening port; (4) exec into a utility Pod and `curl <pod-ip>:<port>` to prove the app is reachable.

**Symptom: 503 Service Unavailable from the Ingress**

- Cause: the Service has no healthy Endpoints (selector mismatch, crashing Pods, or failing readiness probe), so the controller has no upstream.
- Fix: fix the selector or the Pods; only Ready Pods join Endpoints.

**Symptom: 404 Not Found from the Ingress**

- Cause: no Ingress rule matches the requested path or host.
- Fix: check `path`, `pathType`, and `host` in the Ingress rules; confirm the controller picked up the change.

**Symptom: Ingress does nothing after applying YAML**

- Cause: no Ingress Controller installed.
- Fix: install NGINX or Traefik and confirm `kubectl get pods -n ingress-nginx` is Running.

**Symptom: traffic flows even after applying a NetworkPolicy**

- Cause: the CNI does not enforce NetworkPolicies (for example, Flannel alone).
- Fix: install a policy-capable CNI such as Calico or Cilium.

**Symptom: 503 inside a service mesh**

- Cause: missing sidecar (namespace not labeled) or STRICT mTLS with a workload that has no proxy.
- Fix: `kubectl get pod <pod> -o yaml | grep istio-proxy`; run `istioctl analyze`; start with PERMISSIVE mTLS.

## 8. 30-Second Recap

- CNI gives every Pod a unique IP and a flat network; the kernel routes, plugins program.
- Services give Pods a stable ClusterIP and DNS name; Endpoints list the real Pod IPs; kube-proxy DNATs via iptables (or IPVS/eBPF).
- Service types: ClusterIP (internal), NodePort (30000-32767 on every node), LoadBalancer (cloud LB), ExternalName (CNAME), headless (`clusterIP: None` for StatefulSets).
- DNS: `<name>.<namespace>.svc.cluster.local` resolved by CoreDNS.
- Ingress = L7 rules; Ingress Controller = the software (NGINX/Traefik) that executes them; always routes to a Service.
- NetworkPolicy = CNI-enforced firewall; default is allow-all; `podSelector: {}` + `policyTypes: [Ingress, Egress]` = default deny.
- Service Mesh = sidecar proxies (data plane) + control plane; provides mTLS and weighted canary routing.
- 502 = Pod refused the connection (check `targetPort`); 503 = no Endpoints; timeout = policy drop; 404 = no matching Ingress rule.

## Related Lessons

- [Lesson 16 - Networking Fundamentals and the CNI](../docs/04-networking/lesson-16-networking-fundamentals-and-the-cni.md)
- [Lesson 17 - Services and Cluster Networking](../docs/04-networking/lesson-17-services-and-cluster-networking.md)
- [Lesson 18 - Ingress and Ingress Controllers](../docs/04-networking/lesson-18-ingress-and-ingress-controllers.md)
- [Lesson 19 - Network Policies](../docs/04-networking/lesson-19-network-policies.md)
- [Lesson 33 - End-to-End Traffic Flow and the 502 Bad Gateway](../docs/04-networking/lesson-33-end-to-end-traffic-flow-and-the-502-bad-gateway.md)
- [Lesson 37 - Service Mesh (Istio and Linkerd)](../docs/04-networking/lesson-37-service-mesh-istio-and-linkerd.md)

## Related Material

- [Networking Cheat Sheet](../cheatsheets/networking-cheatsheet.md)
- [Interview - Networking](../interview/networking.md)

[Back to Revision Index](README.md)
