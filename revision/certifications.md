---
title: Revision - Certifications and Capstone
module: 14 Certifications
status: Complete
tags: [revision, certifications, cka, capstone, interview, career]
---

# Revision - Certifications and Capstone

## CKA / CKAD / CKS Core

- **CKA**: cluster administration, control plane, troubleshooting, etcd, upgrades.
- **CKAD**: application design and build (workloads, config, services).
- **CKS**: security hardening, RBAC, admission, image security.

Speed tools:

```bash
alias k=kubectl
export do='--dry-run=client -o yaml'
k run nginx --image=nginx $do > pod.yaml
```

## Key Facts to Recall

- etcd port: 2379
- API Server port: 6443
- node-monitor-grace-period: 40s; pod-eviction-timeout: 5m
- QoS Guaranteed: requests == limits on all containers
- Cilium: eBPF, no iptables
- `helm history <name>` shows release history

## The Senior Interview Mindset

- Everything is a control loop (GitOps, HPA, ReplicaSet, Rollouts).
- Speak in business outcomes: rollback time, cost, reliability.
- Three gates: core knowledge, production troubleshooting, behavioral (STAR).
- Never type `kubectl apply` in production; use GitOps.

## Related Lessons

- [Lesson 40 - CKA Exam Masterclass](../docs/14-certifications/lesson-40-cka-exam-masterclass.md)
- [Lesson 41 - Cluster Architecture and the Kubeconfig File](../docs/14-certifications/lesson-41-cluster-architecture-and-the-kubeconfig-file.md)
- [Lesson 42 - etcd Backup and Restore](../docs/14-certifications/lesson-42-etcd-backup-and-restore.md)
- [Lesson 47 - The Capstone](../docs/14-certifications/lesson-47-the-capstone-architecture-career-and-interview-mastery.md)

## Related Material

- [Interview - Capstone](../interview/capstone.md)
- [All Cheat Sheets](../cheatsheets/README.md)

[Back to Revision Index](README.md)