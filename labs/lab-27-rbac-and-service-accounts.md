# Lab 27 - RBAC and Service Accounts

## Prerequisite

- Completion of [Lesson 27 - RBAC and Service Accounts](../docs/07-security/lesson-27-rbac-and-service-accounts.md).
- A running Kubernetes cluster (kind, minikube, k3s, or Docker Desktop).
- kubectl installed and configured.

## Objective

Create a ServiceAccount with restricted RBAC permissions. Give it permission to only list Pods. Then, try to list Secrets from inside a Pod and watch the API Server reject us.

## Estimated Time

15 minutes.

---

## Step 1: Create a Namespace

```bash
kubectl create namespace rbac-test
kubectl config set-context --current --namespace=rbac-test
```

Expected output:

```
namespace/rbac-test created
Context "kind-kind" modified.
```

## Step 2: Create the RBAC Resources

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

Expected output:

```
serviceaccount/pod-reader-sa created
role.rbac.authorization.k8s.io/pod-reader-role created
rolebinding.rbac.authorization.k8s.io/pod-reader-binding created
```

## Step 3: Verify RBAC Objects

```bash
kubectl get roles,rolebindings,serviceaccounts
```

Expected output:

```
NAME                                     ROLE                                             AGE
role.rbac.authorization.k8s.io/pod-reader-role   Role/pod-reader-role                                       10s

NAME                                                ROLE                   AGE
rolebinding.rbac.authorization.k8s.io/pod-reader-binding   Role/pod-reader-role   10s

NAME                                  SECRETS   AGE
serviceaccount/pod-reader-sa          0         10s
serviceaccount/default                0         15s
```

## Step 4: Create a Pod Using the ServiceAccount

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

Expected output:

```
pod/curl-pod created
```

## Step 5: Wait for the Pod to Run

```bash
kubectl get pod curl-pod --wait
```

Expected output (wait for STATUS to be Running):

```
NAME       READY   STATUS    RESTARTS   AGE
curl-pod   1/1     Running   0          30s
```

## Step 6: Test Allowed Action (List Pods)

```bash
kubectl exec -it curl-pod -- sh
```

Inside the Pod, run:

```sh
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
APISERVER=https://kubernetes.default.svc

curl --cacert $CACERT --header "Authorization: Bearer $TOKEN" $APISERVER/api/v1/namespaces/rbac-test/pods
```

Expected output: A JSON response listing the Pods in the `rbac-test` namespace.

## Step 7: Test Denied Action (List Secrets)

Still inside the Pod, run:

```sh
curl --cacert $CACERT --header "Authorization: Bearer $TOKEN" $APISERVER/api/v1/namespaces/rbac-test/secrets
```

Expected output:

```json
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "secrets is forbidden: User \"system:serviceaccount:rbac-test:pod-reader-sa\" cannot list resource \"secrets\" in API group \"\" in the namespace \"rbac-test\"",
  "reason": "Forbidden",
  "details": {
    "kind": "secrets",
    "reason": "Forbidden"
  },
  "code": 403
}
```

The API Server rejects the request because the ServiceAccount doesn't have permission to list Secrets.

Type `exit` to leave the Pod.

## Step 8: Use kubectl auth can-i (Pro Method)

```bash
kubectl auth can-i list pods --as=system:serviceaccount:rbac-test:pod-reader-sa -n rbac-test
kubectl auth can-i list secrets --as=system:serviceaccount:rbac-test:pod-reader-sa -n rbac-test
```

Expected output:

```
yes
no
```

This confirms the RBAC rules are working as expected.

## Step 9: Check Pod ServiceAccount

```bash
kubectl get pod curl-pod -o yaml | grep serviceAccountName
```

Expected output:

```
  serviceAccountName: pod-reader-sa
```

---

## Cleanup

```bash
kubectl config set-context --current --namespace=default
kubectl delete namespace rbac-test
```

Expected output:

```
namespace "rbac-test" deleted
```

## What You Learned

- ServiceAccounts are identities for Pods.
- Roles define permissions within a namespace.
- RoleBindings attach Roles to ServiceAccounts.
- The API Server returns 403 Forbidden when RBAC denies a request.
- `kubectl auth can-i` is a powerful tool to test RBAC permissions.

## Next Steps

Proceed to [Lesson 28 - Security Contexts and Pod Security Standards](../docs/07-security/lesson-31-locking-down-the-container-security-contexts.md) to learn how to restrict what Pods can do at the container level.

---

[Back to Labs](README.md)
