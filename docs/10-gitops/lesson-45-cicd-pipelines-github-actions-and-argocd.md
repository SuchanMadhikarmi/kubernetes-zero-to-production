---
title: Lesson 45 - CI/CD Pipelines (GitHub Actions and ArgoCD)
module: 10 GitOps
lesson: 45
status: Complete
tags: [kubernetes, gitops, ci, cd, github-actions, argocd, docker, helm, automation]
---

# Lesson 45 - CI/CD Pipelines (GitHub Actions and ArgoCD)

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

- Explain the end-to-end flow of modern GitOps CI/CD.
- Distinguish between Continuous Integration (CI) and Continuous Deployment (CD).
- Write a real GitHub Actions workflow YAML.
- Automate building a Docker image, pushing it to a registry, and updating a Helm chart.
- Explain why CI tools should never have direct kubectl access to the production cluster.

## Prerequisites

- Completion of Lessons 1 through 44.
- Understanding of Helm (Lessons 15 and 39) and ArgoCD (Lesson 16).
- A conceptual understanding of Docker and Git.

## Real-world Motivation

### From Lesson

The manual deployment bottleneck: imagine a developer finishes writing a new feature for the billing API. They manually run `docker build` and `docker push`. They manually edit the Helm `values.yaml` to point to the new image tag. They manually run `helm upgrade` or `kubectl apply` against the production cluster. This process is slow, prone to human error, and violates the Principle of Least Privilege (developers should not have production kubectl access). Furthermore, if the deployment fails, there is no automatic audit trail of what changed.

Why this exists: to automate the build and deploy process securely and declaratively. CI (GitHub Actions) builds the code, runs tests, and packages the Docker image. It then updates the Git repository with the new image tag. CD (ArgoCD) detects the Git change and deploys it to the cluster. By separating these concerns, the CI pipeline never needs cluster credentials, massively improving security.

### Additional Production Knowledge

The audit trail is the real product of GitOps. Every merge, every image tag, and every `git revert` is recorded in history, so "who changed what and when" is answerable even months later. This turns rollbacks and post-incident reviews from guesswork into reading the dictionary that is the repository. The friction usually comes not from the tooling but from agreeing that Git is the single source of truth and that manual `kubectl` fixes in production count as a bug, because they create drift that ArgoCD will silently reconcile away or your review process cannot explain.

## Core Concepts

### From Lesson

- **Continuous Integration (CI)**: automatically building and testing code changes. In this context it also builds the Docker image and updates the manifest.
- **Continuous Deployment (CD)**: automatically deploying the application to the cluster.
- **GitOps**: an operational framework where Git is the single source of truth. CI updates Git; ArgoCD reads Git.
- **Image tagging (Git SHA)**: best practice is to tag images with the Git commit SHA (e.g. `myapp:abc1234`), not `latest`, to ensure immutable, traceable deployments.
- **Automated manifest update**: the CI pipeline uses `yq` or `sed` to replace the `image.tag` in `values.yaml` and commits that change back to Git.

### Additional Production Knowledge

- **Environment promotion**: the same commit SHA can be promoted Dev, Staging, then Prod simply by having each environment's ArgoCD application point the same tag. This "promote by SHA, not by rebuild" model guarantees the exact artifact tested in staging is the one deployed to production.
- **Secrets handling**: `DOCKER_PASSWORD` and any registry credential are injected from GitHub Secrets. Never hardcode them, never commit `.env` files.
- **Webhooks vs polling**: ArgoCD defaults to a polling interval (commonly 3 minutes). A webhook makes ArgoCD react to a Git push immediately, reducing how long a "just pushed" change takes to appear.

## Architecture

### From Lesson

In a modern GitOps pipeline, CI and CD have strictly separated roles.

```text
[ Developer ] --(git push)--> [ GitHub Repo ]
                                  |
                                  v
                       [ GitHub Actions (CI) ]
                       1. Build Docker Image
                       2. Push to Registry (DockerHub/ECR)
                       3. Update values.yaml (image: myapp:<sha>)
                       4. git push back to Repo
                                  |
                                  v
                       [ ArgoCD (CD) detects Git change ]
                                  |
                                  v
                       [ Kubernetes API Server ]
                       (Pulls new image, restarts Pods)
```

### Additional Production Knowledge

The magic of this architecture is the strict read/write split: CI can only write to the Git repo, and ArgoCD can only read the repo and write to the cluster. Neither crosses into the other's domain for credentials. An attacker who compromises the CI runner can push a bad image tag to Git, but they cannot reach the cluster directly, which is the core security argument for this design.

## ASCII Diagrams

### From Lesson

```text
[ Developer ] --(git push)--> [ GitHub Repo ]
                                  |
                                  v
                       [ GitHub Actions (CI) ]
                       1. Build Docker Image
                       2. Push to Registry (DockerHub)
                       3. Update values.yaml (image: myapp:<sha>)
                       4. git push back to Repo
                                  |
                                  v
                       [ ArgoCD (CD) detects Git change ]
                                  |
                                  v
                       [ Kubernetes API Server ]
                       (Pulls new image, restarts Pods)
```

### Additional Production Knowledge

```text
App repo (developers write code here)
  |  CI: build + push image, commit values bump
  v
Config/GitOps repo (my-config)
  |  ArgoCD Application watches this repo
  v
Kubernetes cluster  <-- ArgoCD applies the rendered Helm chart
```

Separating the app repo from the config repo (rather than mixing them) is a production best practice: developers can push untested code to the app repo, but the config repo that ArgoCD reads only ever changes through an automated, reviewed update.

## Hands-on

### From Lesson

Goal: write the exact GitHub Actions workflow YAML you will use to automate deployments.

Step 1 - Application code (`app.py`):

```python
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return "Hello from my CI/CD app!"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

Step 2 - `Dockerfile`:

```dockerfile
FROM python:3.9-slim
WORKDIR /app
COPY . .
RUN pip install flask
EXPOSE 5000
CMD ["python", "app.py"]
```

Step 3 - The GitHub Actions workflow at `.github/workflows/deploy.yml`:

```yaml
name: CI/CD Pipeline

on:
  push:
    branches:
      - main

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v3

      - name: Login to Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Build and Push Docker Image
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: myrepo/myapp:${{ github.sha }}

      - name: Update Helm Values
        run: |
          sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq

          yq -i ".image.tag = \"${{ github.sha }}\"" helm/values.yaml

          git config --global user.name "GitHub Actions"
          git config --global user.email "actions@github.com"
          git add helm/values.yaml
          git commit -m "Update image tag to ${{ github.sha }}"
          git push
```

Step 4 - How ArgoCD finishes the job: when the Action pushes the new `values.yaml`, ArgoCD notices within its polling interval (about 3 minutes by default), renders the Helm chart with the new values, sees the Pod image changed, and performs a rolling update in the cluster.

Cleanup: no cluster cleanup required (we only generated the workflow YAML).

## Commands

```bash
# yq for editing YAML (Linux)
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Update an image tag in a values.yaml
yq -i '.image.tag = "<sha>"' helm/values.yaml

# Commit the manifest bump
git add helm/values.yaml
git commit -m "Update image tag to <sha>"
git push

# Optional: install ArgoCD and register an app pointing at the repo
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
argocd app create my-app --repo https://github.com/USER/config.git \
  --path helm --dest-server https://kubernetes.default.svc
```

## YAML Explanation

```yaml
on:
  push:
    branches:
      - main
```

- `on.push.branches: [main]` triggers the workflow only on pushes to `main`. Use `pull_request` events too if you want PR-based checks.

```yaml
- name: Login to Docker Hub
  uses: docker/login-action@v2
  with:
    username: ${{ secrets.DOCKER_USERNAME }}
    password: ${{ secrets.DOCKER_PASSWORD }}
```

- The secrets are injected from GitHub's encrypted Secrets store. Never hardcode passwords in YAML.

```yaml
- name: Build and Push Docker Image
  uses: docker/build-push-action@v4
  with:
    context: .
    push: true
    tags: myrepo/myapp:${{ github.sha }}
```

- `${{ github.sha }}` is the unique commit hash. Every build produces a unique, traceable image tag. Using `latest` would prevent ArgoCD from detecting a change because the Git string would not change.

```yaml
- name: Update Helm Values
  run: |
    yq -i ".image.tag = \"${{ github.sha }}\"" helm/values.yaml
    git commit -am "Update image tag to ${{ github.sha }}"
    git push
```

- `yq -i` edits YAML in place, changing the image tag in the Helm chart. The commit + push back to Git is the "manifest bump" that ArgoCD will detect.

## Production Notes

### From Lesson

- Separate App and Config repos: developers commit code to an App repo; CI builds the image and updates the Helm values in a separate Config repo that ArgoCD watches. This prevents developers from accidentally deploying untested code directly.
- Use specific image tags (SHA or semantic version), never `latest`.
- No direct cluster access: CI never holds kubeconfig credentials; it only needs Git access. ArgoCD handles deployment.
- Use webhooks to instantly notify ArgoCD, rather than waiting for the polling interval.

### Additional Production Knowledge

- Store the Docker account credentials and any registry tokens as encrypted GitHub Secrets, and rotate them periodically.
- Protect the `main` branch so the manifest bump and infra changes go through review.
- Set resource limits and caching on Docker builds (layer caching) so images build fast without starving the runner.

## Best Practices

### From Lesson

- Tag images with `${{ github.sha }}` or a semantic version.
- Keep CI and CD separated by Git: CI builds and commits; ArgoCD pulls.
- Inject credentials only via Secrets, never hardcode.
- Use webhooks for near-instant GitOps reaction.

### Additional Knowledge

- Pin action versions (`uses: actions/checkout@v3`, `@v4`) with a SHA for supply-chain safety on the runner.
- Add a `concurrency` group to cancel superseded runs when a developer pushes two changes quickly.
- Keep the Helm chart version and image tag discoverable; log the exact commit that changed `values.yaml`.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Using `latest` image tag | The string doesn't change, so ArgoCD never detects a new image | Tag with `${{ github.sha }}` or a version. |
| Giving CI kubectl access | CI takes over the cluster if compromised | Keep CI to Git only; let ArgoCD deploy. |
| Forgetting to push the manifest bump | ArgoCD never sees a change | Confirm `git push` of the updated `values.yaml` succeeded. |
| Not syncing the Config repo | ArgoCD watches the wrong repo/branch | Verify the ArgoCD Application repo and target branch. |

## Troubleshooting

### From Lesson

Scenario: the pipeline failed.

- Check the failed run in the GitHub Actions tab, expand the failing step.
- Docker login failed: make sure `DOCKER_USERNAME` and `DOCKER_PASSWORD` are set in repo Secrets.
- Git push failed: the workflow needs write permission. Go to Repo Settings -> Actions -> General -> Workflow permissions and enable "Read and write permissions".

Scenario: ArgoCD didn't deploy.

1. Check Git: did the CI actually commit the new `values.yaml`?
2. Check ArgoCD Application: is it `OutOfSync`? If not, ArgoCD may watch the wrong repo/branch.
3. Check the image tag: if CI used `latest`, the Git string didn't change, so no sync.

### Additional Knowledge

- If the image was pushed but the cluster runs a stale one, the Deployment may cache the old image in the kubelet; force a rollout.
- If updates cause an outage, use `git revert <sha>`; the git-revert short-circuit covers most rollback.

## Comparison Tables

| Feature | Traditional CI/CD (Jenkins) | GitOps CI/CD (GH Actions + ArgoCD) |
|---------|-----------------------------|------------------------------------|
| Trigger | Jenkins pushes to cluster | CI updates Git; ArgoCD pulls |
| Source of truth | Jenkins job config | Git repository |
| Cluster access | Needs kubeconfig | None (runs in cluster) |
| Manual changes | Allowed (drift) | Overwritten (self-heal) |
| Rollback | Re-run old Jenkins job | `git revert` |

## When to Use / When Not to Use

Use CI/CD pipelines:

- Any environment where code changes often.
- When you need strict auditability for cluster changes.
- When you want to separate build from deployment.

Do not use when:

- Doing local development on your laptop: `kubectl apply` is fine.
- Your team isn't yet disciplined about Pull Requests for infra changes.

## Performance & Security Considerations

- Performance: GitHub Actions runners are ephemeral. Large builds can be slow; use Docker layer caching.
- Security: never give CI kubectl access. If a runner is compromised, an attacker can put a malicious image in a registry but cannot directly take over the cluster; ArgoCD remains the secure bridge.

## Real Company Examples

### From Lesson

Shopify runs huge traffic during Black Friday. A developer merges a PR; a GitHub Action builds and pushes the Docker image in a few minutes; another update updates the Helm chart in a separate config repo; ArgoCD deploys to staging. If staging tests pass, an automated system promotes the exact same commit SHA to production. The whole flow takes minutes and no human type a kubectl command.

## Common Myths

- Myth: "ArgoCD replaces CI tools." False. ArgoCD is CD (deploys YAML). You still need CI to compile, test, and build images. CI updates Git; ArgoCD deploys it.
- Myth: "GitOps means you can't use Helm." False. ArgoCD natively supports Helm; point it at a repo with Chart.yaml and values.yaml and it renders and deploys.

## Summary

- CI builds/tests/pushes a Docker image; tags it with the Git SHA; updates values.yaml in Git.
- CD (ArgoCD) pulls that Git change and deploys to the cluster.
- Secrets go via GitHub Secrets; never hardcoded.
- The CI tool should never have direct kubectl access to the cluster.

## Revision Notes & Cheat Sheet

- CI = Build & Push; CD = Pull & Deploy.
- Git SHA = image tag (not latest).
- No direct cluster access for CI; ArgoCD watches Git.

Memory trick:
- GitHub Actions: the factory robot that builds parts and updates the manual.
- Docker registry: the warehouse storing parts.
- ArgoCD: the floor manager reading the updated manual and installing the part.
- Git SHA: the serial number on the part.

| Concept | Tool / Command |
|---------|----------------|
| CI tool | GitHub Actions, Jenkins |
| CD tool | ArgoCD, Flux |
| Image tag | `${{ github.sha }}` |
| YAML editor | `yq` |

## Interview Preparation

### Beginner

Q: Walk me through your CI/CD pipeline.

A: A developer pushes to main. GitHub Actions triggers, builds a Docker image, tags it with the Git SHA, and pushes to the registry. Then it uses `yq` to update the image tag in `values.yaml` and pushes that back to Git. ArgoCD detects the change, syncs the Helm chart, and rolls out in the cluster.

Q: Why shouldn't CI have kubectl access?

A: Security. If a CI tool has kubectl access, an attacker who compromises it can take over the cluster. In GitOps the CI tool only touches Git, and ArgoCD, running inside the cluster, performs the deployment.

### Intermediate

Q: Why tag with Git SHA instead of latest?

A: Immutability and traceability. `latest` never changes in Git so ArgoCD never notices a new image. Tagging with the SHA makes every commit a unique, traceable deployment.

Q: What if the CI pipeline can't push the updated values.yaml back?

A: The image is in the registry, but ArgoCD doesn't know how to deploy it. The cluster keeps the old version. The manifest bump must be committed for a deploy to happen.

### Scenario

Q: A developer merged a bad YAML and ArgoCD deployed it. Production is down.

A: `git revert <commit-sha>`. ArgoCD detects the change, syncs back to the previous working state, and production recovers without `kubectl rollout undo`.

### True / False

- "ArgoCD can build Docker images." False (that's CI).
- "You must use `latest` tags for GitOps." False (never use `latest`).

## Quiz

1. In a GitOps pipeline, what does the CI tool build?
   - A. A Docker image and a manifest bump
   - B. The Kubernetes secrets
   - C. ArgoCD itself
   - D. NetworkPolicies

2. Which image tag strategy do you recommend?
   - A. `latest`
   - B. The Git commit SHA
   - C. Random numbers
   - D. No tags

3. What writes the values.yaml image tag change back to Git before ArgoCD deploys?
   - A. ArgoCD
   - B. The CI workflow (`yq` + git commit/push)
   - C. kubectl
   - D. Grafana

4. A bad config is deployed. What is the GitOps rollback?
   - A. `kubectl rollout undo`
   - B. `git revert <sha>` and ArgoCD syncs
   - C. Rebuild the cluster
   - D. Re-apply the manifests manually

5. True / False: the CI tool should have direct kubectl access to Prod.
   - A. True
   - B. False

Answers: 1-A, 2-B, 3-B, 4-B, 5-B

## Revision

- CI = build/push image + bump manifest; CD = pull from Git and deploy.
- Tag with `${{ github.sha }}`.
- Keep CI off the cluster (only Git), ArgoCD in-cluster does the deploy.
- Rollback = `git revert`; secrets = GitHub Secrets.

## Cheat Sheet

```bash
# yq (Linux)
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Bump and commit the manifest
yq -i '.image.tag = "<sha>"' helm/values.yaml
git add helm/values.yaml
git commit -m "Update image tag to <sha>"
git push

# Optional: install ArgoCD and a demo app
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
argocd app create my-app --repo https://github.com/USER/config.git --path helm --dest-server https://kubernetes.default.svc
```

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [GitOps Principles](https://www.gitops.tech/)
- [docker/build-push-action](https://github.com/docker/build-push-action)

## Related Lessons

- [Lesson 35 - GitOps Principles and Practices](lesson-35-gitops-principles-and-practices.md) - the GitOps foundation this pipeline builds on.
- [Lesson 39 - Helm Deep Dive](../09-packaging/lesson-39-helm-deep-dive-writing-production-charts.md) - the Helm chart that CI updates.
- [Lesson 33 - Helm](../09-packaging/lesson-33-helm.md) - Helm fundamentals.
- [Lesson 15 - Jobs and CronJobs](../03-workloads/lesson-15-jobs-and-cronjobs.md) - running recurring pipeline tasks.

## Coming Next

A deeper walkthrough of the CD side: configuring an ArgoCD Application, introducing the App/Config repo split, and using webhooks to move from polling to instant syncs.