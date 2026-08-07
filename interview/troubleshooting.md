---
title: Interview - Troubleshooting
module: 13 Troubleshooting
status: Complete
tags: [interview, troubleshooting, debugging, logs, diagnosis]
---

# Interview - Troubleshooting

## Beginner

**Q: Where do you start when a Pod is failing?**

A: `kubectl get pods`, then `kubectl describe pod <name>` for events and conditions, then `kubectl logs <pod>`. Work outside-in: Service -> endpoints -> Pod -> container.

**Q: What does `kubectl logs --previous` do?**

A: For a CrashLoopBackOff container, it reads the logs of the previous (crashed) instance. The current logs are empty because the container just restarted, so the real error is in the previous logs.

## Intermediate

**Q: A Service is not routing traffic. How do you debug?**

A: Check `kubectl get endpoints <svc>` (empty = selector mismatch or Pods not Ready), verify Pods are Running/Ready, confirm the Service `targetPort` matches the container port, then probe the Pod IP directly and check NetworkPolicy/DNS.

**Q: A node is NotReady with DiskPressure. What is happening?**

A: The node's disk is over the eviction threshold. The kubelet is evicting Pods. Investigate large volumes, logs, and images; then compact/clean up or add capacity.

**Q: How do you identify which Pods are on a node?**

A: `kubectl get pods -A -o wide | grep <node>` or `--field-selector spec.nodeName=<node>`.

## Scenario

Q: The API server is reachable but a Service suddenly 502s. Step by step.

A: Check the Ingress/Service endpoints and the backing deployment; see if Pods crashed (`describe`), the targetPort is correct, and the app is actually listening. Use `kubectl get endpoints`, `kubectl top pod`, and event logs.

## Related

- [Revision - Troubleshooting](../revision/troubleshooting.md)
- [Lesson 17 - End-to-End Traffic Flow and the 502 Bad Gateway](../docs/04-networking/lesson-17-end-to-end-traffic-flow-and-the-502-bad-gateway.md)

[Back to Interview Index](README.md)