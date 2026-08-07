# Module 02 - Architecture

## Overview

Module 02 goes inside the cluster. It explains the control plane and worker node components, how the Kubernetes API server works, and how a request flows end to end through the system. A solid understanding of the architecture is what separates users from operators.

## Lessons

| Lesson | Title | Status |
|--------|-------|--------|
| 3 | [Controlling Where Pods Run (Scheduling and Taints)](lesson-03-worker-node-architecture.md) | Complete |
| 4 | [Pod Priority and Preemption](lesson-04-pod-priority-and-preemption.md) | Complete |
| 5 | [Node Affinity and Pod Anti-Affinity](lesson-05-node-affinity-and-anti-affinity.md) | Complete |

## Learning Outcomes

After completing this module you will be able to:

- Identify every control plane component and its role
- Identify every worker node component and its role
- Explain the API server, etcd, and the controller loop
- Trace a request from kubectl to a running pod and back

## Prerequisites

- [Module 01 - Fundamentals](../01-fundamentals/README.md)

## Related Material

- Diagrams: [diagrams/](../../diagrams/README.md)

## Next Module

[Module 03 - Workloads](../03-workloads/README.md) - the Pod and the controllers that manage it.

[Back to Documentation Hub](../README.md)
