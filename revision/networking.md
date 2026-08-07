---
title: Revision - Networking
module: 04 Networking
status: Complete
tags: [revision, networking, service, ingress, network-policy, cni, dns]
---

# Revision - Networking

## Core Ideas

- **CNI** gives every Pod its own IP (flat network): Calico, Cilium, Flannel.
- **Service** provides a stable virtual IP (ClusterIP) in front of Pods. kube-proxy programs iptables/ipvs DNAT.
- **Ingress** routes external HTTP/HTTPS by host/path; needs an Ingress Controller (NGINX, Traefik, etc.).
- **NetworkPolicy** is pod-to-pod traffic filtering enforced by the CNI.
- **CoreDNS** resolves service names to `svc.namespace.svc.cluster.local`.

## Service Types

| Type | Purpose |
|------|---------|
| ClusterIP | Default; internal-only virtual IP |
| NodePort | Expose on `nodeIP:nodePort` (30000-32767) |
| LoadBalancer | Cloud LB in front |
| ExternalName | CNAME to external DNS |
| Headless (`clusterIP: None`) | per-Pod DNS for StatefulSets |

```yaml
spec:
  selector: {app: web}
  ports:
  - port: 80
    targetPort: 8080
```

## NetworkPolicy

```yaml
spec:
  podSelector: {matchLabels: {app: api}}
  policyTypes: [Ingress, Egress]
  ingress:
  - from:
    - podSelector: {matchLabels: {app: web}}
    ports: [{protocol: TCP, port: 8080}]
```

Default-deny a namespace: `podSelector: {}` with `policyTypes: [Ingress, Egress]`.

## Debugging Flow (Service Down)

1. `kubectl get endpoints <svc>` empty? selector mismatch or Pods not Ready.
2. Test Pod IP directly.
3. Check CoreDNS health.
4. Walk Ingress -> Service -> Pod.

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