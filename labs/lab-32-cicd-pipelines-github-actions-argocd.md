# Lab 32 - CI/CD Pipelines (GitHub Actions and ArgoCD)

## Prerequisite

- Completion of [Lesson 32 - CI/CD Pipelines (GitHub Actions and ArgoCD)](../docs/10-gitops/lesson-32-cicd-pipelines-github-actions-and-argocd.md).
- A GitHub account and a repository you can push to.
- A kind cluster (optional, for the ArgoCD step).

## Objective

Build the end-to-end GitOps flow: a Flask app, a Dockerfile, a GitHub Actions workflow that builds an image and bumps the Helm values, and ArgoCD-based deployment to a kind cluster.

## Estimated Time

30 minutes.

---

## Step 1: Create the application files

In a new GitHub repository, add:

`app.py`:

```python
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return "Hello from my CI/CD app!"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

`Dockerfile`:

```dockerfile
FROM python:3.9-slim
WORKDIR /app
COPY . .
RUN pip install flask
EXPOSE 5000
CMD ["python", "app.py"]
```

## Step 2: Add the Helm chart

Create `helm/Chart.yaml` and `helm/values.yaml`:

```yaml
# helm/Chart.yaml
apiVersion: v2
name: myapp
version: 0.1.0
```

```yaml
# helm/values.yaml
replicaCount: 2
image:
  repository: <YOUR_DOCKER_USERNAME>/myapp
  tag: latest
service:
  port: 80
```

## Step 3: Add the GitHub Actions workflow

Create `.github/workflows/deploy.yml` with the workflow from Lesson 32 (build, push to Docker Hub, update `helm/values.yaml` image.tag with `${{ github.sha }}`, commit and push back).

## Step 4: Configure Secrets and permissions

- Add `DOCKER_USERNAME` and `DOCKER_PASSWORD` as repository Secrets (Settings -> Secrets and variables -> Actions).
- In Settings -> Actions -> General -> Workflow permissions, enable "Read and write permissions".

## Step 5: Run the pipeline

Push all files to `main` and open the Actions tab.

Expected: the workflow runs, builds and pushes the image tagged `myapp:<sha>`, updates `helm/values.yaml` `image.tag` to `<sha>`, and pushes a new commit.

Expected after: the Git history contains a commit titled `Update image tag to <sha>`.

## Step 6 (Optional): Deploy with ArgoCD on kind

```bash
kind create cluster --name argocd-lab
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# Wait for pods, then register the app pointing at the config repo
argocd app create myapp --repo https://github.com/USER/config.git \
  --path helm --dest-server https://kubernetes.default.svc
```

Expected: ArgoCD syncs the Helm chart and the Deployment runs with the new image tag.

## Verification

- `git log --oneline -3` shows the manifest-bump commit.
- (Optional with ArgoCD) `kubectl get deploy -n default` shows a rollout with the new image.

## Cleanup

Delete the kind cluster if you created it:

```bash
kind delete cluster --name argocd-lab
```

## Summary

You authored a CI pipeline that builds an image and bumps a Helm manifest, and watched how ArgoCD pulls that Git change into Kubernetes, completing the GitOps loop without any direct kubectl access from CI.