---
title: Revision - Security
module: 07 Security
status: Complete
tags: [revision, security, rbac, service-account, pod-security, admission]
---

# Revision - Security

## 1. The Mental Model

Security is layered: **Identity** (who are you?), **Authorization** (what may you do?), **Restriction** (what can the process itself do?).

- **ServiceAccount** = an ID badge the kubelet pins to your Pod. The Pod uses it to talk to the API Server.
- **Role / ClusterRole** = the rulebook (which verbs are allowed on which resources).
- **RoleBinding / ClusterRoleBinding** = the lanyard that attaches the rulebook to an identity.
- **RBAC is deny-by-default**: nothing is allowed unless a rule explicitly grants it. A denied request returns **403 Forbidden**.
- **RBAC only controls the API Server**, not network traffic between Pods. Pod-to-Pod traffic is controlled by Network Policies.
- **SecurityContext** = the straitjacket on the container itself. It tells the Linux kernel how the process may run (UID, capabilities, read-only filesystem, syscalls).
- RBAC and SecurityContexts are complementary: RBAC gates *requests*, SecurityContexts limit the *process* if it is compromised.

## 2. Core Concepts

### Authentication vs Authorization

| Concept | Question | Mechanism | Example |
|---------|----------|-----------|---------|
| Authentication | Who are you? | Validates the identity/token | API server validates the ServiceAccount Bearer token; does a user's client cert chain to a trusted CA |
| Authorization | What may you do? | Evaluates RBAC rules | Does this identity have `list` on `pods` in this namespace? |

Authentication always happens first; if it fails you get **401 Unauthorized** (bad identity). Authorization happens after; if it fails you get **403 Forbidden** (known identity, insufficient permission).

### RBAC objects

| Object | Scope | Grants |
|--------|-------|--------|
| Role | One namespace | Rules for namespaced resources |
| ClusterRole | Entire cluster | Rules for any resource (Nodes, PVs) OR namespaced resources across all namespaces |
| RoleBinding | One namespace | Binds a Role (or ClusterRole) to a user/group/ServiceAccount in that namespace |
| ClusterRoleBinding | Whole cluster | Binds a ClusterRole cluster-wide |

A **RoleBinding** can also reference a **ClusterRole** -- this is the common pattern for "share one rulebook, bind it into many namespaces."

**Rules fields:**

| Field | Meaning | Example |
|-------|---------|---------|
| `apiGroups` | API group the resource belongs to. `""` is the core group | `[""]`, `["apps"]`, `["batch"]` |
| `resources` | Resource types being controlled | `["pods", "secrets", "deployments"]` |
| `verbs` | Allowed actions | `get`, `list`, `watch`, `create`, `update`, `patch`, `delete` |

`get`/`list`/`watch` are read operations; `create`/`update`/`patch`/`delete` are write operations. Use `["*"]` for "all" only where truly needed.

### ServiceAccounts

- Every namespace has a `default` ServiceAccount. If you do not set `serviceAccountName`, the Pod gets `default`.
- The kubelet mounts the SA token at `/var/run/secrets/kubernetes.io/serviceaccount/token` along with `ca.crt` and `namespace`.
- The app reads the token and sends it as `Authorization: Bearer <token>` to the API server.
- Modern Kubernetes (1.24+) uses **bound** Service Account tokens that are time-limited and rotated, not eternal tokens.
- Use `automountServiceAccountToken: false` (or `automountServiceAccountToken: false` on the SA) when a Pod never talks to the API; this removes the mounted credential entirely and reduces blast radius.

### Pod Security Standards (PSA)

The API server can enforce a baseline via three levels applied as namespace labels:

| Level | Policy | Typical admissions |
|-------|--------|--------------------|
| privileged | No restrictions | system components, host-coupled agents |
| baseline | Minimally restrictive | defaults run as root or with `pods/log` access |
| restricted | Hardened | forces non-root, dropped capabilities, seccomp, etc. |

Applied with labels like `pod-security.kubernetes.io/enforce=restricted`.

### securityContext (Pod vs Container)

- **Pod-level** `spec.securityContext` applies to every container in the Pod (UID, GID, seccomp, runAsNonRoot).
- **Container-level** `containers[].securityContext` applies only to that one container and overrides the Pod-level for that container.
- In multi-container Pods, be explicit inside each container.

Key fields:

| Field | Effect |
|-------|--------|
| `runAsNonRoot: true` | Blocks running as UID 0 |
| `runAsUser: 1000` | Runs the process as that UID |
| `allowPrivilegeEscalation: false` | Blocks sudo/setuid escalation |
| `readOnlyRootFilesystem: true` | Mounts `/` read-only; writes need a writable volume (e.g. emptyDir) |
| `capabilities.drop: [ALL]` / `add` | Strips/adds Linux capability bits (e.g. `NET_BIND_SERVICE`) |
| `seccompProfile: {type: RuntimeDefault}` | Restricts syscalls to a sane default |
| `privileged: false` | Default; denies access to host devices and kernel features |

### Image security and Secrets

- Don't use latest tags; pin immutable digests or semantic versions and scan images for CVEs continuously (Trivy etc.).
- Only pull from private/trusted registries; enforce `ImagePullSecrets` for auth; consider image policy webhooks and signing.
- Mount Secrets only where needed and keep them out of the image and environment; inject them via referenced Secrets (e.g. `secretRef` or a projected volume) rather than literals.

---

## 3. Key Commands

```bash
kubectl create serviceaccount <name> -n <ns>

kubectl get sa,roles,rolebindings,clusterroles,clusterrolebindings -A

# Impersonate an SA to check permissions
kubectl auth can-i list secrets --as=system:serviceaccount:<ns>:<sa-name> -n <ns>
kubectl auth can-i get pods

# Inspect what a Pod actually uses
kubectl get pod <name> -o yaml | grep serviceAccountName

# Describe a binding to see subject -> role wiring
kubectl describe rolebinding <name> -n <ns>

# Inspect a Pod/container security context
kubectl get pod <name> -o jsonpath='{.spec.containers[0].securityContext}'

# Inspect a CreateContainerErrors
kubectl describe pod <name>

# Verify the image's default user
docker inspect <image> --format '{{.Config.User}}'
```

---

## 4. YAML Patterns

### ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: dev
```

- `apiVersion: v1` and `kind: ServiceAccount`: the identity object; always namespaced.
- `metadata.name` / `metadata.namespace`: the SA name and the namespace it belongs to.
- Any Pod that sets `serviceAccountName: app-sa` in the same namespace gets this SA's token mounted.

### Role + RoleBinding

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
kind: RoleBinding
metadata:
  namespace: dev
  name: read-pods
subjects:
- kind: ServiceAccount
  name: app-sa
  namespace: dev
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

- `rules`: one or more permission entries. `apiGroups: [""]` = the core group (`pods`, `secrets`, `configmaps`).
- `resources`: which resource types the rule covers; `pods/log` covers the log subresource.
- `verbs`: allowed actions; `get/list/watch` are read-only, so this Role cannot modify anything.
- `subjects`: who receives the grant. Here: the `app-sa` ServiceAccount in `dev`.
- `roleRef`: which Role is being granted. `apiGroup` must be `rbac.authorization.k8s.io`.

### ClusterRoleBinding

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: read-pods-cluster
subjects:
- kind: ServiceAccount
  name: app-sa
  namespace: dev
roleRef:
  kind: ClusterRole
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

- ClusterRoleBinding has no `namespace`; it applies cluster-wide.
- It binds a ClusterRole (cluster-scoped ruleset) to a subject; the subject itself (an SA) still lives in a namespace.
- Use for cluster-wide resources (Nodes, PVs) or to apply the same rulebook in many namespaces.

### Pod / container securityContext

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx:1.25-alpine
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: [ALL]
        add: [NET_BIND_SERVICE]
```

- `spec.securityContext` (Pod level): default for all containers in the Pod.
  - `runAsNonRoot: true`: kubelet refuses to start if the image would run as UID 0.
  - `runAsUser: 1000`: force the process UID; must match a user present in the image for file permissions.
  - `seccompProfile.type: RuntimeDefault`: restrict syscalls to a safe default profile.
- `containers[].securityContext` (container level): overrides the Pod level for this container.
  - `allowPrivilegeEscalation: false`: blocks sudo / setuid privilege gain.
  - `readOnlyRootFilesystem: true`: mounts `/` read-only; writes go to mounted volumes (e.g. `emptyDir` at `/tmp`).
  - `capabilities.drop: [ALL]` then `add: [NET_BIND_SERVICE]`: strip everything, re-add only what the app needs (here: binding to port 80).
- Nginx runs as non-root on port 8080, or keeps `NET_BIND_SERVICE` to bind low ports.


## 5. How It All Fits Together

**End-to-end authorization flow for an API request:**

```
[ Pod ] --(Bearer SA token)--> [ API Server ]
        -- 1. AUTHENTICATION: validate token / cert -> identity
        -- 2. AUTHORIZATION: RBAC check verb+resource against bindings
        -- 3. ADMISSION: PSA / policy webhooks validate the request body
        -- > 200 OK (or 401 / 403)
```

**Least-privilege workflow when deploying an app:**

1. Create a dedicated namespace and a dedicated ServiceAccount (never rely on `default`).
2. Create a Role containing only the verbs/resources the app needs (e.g. `get,list` on `configmaps`).
3. Create a RoleBinding binding that SA to the Role in that namespace.
4. Set `serviceAccountName` in the Pod spec so it uses the restricted identity.
5. Add a strict container `securityContext`: `runAsNonRoot: true`, `runAsUser: 1000`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`.
6. Verify with `kubectl auth can-i` and by drilling the 403 on other namespaces/resources.

---

## 6. Common Mistakes and Gotchas

| Mistake | Why it happens | How to avoid |
|---------|----------------|--------------|
| Using `default` SA for API-accessing Pods | `serviceAccountName` not set | Always create + set a dedicated SA |
| Granting `cluster-admin` to an app or CI/CD | Convenience | Create a Role/ClusterRole scoped to minimal resources/namespaces |
| `runAsNonRoot: true` on a root image (e.g. redis) | Image defaults to UID 0 | kubelet refuses -> `CreateContainerConfigError`; override with `runAsUser` or rebuild image with `USER 1000` |
| `readOnlyRootFilesystem` without a /tmp volume | Java/Node apps write temp files | Mount `emptyDir` at `/tmp` (or the write dir) |
| Confusing Pod vs container level context | Multi-container Pods only | Override per container where behavior differs |
| RBAC allowed but app still gets `myself` | Request denied because of a different verb | Check both verb and resource; `wildcard` not passed |
| Assuming RBAC == network security | RBAC only gating the API server | Add Network Policies for Pod-to-Pod traffic |
| Leaving token mounted | Apps that never call the API | Set `automountServiceAccountToken: false` |

---

## 7. Quick Troubleshooting

**Symptom: Pod gets 403 Forbidden from the API server**
Cause: the SA lacks an RBAC rule for that verb/resource.
Fix:
```bash
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<ns>:<sa-name> -n <ns>
```
then create/update the Role + RoleBinding and reapply.

**Symptom: Pod uses the `default` ServiceAccount**
Cause: `serviceAccountName` missing from spec.
Fix: `kubectl get pod <name> -o yaml | grep serviceAccountName`, then add the field.

**Symptom: ClusterRoleBinding "not working"**
Cause: binding is namespace-scoped or references a missing SA/ClusterRole.
Fix: `kubectl get clusterrolebinding <name> -o yaml`; ensure `subjects` and `roleRef` are correct.

**Symptom: Pod is in `CreateContainerConfigError` / `CrashLoopBackOff`**
Cause: `kubectl describe pod <name>` shows `container has runAsNonRoot and image will run as root`.
Fix: set `runAsUser: 1000` in YAML or rebuild image with a `USER 1000` directive.

**Symptom: App crashes with `IOException: Permission denied` on startup**
Cause: read-only root filesystem blocks temp writes.
Fix: add an `emptyDir` volume mounted to the path the app writes to (e.g. `/tmp`).

---

## 8. 30-Second Recap

- SA = ID badge; Role = rulebook; Binding = glue. RBAC is **deny-by-default**; deny action means **403 Forbidden**.
- Least privilege: always use a dedicated SA and a context free of `default`.
- SecurityContext = straitjacket: non-root UID, read-only root, drop all capabilities, no privilege escalation, seccomp.
- `CreateContainerError` + "runAsNonRoot and image will run as root" = image defaults to root.
- RBAC controls the API; SecurityContext controls the process; keep both layers.

## Related Lessons

- [Lesson 22 - RBAC and Service Accounts](../docs/07-security/lesson-22-rbac-and-service-accounts.md)
- [Lesson 23 - Locking Down the Container (Security Contexts)](../docs/07-security/lesson-23-locking-down-the-container-security-contexts.md)

## Related Material

- [Security Cheat Sheet](../cheatsheets/security-cheatsheet.md)
- [Interview - Security](../interview/security.md)

[Back to Revision Index](README.md)