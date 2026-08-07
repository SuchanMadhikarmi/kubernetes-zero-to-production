---
title: Networking Cheat Sheet
topic: networking
status: Complete
tags: [cheatsheet, networking, service, ingress, network-policy, cni, dns]
---

# Networking Cheat Sheet

## The Data Path

```text
Client -> Cloud LB -> Ingress Controller -> Service (ClusterIP) -> Pod IP -> Container
```

- Pod-to-Pod: flat network via the CNI (every Pod gets a real IP).
- Pod-to-Service: kube-proxy programs iptables/ipvs DNAT rules from ClusterIP to backing Pod IPs.
- DNS: CoreDNS resolves Service names (`svc.namespace.svc.cluster.local`).

## Service Types

| Type | Use | Behavior |
|------|-----|----------|
| `ClusterIP` | Default. Internal only | Stable virtual IP; load balances to backing Pods |
| `NodePort` | External access without a cloud LB | Exposes on `nodeIP:nodePort` (30000-32767) |
| `LoadBalancer` | Cloud-provider external IP | Creates cloud LB that forwards to NodePort/ClusterIP |
| `ExternalName` | Map to external DNS/CNAME | No Pods; returns CNAME |

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: ClusterIP            # ClusterIP | NodePort | LoadBalancer | ExternalName
  selector:
    app: web
  ports:
  - port: 80                 # service port (ClusterIP:80)
    targetPort: 8080         # container port on the Pod
    nodePort: 30080          # only for type: NodePort
  sessionAffinity: None      # or ClientIP (sticky sessions)
```

```bash
kubectl get svc
kubectl get endpoints <svc>          # backing Pod IPs (empty = selector/probe problem)
kubectl describe svc <name>
kubectl expose pod <name> --port=80 --target-port=8080 --type=ClusterIP
kubectl port-forward svc/web 8080:80
```

## Headless Service (StatefulSet DNS)

```yaml
spec:
  clusterIP: None
  selector:
    app: db
```

Gives per-Pod A records: `db-0.db.default.svc.cluster.local`. Used by StatefulSets so peers can address each other directly instead of random load balancing.

## Ingress and Ingress Controllers

Ingress routes external HTTP/HTTPS traffic by host/path. It is only rules; an Ingress Controller (NGINX, Traefik, HAProxy, Contour, AWS ALB) must run in the cluster.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx        # optional; binds to a controller class
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /v1
        pathType: Prefix
        backend:
          service:
            name: api
            port:
              number: 80
  tls:
  - hosts: [app.example.com]
    secretName: app-tls
```

`pathType` values: `Prefix` (longest-prefix match), `Exact`, `ImplementationSpecific`.

```bash
kubectl get ingress
kubectl describe ingress <name>
kubectl create ingress web --rule=app.example.com/=web:80 --class=nginx
```

## Network Policy

NetworkPolicy is default-deny style isolation enforced by the CNI (Calico, Cilium). It filters Pod-to-Pod traffic.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress, Egress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: db
    ports:
    - protocol: TCP
      port: 5432
```

```bash
kubectl get networkpolicies -A
kubectl describe networkpolicy <name>
kubectl create -f policy.yaml
```

Rules of thumb:

- Empty `podSelector: {}` targets all Pods in the namespace.
- `ipBlock` targets external CIDRs.
- A Policy with only `Ingress` in `policyTypes` leaves egress open.
- Ingress on Namespace objects is not supported; use `namespaceSelector`.

## DNS and Service Discovery

```text
<service>.<namespace>.svc.cluster.local
<service>.<namespace>.svc.cluster.local:<port>
pod-ip.with.dashes.<namespace>.pod.cluster.local   # pod hostname (rare)
```

```bash
kubectl run tmp --image=busybox --rm -it --restart=Never -- nslookup web.default.svc.cluster.local
kubectl get configmap -n kube-system coredns -o yaml
kubectl rollout restart -n kube-system deployment/coredns
```

Pod uses `search` domain suffixes so `web` resolves within its namespace.

## Service Mesh (Istio flavor)

Istio injects a sidecar (Envoy) into each Pod; the mesh handles mTLS and advanced routing, and east-west (service-to-service) traffic.

```yaml
# Enable a namespace for auto-injection
kubectl label namespace default istio-injection=enabled
```

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: web
spec:
  hosts: [web]
  http:
  - route:
    - destination:
        host: web
        subset: v1
      weight: 90
    - destination:
        host: web
        subset: v2
      weight: 10
```

Istio canary = split traffic weight between subsets without touching Service or Deployment. Argo Rollouts can drive these weights automatically.

## CNI Quick Reference

| CNI | Notes |
|-----|-------|
| Calico | Network policies, BGP; mature policy engine |
| Cilium | eBPF data path, no iptables, policy, observability |
| Weave | Simpler, smaller clusters |
| Flannel | Simple overlay; no NetworkPolicy by default |

## Connectivity Debugging

```bash
kubectl get endpoints -A
kubectl get svc -A -o wide
kubectl describe pod <name> | grep -A5 Events
kubectl exec -it <util-pod> -- curl -v http://<svc>:<port>
kubectl exec -it <util-pod> -- nc -zv <pod-ip> <port>
kubectl get pods -o wide
```

Check firewall of target container, Service selector labels, and readiness of backing Pods.

## Common Commands at a Glance

```bash
kubectl get svc,ep -A
kubectl get ingress -A
kubectl get networkpolicies -A
kubectl port-forward svc/<svc> 8080:80
kubectl run curl --image=curlimages/curl --rm -it --restart=Never -- sh
```
