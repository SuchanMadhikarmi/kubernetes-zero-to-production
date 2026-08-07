---
title: Interview - Security
module: 07 Security
status: Complete
tags: [interview, security, rbac, service-account, pod-security, admission]
---

# Interview - Security

## Beginner

**Q: What is RBAC?**

A: Role-based access control. Roles define permissions; bindings attach them to subjects (ServiceAccounts, users, groups). Namespaced (Role/RoleBinding) or cluster-wide (ClusterRole/ClusterRoleBinding).

**Q: What is a ServiceAccount?**

A: An identity for Pods to authenticate with the API Server. Its token is mounted at `/var/run/secrets/kubernetes.io/serviceaccount`; Pods can use it for API calls.

## Intermediate

**Q: How do you verify if a user can create deployments?**

A: `kubectl auth can-i create deployments --as=<user-or-sa>`. For an SA: `--as=system:serviceaccount:<ns>:<sa>`.

**Q: What are Pod Security Standards?**

A: Three tiers - privileged, baseline, restricted - enforced by Pod Security Admission via namespace labels (`pod-security.kubernetes.io/enforce=restricted`). Restricted requires non-root, dropping capabilities, and seccomp.

## Advanced

Q: How do you harden a container image at the Pod level?

A: Set `runAsNonRoot: true`, `runAsUser`, drop all capabilities with `capabilities.drop: [ALL]`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, and a RuntimeDefault seccomp profile. Enforce these centrally with Kyverno policies.

## Scenario

Q: A Pod is rejected by admission. Where do you look?

A: The event on the Pod and the webhook/admission controller (Kyverno policy, Pod Security label, or `LimitRange`). Check `kubectl describe pod`, then the relevant policy and namespace labels.

## True/False

- A ClusterRole can be bound within a namespace using a RoleBinding. (True)
- Secret values are encrypted at rest in etcd by default. (False - they are base64; encryption must be enabled.)

## Related

- [Revision - Security](../revision/security.md)
- [Lesson 27 - RBAC and Service Accounts](../docs/07-security/lesson-27-rbac-and-service-accounts.md)

[Back to Interview Index](README.md)