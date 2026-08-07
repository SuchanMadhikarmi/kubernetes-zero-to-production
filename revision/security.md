---
title: Revision - Security
module: 07 Security
status: Complete
tags: [revision, security, rbac, service-account, pod-security, admission]
---

# Revision - Security

## Core Ideas (Defense in Depth)

- **RBAC**: Role/ClusterRole + RoleBinding/ClusterRoleBinding + ServiceAccount/User.
- Roles grant verbs (`get`, `list`, `watch`, `create`, `update`, `patch`, `delete`) on resources.
- **ServiceAccounts** identify Pods; tokens mount at `/var/run/secrets/kubernetes.io/serviceaccount`.
- **Pod Security**: `pod-security.kubernetes.io/enforce=restricted` namespace labels (privileged / baseline / restricted).
- **Pod/container hardening**: SecurityContext with non-root, cap drop, read-only root fs, seccomp.
- **Admission control** (Kyverno) enforces policy at request time.

## RBAC Pattern

```yaml
roleRef:
  kind: Role            # or ClusterRole
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

```bash
kubectl auth can-i --list
kubectl auth can-i get pods --as=system:serviceaccount:dev:app-sa
kubectl get roles,rolebindings,clusterroles,clusterrolebindings -A
```

## Hardening a Pod

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
  - name: app
    image: nginx
    securityContext:
      allowPrivilegeEscalation: false
      capabilities: {drop: [ALL]}
      readOnlyRootFilesystem: true
```

## Related Lessons

- [Lesson 27 - RBAC and Service Accounts](../docs/07-security/lesson-27-rbac-and-service-accounts.md)
- [Lesson 31 - Locking Down the Container Security Contexts](../docs/07-security/lesson-31-locking-down-the-container-security-contexts.md)

## Related Material

- [Security Cheat Sheet](../cheatsheets/security-cheatsheet.md)
- [Interview - Security](../interview/security.md)

[Back to Revision Index](README.md)