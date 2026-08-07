# Lab 35 - GitOps Principles and Practices

## Prerequisite

- Completion of [Lesson 35 - GitOps Principles and Practices](../docs/10-gitops/lesson-35-gitops-principles-and-practices.md).
- A running kind cluster.
- kubectl installed and configured.

## Objective

Install ArgoCD, deploy an app from a public Git repository, and then try to manually break it to watch ArgoCD self-heal.

## Estimated Time

25 minutes.

---

## Step 1: Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for all the ArgoCD pods to be running:

```bash
kubectl get pods -n argocd
```

## Step 2: Access the ArgoCD UI

Get the admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

Open a second terminal window and run this to port-forward the UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open your web browser and go to: `https://localhost:8080`

(Your browser will warn you about a self-signed certificate. Click "Advanced" -> "Proceed to localhost").

- Username: `admin`
- Password: (Paste the password from above)

## Step 3: Create an ArgoCD Application via YAML

Create `argo-app.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Apply it:

```bash
kubectl apply -f argo-app.yaml
```

## Step 4: Watch it Deploy

Go back to your browser UI. Click on the guestbook application. You will see a visual tree of the Deployment and Service. It should turn green and say "Healthy" and "Synced".

Verify in your terminal:

```bash
kubectl get pods -n default
```

## Step 5: Self-Heal Test (Breaking Things on Purpose)

Scale the deployment:

```bash
kubectl scale deployment guestbook-ui --replicas=5
```

Verify it scaled up:

```bash
kubectl get pods -l app=guestbook-ui
```

(You should temporarily see 5 pods).

Wait for ArgoCD to react (about 10-20 seconds), then run the command again:

```bash
kubectl get pods -l app=guestbook-ui
```

**Your Task:**

- After waiting, how many pods are running now?
- Look at the ArgoCD UI in your browser. Did the UI color or status change temporarily when you scaled it?
- Based on the theory of `selfHeal: true`, explain exactly what ArgoCD did to your manual change.

(Answer: 1. 1 pod. 2. It likely flashed "OutOfSync" briefly. 3. ArgoCD noticed the live cluster had 5 replicas, but Git desired state had 1. Because `selfHeal` was true, it sent a PATCH to scale it back to 1).

## Step 6: Cleanup

```bash
kubectl delete application guestbook -n argocd
kubectl delete namespace argocd
kubectl delete deployment guestbook-ui
kubectl delete svc guestbook-ui
```

---

## What You Learned

- GitOps means your entire cluster configuration lives in a Git repository.
- ArgoCD is a pull-based CD tool that runs inside your cluster.
- It constantly compares Git (Desired State) with the cluster (Live State).
- If `selfHeal` is enabled, ArgoCD automatically overwrites manual changes.
- ArgoCD uses Kubernetes CRDs, meaning an "Application" is just another native Kubernetes object.

## Next Steps

Proceed to [Lesson 36 - Argo CD and Flux](../docs/10-gitops/lesson-45-cicd-pipelines-github-actions-and-argocd.md) to compare GitOps tools.

---

[Back to Labs](README.md)
