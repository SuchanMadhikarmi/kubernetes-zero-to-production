---
title: Interview - Capstone and Certifications
module: 14 Certifications
status: Complete
tags: [interview, capstone, cka, career, STAR]
---

# Interview - Capstone and Certifications

## The Three Interview Gates

1. **Core knowledge** - rapid-fire conceptual questions (e.g., `kubectl run` flow).
2. **Production troubleshooting** - scenario debugging (e.g., 502s).
3. **Behavioral / incident** - "Tell me about a time you handled production." Use the STAR method.

## STAR Method

**Situation, Task, Action, Result.** Structure incidents that way: set the context, state your task, explain the specific action, and quantify the result (e.g., "reduced time to detect by 80%").

## Quick Facts to Recall

| Fact | Value |
|------|-------|
| etcd port | 2379 |
| API Server | 6443 |
| node-monitor-grace-period | 40s (NotReady) |
| pod-eviction-timeout | 5m |
| QoS class | Guaranteed = requests == limits |
| CNI with eBPF | Cilium |
| Helm history command | `helm history <name>` |

## Portfolio Blueprint

- Public repo: your Helm charts, GitHub Actions pipeline, ArgoCD/GitOps config.
- A README explaining the architecture diagram (CI -> Git -> ArgoCD -> K8s -> Ingress -> Pod).
- Sanitized examples: no proprietary manifests or secrets.
- Link it on LinkedIn and your resume. Target Platform Engineering and SRE roles.

## Common myths

- You must know Go? No: controllers are Go, but most Kubernetes engineering is YAML, Helm, and infrastructure.
- You need a CS degree? No. Systems and self-taught DevOps backgrounds are common.

## Related

- [Revision - Certifications](../revision/certifications.md)
- [Lesson 47 - The Capstone](../docs/14-certifications/lesson-47-the-capstone-architecture-career-and-interview-mastery.md)

[Back to Interview Index](README.md)