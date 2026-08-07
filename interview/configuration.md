---
title: Interview - Configuration
module: 06 Configuration
status: Complete
tags: [interview, configuration, configmap, secret, resources, quota]
---

# Interview - Configuration

## Beginner

**Q: What is a ConfigMap?**

A: A resource for storing non-secret configuration as key/value pairs, injected into Pods as environment variables or mounted files.

**Q: What is the difference between ConfigMap and Secret?**

A: Secrets are intended for sensitive data and are base64-encoded in `data` (with plain `stringData` in manifests). Both are used the same way, but Secrets should be encrypted at rest and managed carefully.

## Intermediate

**Q: How do you inject a Secret into a Pod?**

A: As env vars via `secretKeyRef` or `envFrom`, or mounted as a volume. The token path `/var/run/secrets/kubernetes.io/serviceaccount` is the ServiceAccount token.

**Q: What happens when you change a ConfigMap?**

A: Mounted volumes update after a short delay. Env vars are set at Pod start and do not update until the Pod is recreated.

**Q: What are resource requests and limits?**

A: Requests reserve CPU/memory for scheduling and guarantee baseline; limits cap usage (a memory limit can OOM-kill the container; CPU is throttled). Requests also drive the HPA.

## Advanced

Q: What is the QoS class of a Pod with no resources set?

A: BestEffort. Guaranteed requires requests equal to limits for CPU and memory on all containers; everything between is Burstable. Under pressure, BestEffort is evicted first.

## Scenario

Q: Your app is killed with OOMKilled. How do you fix it?

A: Check memory usage with `kubectl top pod`, raise the container memory `limits` and `requests` (and the app's heap limits), or investigate a memory leak. Never set a memory limit lower than the app needs.

## Related

- [Revision - Configuration](../revision/configuration.md)
- [Lesson 21 - Resource Management and the OOMKiller (Requests vs Limits)](../docs/06-configuration/lesson-21-resource-requests-limits-and-quotas.md)

[Back to Interview Index](README.md)