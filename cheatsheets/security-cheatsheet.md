---
title: Security Cheat Sheet
topic: security
status: Complete
tags: [cheatsheet, security, rbac, service-account, pod-security, network-policy, admission]
---

# Security Cheat Sheet

Security is layered: RBAC (who can do what) + ServiceAccounts + Pod/container hardening + NetworkPolicies + admission control (Kyverno).

## RBAC Overview

```text
Role / ClusterRole  (permissions)
      ^
      |  RoleBinding / ClusterRoleBinding
      |
ServiceAccount / User / Group  (who)
```

- **Role**: namespaced permissions. **ClusterRole**: cluster-wide (or namespaced grant).
- **RoleBinding** grants within a namespace; **ClusterRoleBinding** cluster-wide.
- A ClusterRole can be bound to a RoleBinding in a namespace (grants its rules in that ns).

## Role / ClusterRole

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: dev
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: deploy-creator
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list"]
```

`resources` are plural resource names; verbs: `get`, `list`, `watch`, `create`, `update`, `patch`, `delete`, `deletecollection`, `impersonate`.

## RoleBinding / ClusterRoleBinding

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: dev
  name: read-pods
subjects:
- kind: ServiceAccount
  name: app-sa
  namespace: dev
- kind: User
  name: alice
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: deploy-all-ns
subjects:
- kind: ServiceAccount
  name: pipeline-sa
  namespace: cicd
roleRef:
  kind: ClusterRole
  name: deploy-creator
  apiGroup: rbac.authorization.k8s.io
```

## ServiceAccount

Every namespace has `default`. Pods run under a ServiceAccount; its token is mounted at `/var/run/secrets/kubernetes.io/serviceaccount`.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: dev
automountServiceAccountToken: false   # mount token only if needed
---
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  serviceAccountName: app-sa
  automountServiceAccountToken: false
  containers: [{name: app, image: nginx}]
```

```bash
kubectl create serviceaccount app-sa -n dev
kubectl get serviceaccounts -A
kubectl auth can-i create deployments -n dev --as=system:serviceaccount:dev:app-sa
kubectl auth can-i --list -n dev --as=system:serviceaccount:dev:app-sa
```

## Pod Security (Pod Security Standards)

Enforced via **Pod Security Admission** (replaces PSP) on namespaces, or via Kyverno. Three standards:

| Standard | What it allows |
|----------|----------------|
| `privileged` | unrestricted |
| `baseline` | least-restrictive common set; disallows privileged, host namespaces, etc. |
| `restricted` | most restrictive; non-root, drop all caps, seccomp, no hostPath, etc. |

```bash
kubectl label ns default pod-security.kubernetes.io/enforce=restricted
kubectl label ns default pod-security.kubernetes.io/enforce-version=latest
kubectl label ns default pod-security.kubernetes.io/audit=restricted
kubectl label ns default pod-security.kubernetes.io/warn=restricted
```

Modes: `enforce` (block), `audit` (log), `warn` (warn). Exemptions by username, runtimeClass, or namespace.

## Pod and Container Hardening

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: [ALL]
        add: [NET_BIND_SERVICE]
```

| Setting | Effect |
|---------|--------|
| `runAsNonRoot: true` | prevent running as root |
| `drop: [ALL]` | drop all Linux capabilities |
| `allowPrivilegeEscalation: false` | no setuid escalation |
| `readOnlyRootFilesystem: true` | read-only container fs |
| `seccompProfile: RuntimeDefault` | sane syscall filter |
| `readinessProbe` + health checks | keep only healthy pods serving |

## Image Security

```yaml
spec:
  containers:
  - name: app
    image: registry.example.com/app:v1.2.3
    imagePullPolicy: IfNotPresent
  imagePullSecrets:
  - name: regcred
```

Use explicit, immutable tags (or digests), scan images (Trivy), and sign images. Use `imagePullSecrets` for private registries.

## NetworkPolicy (see networking-cheatsheet.md)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api
spec:
  podSelector:
    matchLabels: {app: api}
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels: {app: web}
    ports:
    - protocol: TCP
      port: 8080
```

Default-deny in a namespace:

```yaml
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

## Admission Control and Kyverno

Admission controllers run on the API Server. Webhooks (validating/mutating) extend them; Kyverno is a policy-as-code engine.

```bash
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations
kubectl get kyvernoclusterpolicies # if Kyverno installed
```

Common policies: require non-root, force labels, ensure resource limits, block `latest` tags.

## etcd and Secrets at Rest

- Secrets are base64, not encrypted at rest by default.
- Enable `--encryption-provider-config` on the API Server (aescbc/aesgcm) to encrypt Secrets in etcd.

## Useful RBAC / security commands

```bash
kubectl get roles,rolebindings,clusterroles,clusterrolebindings -A
kubectl describe rolebinding <name>
kubectl auth can-i get pods --as=system:serviceaccount:ns:sa
kubectl auth can-i --list -A
kubectl create token app-sa -n dev   # request a service account token
kubectl describe pod <name>          # check SecurityContext and SA
kubectl get secrets
```
