---
title: Lesson 27 - RBAC and Service Accounts
module: 07 Security
lesson: 27
status: Complete
tags: [kubernetes, rbac, service-accounts, authentication, authorization, roles, rolebindings, cluster-roles, least-privilege]
---

# Lesson 27 - RBAC and Service Accounts

## Table of Contents

- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Real-world Motivation](#real-world-motivation)
- [Core Concepts](#core-concepts)
- [Architecture](#architecture)
- [ASCII Diagrams](#ascii-diagrams)
- [Hands-on](#hands-on)
- [Commands](#commands)
- [YAML Explanation](#yaml-explanation)
- [Production Notes](#production-notes)
- [Best Practices](#best-practices)
- [Common Mistakes](#common-mistakes)
- [Troubleshooting](#troubleshooting)
- [Interview Questions](#interview-questions)
- [Scenario Questions](#scenario-questions)
- [Quiz](#quiz)
- [Revision](#revision)
- [Cheat Sheet](#cheat-sheet)
- [References](#references)
- [Related Lessons](#related-lessons)
- [Coming Next](#coming-next)

---

## Learning Objectives

By the end of this lesson you will be able to:

- Explain the difference between Authentication (who are you?) and Authorization (what can you do?).
- Describe what a ServiceAccount is and how Pods use it to talk to the API Server.
- Distinguish between Role (namespace-scoped) and ClusterRole (cluster-scoped).
- Explain how RoleBindings connect ServiceAccounts to Roles.
- Trigger a 403 Forbidden error from the API Server.

## Prerequisites

- Completion of Lessons 1 through 12.
- A running Kubernetes cluster (see [Lesson 01](../01-fundamentals/lesson-01-anatomy-of-a-container.md) for kind setup instructions).
- kubectl installed and configured.

## Real-world Motivation

### The Lateral Movement Attack

Imagine you deploy a frontend web application. A hacker finds a Remote Code Execution (RCE) vulnerability in your frontend and drops into a shell inside the Pod. Because you didn't configure RBAC, the Pod is using the default ServiceAccount. The hacker discovers the Kubernetes API Server URL and the token mounted in the Pod. They use curl to query the API, list all Secrets in the namespace, steal the database password, and delete your Deployments to cause a ransomware outage.

### Why This Exists

Kubernetes needed a way to enforce the Principle of Least Privilege. Not every application needs to read Secrets or delete Pods. RBAC allows cluster administrators to create strict rules: "This frontend Pod can only read ConfigMaps. It cannot read Secrets, and it cannot talk to other namespaces."

### Real Company Examples

**Capital One:** At Capital One, they run strict RBAC. The frontend Pod uses a ServiceAccount bound to a Role that only allows `get` on ConfigMaps in the frontend namespace. The backend Pod uses a different ServiceAccount that allows `get` on Secrets (for DB passwords). An attacker who compromises the frontend Pod cannot read Secrets, preventing them from stealing database credentials and moving laterally.

## Core Concepts

### Explain Like I'm 12

Imagine a school.

- **User Accounts** are for teachers and principals (humans).
- **ServiceAccounts** are for the school robots (apps). Each robot needs an ID badge to walk around.
- **Role:** A list of rules. "Badge level A can read the library books, but cannot enter the principal's office."
- **RoleBinding:** The act of pinning that badge to a specific robot. "Robot #1, you now have Badge level A."

### Explain Like I'm a Junior Engineer

When a Pod starts, Kubernetes automatically mounts a token (an identity) into it. By default, it uses the `default` ServiceAccount in that namespace. If the application needs to query the Kubernetes API (e.g., to check the status of other Pods), it uses that token. RBAC is the system that evaluates that token and says "Allowed" or "Denied".

### Explain Technically

- **Authentication:** The API Server checks the Bearer token (JWT). It identifies the ServiceAccount.
- **Authorization (RBAC):** The API Server checks if that ServiceAccount has been bound to a Role or ClusterRole via a RoleBinding. It evaluates the verbs (`get`, `list`, `watch`, `create`, `delete`) against the resources (`pods`, `secrets`, `configmaps`).
- If there is a match, it returns 200 OK. If not, it returns 403 Forbidden.

### How Kubernetes Implements It Internally

The kubelet mounts a projected volume containing the ServiceAccount token into the Pod. When the application makes an HTTP request to the API Server with `Authorization: Bearer <token>`, the API server's Authorization layer intercepts it. It queries the RBAC authorizer, which checks the RoleBinding objects in etcd. Modern Kubernetes (1.24+) uses "Bound Service Account Tokens" which are time-limited and tied to the Pod's lifecycle, automatically rotating them.

### Why Kubernetes Was Designed That Way

RBAC is a deny-by-default system. Nothing is allowed unless explicitly permitted. This is the security model used by major cloud providers and is essential for multi-tenant clusters where different teams share the same infrastructure.

## Architecture

```
[ Pod (App) ] -> (Bearer Token) -> [ API Server ]
                                      |
                                      v
1. Authentication: "Who are you?" (Validates the SA Token)
                                      |
                                      v
2. Authorization (RBAC): "Are you allowed to list Pods?" (Checks RoleBindings)
                                      |
                                      v
3. Admission Controllers: "Is this YAML valid?" (e.g., Kyverno)
                                      |
                                      v
[ etcd ] (Saved)
```

### Terminology

| Term | Definition |
|------|------------|
| ServiceAccount (SA) | An identity for processes running in a Pod. |
| Role | A namespace-scoped set of permissions. |
| ClusterRole | A cluster-scoped set of permissions. |
| RoleBinding | Grants the permissions in a Role to a ServiceAccount. |
| ClusterRoleBinding | Grants the permissions in a ClusterRole to a ServiceAccount cluster-wide. |
| Principle of Least Privilege | Giving an entity only the permissions it needs to do its job, and no more. |
| Authentication | Verifying who you are (validating the token). |
| Authorization | Verifying what you are allowed to do (RBAC rules). |

### How It Works Internally

1. You create a ServiceAccount named `pod-reader-sa`.
2. You create a Role named `pod-reader-role` allowing `get` and `list` on `pods`.
3. You create a RoleBinding linking `pod-reader-sa` to `pod-reader-role`.
4. You create a Pod specifying `serviceAccountName: pod-reader-sa`.
5. The kubelet injects the SA token into the Pod.
6. The app inside the Pod sends an HTTP GET to `/api/v1/namespaces/default/pods` with the token.
7. API Server validates the token (Authentication passed).
8. API Server checks RBAC rules. Finds `pod-reader-role` allows `list` on `pods`. (Authorization passed).
9. API Server returns the Pod list (200 OK).

### Step-by-Step Workflow

1. Admin creates a dedicated Namespace.
2. Admin creates a ServiceAccount in that Namespace.
3. Admin creates a Role with specific verbs (e.g., `get`, `list` on `configmaps`).
4. Admin creates a RoleBinding attaching the Role to the ServiceAccount.
5. Developer deploys a Pod specifying `serviceAccountName`.
6. Pod runs with restricted permissions.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | SA, Role, and RoleBinding are applied to the cluster. |
| Token Mounting | Pod is created. Kubelet requests a token for the SA and mounts it. |
| API Request | App reads token, makes request. |
| Deletion | Deleting a RoleBinding immediately revokes the permissions for all Pods using that SA. |

### Role vs ClusterRole

| Feature | Role | ClusterRole |
|---------|------|-------------|
| Scope | Single Namespace | Entire Cluster (or all namespaces) |
| Use Case | Allow app to read ConfigMaps in its namespace | Allow an admin to list Nodes |
| Resource Types | Namespaced resources (Pods, Secrets) | Any resource (Nodes, PVs, CRDs) |

### RoleBinding vs ClusterRoleBinding

| Feature | RoleBinding | ClusterRoleBinding |
|---------|-------------|---------------------|
| Scope | Single Namespace | Entire Cluster |
| Grants | A Role to a SA | A ClusterRole to a SA |

### Common Myths

| Myth | Fact |
|------|------|
| "If I don't give my Pod a ServiceAccount, it has no permissions." | False. If you don't specify one, Kubernetes automatically attaches the `default` ServiceAccount for that namespace. Depending on the cluster setup, `default` might have broad permissions. |
| "RBAC secures Pod-to-Pod network traffic." | False. RBAC only secures the Kubernetes API Server. To block Pod A from sending network packets to Pod B, you need Network Policies. |

## ASCII Diagrams

Mental Model: The ServiceAccount is an ID Card. The Role is the keycard with magnetic stripes. The RoleBinding is the lanyard that puts the keycard around the robot's neck.

```
[ Pod: api-app ]
  (Uses ServiceAccount: api-reader)
      |
      v
[ ServiceAccount: api-reader ] (Identity)
      |
      v (Bound by RoleBinding)
[ RoleBinding ] (The Lanyard)
  (Links SA to Role)
      |
      v
[ Role: pod-reader ] (The Rulebook)
  (apiGroups: [""], resources: ["pods"], verbs: ["get", "list"])
```

### Authorization Flow

```
[ Pod sends request to API Server ]
      |
      v
[ Authentication: Validate SA token ]
      | (Token valid? Yes)
      v
[ Authorization: Check RBAC rules ]
      | (RoleBinding exists? Yes)
      | (Role allows this verb on this resource? Yes)
      v
[ 200 OK - Request allowed ]
```

## Hands-on

### Objective

Create a Pod with a custom ServiceAccount. Give it permission to only list Pods. Then, try to list Secrets from inside the Pod and watch the API Server reject us.

### Step 1: Create a Namespace

```bash
kubectl create namespace rbac-test
kubectl config set-context --current --namespace=rbac-test
```

### Step 2: Create the RBAC Resources

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-reader-sa
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader-role
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
subjects:
- kind: ServiceAccount
  name: pod-reader-sa
roleRef:
  kind: Role
  name: pod-reader-role
  apiGroup: rbac.authorization.k8s.io
EOF
```

### Step 3: Create a Pod Using the ServiceAccount

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: curl-pod
spec:
  serviceAccountName: pod-reader-sa
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ["sleep", "3600"]
EOF
```

Wait for it to be Running:

```bash
kubectl get pod curl-pod --wait
```

### Step 4: Test Allowed Action (List Pods)

```bash
kubectl exec -it curl-pod -- sh
```

Inside the Pod:

```sh
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
APISERVER=https://kubernetes.default.svc

curl --cacert $CACERT --header "Authorization: Bearer $TOKEN" $APISERVER/api/v1/namespaces/rbac-test/pods
```

Expected: A JSON response listing the Pods.

### Step 5: Test Denied Action (List Secrets)

Still inside the Pod:

```sh
curl --cacert $CACERT --header "Authorization: Bearer $TOKEN" $APISERVER/api/v1/namespaces/rbac-test/secrets
```

Expected: 403 Forbidden. The API Server rejects the request.

Type `exit` to leave the Pod.

### Step 6: Use kubectl auth can-i (Pro Move)

```bash
kubectl auth can-i list pods --as=system:serviceaccount:rbac-test:pod-reader-sa -n rbac-test
kubectl auth can-i list secrets --as=system:serviceaccount:rbac-test:pod-reader-sa -n rbac-test
```

Expected: `yes` for pods, `no` for secrets.

### Step 7: Cleanup

```bash
kubectl config set-context --current --namespace=default
kubectl delete namespace rbac-test
```

## Commands

```bash
# Create a ServiceAccount
kubectl create serviceaccount <name>

# List RBAC objects in a namespace
kubectl get roles,rolebindings

# List ClusterRoles and ClusterRoleBindings
kubectl get clusterroles,clusterrolebindings

# Test permissions (impersonate an SA)
kubectl auth can-i list secrets --as=system:serviceaccount:<ns>:<sa-name>

# Describe a RoleBinding
kubectl describe rolebinding <name>

# Check which SA a Pod uses
kubectl get pod <name> -o yaml | grep serviceAccountName
```

## YAML Explanation

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-reader-sa
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader-role
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
subjects:
- kind: ServiceAccount
  name: pod-reader-sa
roleRef:
  kind: Role
  name: pod-reader-role
  apiGroup: rbac.authorization.k8s.io
```

### Field-by-Field Explanation

- `rules`: A list of permissions.
- `apiGroups: [""]`: The core Kubernetes API (Pods, Services, ConfigMaps).
- `resources: ["pods"]`: The specific resource type.
- `verbs: ["get", "list"]`: The actions allowed. (Denied: `create`, `delete`, `watch`).
- `subjects`: The entity (User, Group, or ServiceAccount) receiving the permission.
- `roleRef`: The Role being granted.

## Production Notes

- **Never use the `default` ServiceAccount.** Always create a dedicated SA for every application.
- **Grant `cluster-admin` sparingly.** This role gives god-mode access to the cluster. Only cluster administrators should have it.
- **Use tools like `audit2rbac`.** If you don't know what permissions your app needs, run it with permissive logging, check the audit logs, and generate a strict Role based on what it actually accessed.
- **Use Bound Service Account Tokens.** Modern Kubernetes (1.24+) uses time-limited tokens that automatically rotate. Ensure your cluster is up to date.
- **Restrict CI/CD ServiceAccounts.** Give your CI/CD pipeline a Role restricted to specific namespaces, not `cluster-admin`.

### When to Use / When NOT to Use

**Always use strict RBAC when:**

- Running production clusters.
- Running 3rd party applications that need API access.
- Separating teams (Team A cannot see Team B's Secrets).

**Never skip RBAC, even for:**

- Local dev clusters. Practice RBAC from the start.

### Performance and Security Considerations

**Performance:** RBAC rules are evaluated synchronously on every API request. However, the API Server caches the ruleset in memory, so the performance impact is negligible.

**Security:** Older Kubernetes versions used non-expiring SA tokens. If a token was leaked, it was valid forever. Modern Kubernetes (1.24+) uses projected, bound tokens that expire after 1 hour and are automatically rotated by the kubelet. Ensure your cluster is up to date.

## Best Practices

- Always create dedicated ServiceAccounts for applications.
- Use Roles (namespace-scoped) instead of ClusterRoles when possible.
- Grant only the minimum permissions needed (least privilege).
- Use `kubectl auth can-i` to test permissions.
- Monitor RBAC changes with audit logs.
- Never grant `cluster-admin` to applications or CI/CD pipelines.
- Use Pod Security Standards to restrict what Pods can do.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Using `default` SA for API access | Not specifying `serviceAccountName` | Always create and specify a dedicated SA |
| Granting `cluster-admin` to CI/CD | Laziness, convenience | Create a Role restricted to specific namespaces |
| Forgetting to test RBAC rules | Assuming permissions work | Use `kubectl auth can-i` to verify |
| Not monitoring RBAC changes | Assuming RBAC is set and forget | Enable audit logging |

## Troubleshooting

**Symptom: Pod gets 403 Forbidden from API Server**

Cause: ServiceAccount doesn't have the required RBAC permissions.

```bash
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<ns>:<sa-name>
kubectl get rolebinding -o yaml | grep -A 5 subjects
```

Fix: Create or update the Role and RoleBinding to grant the required permissions.

**Symptom: Pod uses `default` ServiceAccount**

Cause: `serviceAccountName` not specified in Pod spec.

```bash
kubectl get pod <name> -o yaml | grep serviceAccountName
```

Fix: Add `serviceAccountName` to the Pod spec.

**Symptom: ClusterRoleBinding not working**

Cause: ClusterRoleBinding is namespace-scoped, not cluster-scoped.

```bash
kubectl get clusterrolebinding <name> -o yaml
```

Fix: Ensure the ClusterRoleBinding exists and references the correct SA.

## Interview Questions

**Q: What is the difference between Authentication and Authorization?**

A: Authentication verifies who you are (e.g., validating a ServiceAccount token). Authorization verifies what you are allowed to do (e.g., RBAC rules checking if you can list Pods).

**Q: What is the difference between a Role and a ClusterRole?**

A: A Role is scoped to a single Namespace. A ClusterRole is scoped to the entire cluster (or all namespaces).

**Q: How do you restrict an application running in a Pod so it can only read ConfigMaps?**

A: I create a dedicated ServiceAccount and assign it to the Pod. Then I create a Role with `verbs: ["get", "list"]` on `resources: ["configmaps"]`. Finally, I create a RoleBinding to attach that Role to the ServiceAccount. If the app tries to read Secrets, the API server will return 403 Forbidden.

**Q: An application pod keeps restarting. The logs show 403 Forbidden when it tries to list other Pods. How do you debug this?**

A: I would check which ServiceAccount the Pod is using (`kubectl get pod <name> -o yaml`). Then I would use `kubectl auth can-i list pods --as=system:serviceaccount:<ns>:<sa-name>` to verify its permissions. If it returns `no`, I would inspect the RoleBindings to ensure the SA is bound to a Role that grants the `list` verb on pods.

**Q: What happens if you don't specify a ServiceAccount for a Pod?**

A: Kubernetes automatically attaches the `default` ServiceAccount for that namespace. Depending on the cluster setup, this might have broad permissions.

**Q: Does RBAC secure network traffic between Pods?**

A: No. RBAC only secures the Kubernetes API Server. To block Pod A from sending network packets to Pod B, you need Network Policies.

## Scenario Questions

**Scenario 1:** You have a frontend Pod that needs to read a ConfigMap for its configuration. How do you set this up securely?

A: Create a ServiceAccount `frontend-sa`. Create a Role allowing `get` and `list` on `configmaps`. Create a RoleBinding linking them. Specify `serviceAccountName: frontend-sa` in the Pod spec.

**Scenario 2:** Your CI/CD pipeline needs to deploy to multiple namespaces. How do you configure RBAC?

A: Create a ServiceAccount for the CI/CD pipeline. Create a ClusterRole with deployment permissions. Create ClusterRoleBindings for each namespace the pipeline needs to access. Never use `cluster-admin`.

**Scenario 3 (Mini Project - The Namespace Admin):**

Create a ServiceAccount named `team-a-admin`. Create a Role that gives full access (`verbs: ["*"]`) to all resources in the `team-a` namespace. Create a RoleBinding. Use `kubectl auth can-i` to verify that `team-a-admin` can delete Deployments in `team-a`, but cannot delete Nodes (cluster-wide).

## Quiz

1. What is a ServiceAccount?
   - A. A user account for humans
   - B. An identity for processes running in a Pod
   - C. A cluster admin account
   - D. A network policy

2. What is the difference between a Role and a ClusterRole?
   - A. Role is cluster-wide, ClusterRole is namespace-scoped
   - B. Role is namespace-scoped, ClusterRole is cluster-wide
   - C. They are the same
   - D. Role is for users, ClusterRole is for ServiceAccounts

3. What HTTP status code does the API Server return when RBAC denies a request?
   - A. 200 OK
   - B. 401 Unauthorized
   - C. 403 Forbidden
   - D. 500 Internal Server Error

4. What does a RoleBinding do?
   - A. Binds a Pod to a node
   - B. Binds a Role to a ServiceAccount
   - C. Binds a Secret to a Pod
   - D. Binds a Network Policy

5. What is the Principle of Least Privilege?
   - A. Giving maximum permissions
   - B. Giving only the permissions needed
   - C. No permissions at all
   - D. Using default ServiceAccount

Answers: 1-B, 2-B, 3-C, 4-B, 5-B.

## Revision

One-minute revision:

- ServiceAccounts (SA) are identities for Pods.
- A Pod automatically mounts an SA token to talk to the API Server.
- Role defines permissions within a namespace.
- ClusterRole defines permissions cluster-wide.
- RoleBinding attaches a Role to a ServiceAccount.
- If an app tries to do something not explicitly allowed in the Role, the API Server returns 403 Forbidden.

Memory trick:

- ServiceAccount: An ID badge given to a robot (Pod).
- Role: A keycard with specific magnetic stripes ("Opens Pod Doors", "Does NOT Open Secret Doors").
- RoleBinding: The lanyard that puts the keycard around the robot's neck.

Key facts:

- SA = Identity.
- Role = Rulebook.
- Binding = Glue.
- 403 = Authorization failed (RBAC blocked it).

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl create serviceaccount <name>` | Imperatively creates an SA |
| `kubectl get roles,rolebindings` | Lists RBAC objects in a namespace |
| `kubectl auth can-i list secrets --as=system:serviceaccount:ns:sa` | Impersonates an SA to test permissions |
| `kubectl describe rolebinding <name>` | Shows which Role is attached to which SA |
| `kubectl get pod <name> -o yaml \| grep serviceAccountName` | Check which SA a Pod uses |

## References

- [Kubernetes Documentation: Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Kubernetes Documentation: Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts/)
- [Kubernetes Documentation: Bound Service Account Tokens](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#bound-service-account-token-volume)
- [Kubernetes Documentation: Auth to API Server](https://kubernetes.io/docs/reference/access-authn-authz/authentication/)

## Related Lessons

- [Lesson 01 - The Anatomy of a Container](../01-fundamentals/lesson-01-anatomy-of-a-container.md) - containers, namespaces, and cgroups.
- [Lesson 10 - Pods, ReplicaSets, and Deployments](../03-workloads/lesson-10-pods-replicasets-and-deployments.md) - how Pods work.
- [Lesson 23 - ConfigMaps and Secrets](../06-configuration/lesson-23-configmaps-and-secrets.md) - injecting configuration into Pods.
- [Module 07 Security Index](README.md) - authentication, authorization, and RBAC.
- [Lesson 31 - Container Security Contexts](lesson-31-locking-down-the-container-security-contexts.md) - Pod and container security limits.

## Coming Next

Now that you understand RBAC and ServiceAccounts, the next lesson covers Security Contexts and Pod Security Standards, which restrict what Pods can do at the container level (running as non-root, read-only filesystem, dropping capabilities).
