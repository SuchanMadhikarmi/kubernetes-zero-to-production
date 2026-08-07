---
title: Interview - Networking
module: 04 Networking
status: Complete
tags: [interview, networking, service, ingress, network-policy, dns]
---

# Interview - Networking

## Beginner

**Q: How does a Pod get its IP?**

A: The CNI plugin assigns each Pod an IP on a flat network namespace via, e.g., Calico or Cilium.

**Q: What is a Service?**

A: A stable network abstraction (ClusterIP) in front of Pods, so their IPs can change without breaking callers. kube-proxy implements traffic forwarding.

## Intermediate

**Q: Traffic reaches a Service but fails. Walk me through the debug flow.**

A: First `kubectl get endpoints <svc>` - empty means the selector does not resolve or Pods are not Ready. Then check Pods are running and Ready, exec into a pod and `curl <pod-ip>:<port>`, and check the targetPort matches the container. Verify DNS and NetworkPolicy along the path.

**Q: What is a headless service and when is it used?**

A: A Service with `clusterIP: None`. It returns Pod IPs directly and creates per-Pod DNS A records (e.g. `db-0.db.svc.cluster.local`) so StatefulSet peers can address each other directly instead of random load balancing.

**Q: What does the Ingress Controller do?**

A: An Ingress manifest holds routing rules; the controller (NGINX, Traefik) runs them, terminating TLS and routing HTTP(S) to the right Service by host/path. Ingress is only a rule without a controller.

## Advanced

Q: NetworkPolicy refused. What is its effect?

A: It filters Pod-to-Pod traffic enforced by the CNI. `podSelector: {}` with `policyTypes: [Ingress, Egress]` defaults-deny a namespace; you then allow specific sources/destinations.

## Scenario

Q: A web app returns 502 via the Ingress. How do you fix it?

A: It is a Gateway server error, likely the backend Service has no healthy endpoints. Check `kubectl get endpoints`, Pod readiness, then confirm the app is listening on the expected targetPort (curl the Pod IP).

## Related

- [Revision - Networking](../revision/networking.md)
- [Lesson 18 - Ingress and Ingress Controllers](../docs/04-networking/lesson-18-ingress-and-ingress-controllers.md)

[Back to Interview Index](README.md)