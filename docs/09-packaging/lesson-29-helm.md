---
title: Lesson 29 - Helm
module: 09 Packaging
lesson: 29
status: Complete
tags: [kubernetes, helm, packaging, charts, templates, values, rollbacks, package-manager]
---

# Lesson 33 - Helm

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

- Explain why raw YAML doesn't scale in production.
- Describe what Helm is and the concept of a Chart.
- Explain how Values (`values.yaml`) override template variables.
- Install Helm, deploy an app using a public Chart, and update it.
- Use `helm rollback` to instantly revert a failed deployment.

## Prerequisites

- Completion of Lessons 1 through 14.
- A running kind cluster.
- kubectl installed and configured.
- Helm CLI installed (we will do this in the lab).

## Real-world Motivation

### The YAML Proliferation Nightmare

Imagine you have a web application. For each environment (Dev, Staging, Prod), you need a Deployment, Service, ConfigMap, Secret, and Ingress. That's 5 files. Across 3 environments, that's 15 files. Now multiply that by 50 microservices. You have 750 YAML files. If you need to change the memory limit for the Dev environment, you have to manually search and edit 250 files. This leads to configuration drift, human error, and outages.

### Why This Exists

Kubernetes needed a way to reuse and parameterize configurations. Helm was created to turn static YAML into reusable templates. You write one blueprint (a Chart), and you feed it different configurations (Values) for Dev, Staging, and Prod. It also tracks the history of your deployments, allowing for instant rollbacks.

### Real Company Examples

**Spotify:** Spotify uses Helm to manage their microservices. They have a central "Charts" repository. When a new microservice is created, developers copy a standard Helm Chart. For Dev, they set `replicas: 1` and `storage: 1Gi`. For Prod, they set `replicas: 10` and `storage: 500Gi`. Same chart, completely different infrastructure.

## Core Concepts

### Explain Like I'm 12

Imagine a coloring book. The black-and-white outlines are the Templates. You have a box of crayons called Values. You can color the same outline 3 different ways (red for Dev, blue for Staging, green for Prod) without redrawing the outline every time.

### Explain Like I'm a Junior Engineer

Helm is a package manager for Kubernetes, just like `apt` is for Ubuntu or `npm` is for Node.js. A package in Helm is called a Chart. A Chart contains templates of your Kubernetes objects. When you run `helm install`, Helm merges your `values.yaml` with the templates, generates the final YAML, and sends it to the Kubernetes API Server.

### Explain Technically

- Helm uses Go templates. It takes a `values.yaml` file and injects those variables into `.yaml` template files (e.g., `image: {{ .Values.image.tag }}`).
- Helm 3 is entirely client-side. It renders the YAML on your local machine and applies it via the standard Kubernetes API.
- It stores the "release state" (what it deployed) as a Kubernetes Secret in the namespace. This allows it to track revisions and perform rollbacks.

### How Kubernetes Implements It Internally

Kubernetes doesn't know about Helm. Helm is just an external tool that acts like a human typing `kubectl apply`. When you run `helm upgrade`, Helm fetches the current state from the Secret, compares it to the new state, figures out the diff, and sends only the necessary PATCH requests to the API Server.

### Why Kubernetes Was Designed That Way

Kubernetes was designed to be tool-agnostic. It doesn't care how you generate the YAML — as long as the YAML is valid, the API Server accepts it. This allows tools like Helm, Kustomize, and others to exist without modifying the core platform.

## Architecture

```
[ Developer ]
      |
      | 1. Runs `helm install my-app ./my-chart -f prod-values.yaml`
      v
[ Helm Client (Local Machine) ]
      |
      | 2. Merges default values with prod-values.yaml
      | 3. Renders Go templates into final K8s YAML
      v
[ Kubernetes API Server ] (Helm acts like `kubectl apply`)
      |
      v
[ Cluster creates Pods, Services, etc. ]
      |
      +---> [ Secret: sh.helm.release.v1.my-app.v1 ] (Stores release state for rollbacks)
```

### Terminology

| Term | Definition |
|------|------------|
| Chart | A Helm package containing template files and a default `values.yaml`. |
| Values | Variables passed to the templates to customize the deployment. |
| Release | An instance of a Chart running in the cluster. |
| templates/ | The directory in a Chart containing the Go-template YAML files. |
| Chart.yaml | Metadata about the chart (name, version). |

### How It Works Internally

1. You run `helm install my-web ./my-chart`.
2. Helm reads `Chart.yaml` to verify the chart is valid.
3. Helm reads `values.yaml` and merges any overrides (e.g., `--set image.tag=v2`).
4. Helm parses every file in `templates/`. It replaces `{{ .Values.xxx }}` with the actual values.
5. It validates the generated YAML against the Kubernetes API schema.
6. It sends the YAML to the API Server.
7. It saves a copy of the rendered YAML and the values into a Kubernetes Secret named `sh.helm.release.v1.my-web.v1`.

### Step-by-Step Workflow

1. Developer creates a Chart with `helm create my-app`.
2. Developer writes standard K8s YAML in the `templates/` folder, replacing hardcoded values with `{{ .Values.xxx }}`.
3. Developer defines defaults in `values.yaml`.
4. Developer runs `helm install my-app ./my-app -f prod-values.yaml`.
5. Helm renders and applies the YAML.
6. Developer needs to update the image tag. They run `helm upgrade my-app ./my-app --set image.tag=v2`.
7. Helm calculates the diff, patches the Deployment, and saves a new Secret (v2).

### Lifecycle

| State | Description |
|-------|-------------|
| Install | Creates the first release (Revision 1). |
| Upgrade | Modifies the release (creates Revision 2, 3, etc.). |
| Rollback | Reverts to a previous revision (e.g., from v3 back to v1). |
| Uninstall | Deletes all Kubernetes resources associated with the release and deletes the Secrets. |

### Feature Comparison

| Feature | Raw K8s YAML | Helm |
|---------|--------------|------|
| Reusability | Copy/Paste (Drift prone) | Templates (DRY) |
| Environment Mgmt | Manual editing | `values.yaml` overrides |
| Rollbacks | `kubectl rollout undo` (limited to Deployments) | `helm rollback` (reverts ALL resources) |
| Packaging | Tarballs of YAMLs | Versioned Charts |

### Common Myths

| Myth | Fact |
|------|------|
| "Helm is a server running in my cluster." | False. Helm 3 is purely a client-side CLI tool. It stores its state in standard Kubernetes Secrets, but there is no "Tiller" or Helm server running. |
| "Helm replaces Kustomize." | They solve similar problems but differently. Helm uses templating (logic in YAML). Kustomize uses overlays (patching YAML without logic). Both are valid. |

## ASCII Diagrams

Mental Model: Helm is a factory. You feed it blueprints (Templates) and raw materials (Values). The factory builds the final product (Kubernetes YAML) and ships it to the store (API Server).

```
[ values.yaml ] + [ templates/*.yaml ]
      |
      v (Helm Template Engine)
[ Final K8s YAML ]
      |
      v (kubectl apply equivalent)
[ Kubernetes API Server ]
      |
      v (Creates Pods, Services, etc.)
```

## Hands-on

### Objective

Install Helm, create a basic chart, deploy it, and then perform a rollback.

### Step 1: Install Helm CLI

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
helm version
```

### Step 2: Generate a Basic Helm Chart

```bash
helm create my-app
cd my-app
```

### Step 3: Simplify the Templates

```bash
rm templates/*.yaml templates/*.tpl
rm -rf templates/tests
rm templates/NOTES.txt
```

### Step 4: Write Your Own Template

Create a new file for the Deployment:

```bash
cat <<EOF > templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-deployment
  labels:
    app: {{ .Values.appName }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Values.appName }}
  template:
    metadata:
      labels:
        app: {{ .Values.appName }}
    spec:
      containers:
      - name: {{ .Values.appName }}
        image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
        ports:
        - containerPort: 80
EOF
```

**Field Explanation:**

- `{{ .Release.Name }}`: A built-in Helm variable (the name you give when you install).
- `{{ .Values.xxx }}`: Pulls from the `values.yaml` file.

### Step 5: Write Your Own Values File

```bash
cat <<EOF > values.yaml
appName: my-nginx
replicaCount: 2

image:
  repository: nginx
  tag: alpine
EOF
```

### Step 6: Test the Rendering (Dry Run)

```bash
helm template my-web .
```

### Step 7: Install Your Custom Chart

```bash
helm install my-web .
```

Verify it worked:

```bash
kubectl get deployments
```

Expected output: A deployment named `my-web-deployment` with 2 replicas.

### Step 8: Simulate a Bad Upgrade

```bash
helm upgrade my-web . --set image.tag=broken-tag-123
```

Check the pods:

```bash
kubectl get pods
```

Expected output: A new Pod trying to start, but failing with `ImagePullBackOff`.

### Step 9: Rollback

```bash
helm history my-web
helm rollback my-web 1
```

Check the pods again:

```bash
kubectl get pods
```

Expected output: The broken pod is gone, and the healthy alpine pods are running.

### Step 10: Cleanup

```bash
helm uninstall my-web
cd ..
```

## Commands

```bash
# Scaffold a blank chart directory
helm create <name>

# Dry-run. Renders YAML to screen
helm template <name> <path>

# Deploys the chart to the cluster
helm install <name> <path>

# Updates an existing release
helm upgrade <name> <path> --set key=val

# Shows the revision history
helm history <name>

# Reverts a release to a previous state
helm rollback <name> <revision>

# Deletes the release and resources
helm uninstall <name>

# Lint a chart for syntax errors
helm lint <path>
```

## YAML Explanation

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-deployment
  labels:
    app: {{ .Values.appName }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Values.appName }}
  template:
    metadata:
      labels:
        app: {{ .Values.appName }}
    spec:
      containers:
      - name: {{ .Values.appName }}
        image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
        ports:
        - containerPort: 80
```

### Field-by-Field Explanation

- `{{ .Release.Name }}`: Built-in variable. The name you pass to `helm install`.
- `{{ .Values.appName }}`: Custom variable from `values.yaml`.
- `{{ .Values.image.repository }}`: Nested variable. `image.repository` in `values.yaml`.
- `{{ .Values.image.tag }}`: Nested variable. `image.tag` in `values.yaml`.

## Production Notes

- **Never use `latest` for Chart versions:** Always version your charts (e.g., 1.2.3). This allows you to track exactly which template logic was applied.
- **Use `values.yaml` files for environments:** Keep your Dev values in `dev.yaml` and Prod values in `prod.yaml`. Avoid using `--set` on the CLI for production, as it is not reproducible or auditable.
- **Use `helm lint`:** Run this command before pushing a chart to catch syntax errors.

### When to Use / When NOT to Use

**Use Helm when:**

- Managing multiple environments (Dev/Staging/Prod).
- Deploying 3rd party tools (Prometheus, ArgoCD, Nginx Ingress).
- When you need strict version control of your infrastructure templates.

**Avoid Helm when:**

- For a single, simple, static Pod that never changes.
- If you are using Kustomize (Kubernetes native patching) instead.

### Performance and Security Considerations

**Performance:** Helm renders templates locally, so it has zero impact on the cluster's control plane performance.

**Security:** Helm can execute templating functions that read local files. Do not run untrusted Helm charts from the internet without inspecting them first. Always read the `templates/` folder of a public chart.

## Best Practices

- Always version your charts (never use `latest`).
- Use `values.yaml` files for environments (not `--set`).
- Run `helm lint` before deploying.
- Use `helm template` to dry-run before applying.
- Never delete Helm release Secrets manually.
- Inspect public charts before installing them.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Hardcoding values in templates | Forgetting to use `{{ .Values.xxx }}` | Always use template variables |
| Overusing `--set` | Writing massive CLI commands | Put complex values in YAML files |
| Deleting the Release Secret | Manually deleting Helm Secrets | Never touch Helm Secrets directly |
| Not linting charts | Assuming templates are correct | Always run `helm lint` before deploying |

## Troubleshooting

**Symptom: `helm upgrade` fails with "release not found"**

Cause: The release Secret was deleted.

```bash
helm list --all-namespaces
```

Fix: If the Secret is gone, you cannot upgrade. You must `helm uninstall` and `helm install` again.

**Symptom: Pods stuck in `ImagePullBackOff` after `helm upgrade`**

Cause: The image tag doesn't exist.

```bash
helm history <release>
```

Fix: `helm rollback <release> <previous-revision>`.

**Symptom: `helm template` fails with "function not defined"**

Cause: Old Helm version or invalid template syntax.

```bash
helm version
```

Fix: Upgrade Helm to the latest version.

## Interview Questions

**Q: What is a Helm Chart?**

A: A Helm Chart is a collection of Go-template files and a default `values.yaml` file that define a Kubernetes application. It allows you to package and reuse configurations.

**Q: Where does Helm 3 store its release state?**

A: As a Kubernetes Secret in the namespace where the release was deployed.

**Q: If a `helm upgrade` results in an `ImagePullBackOff`, what will `helm history` show for the new revision's status?**

A: `deployed`. Helm only tracks if the API Server accepted the YAML, not if the application is actually running.

**Q: You have 50 microservices. How do you manage different memory limits for Dev vs Prod without writing 100 YAML files?**

A: I would use Helm. I would create a single Helm Chart for the microservice. I would create a `dev-values.yaml` and a `prod-values.yaml`. When deploying to Dev, I run `helm install -f dev-values.yaml`. When deploying to Prod, I use the prod values file. This keeps the template DRY and manageable.

**Q: Does Helm run a server inside the Kubernetes cluster?**

A: No. Helm 3 is purely a client-side CLI tool. It stores its state in standard Kubernetes Secrets, but there is no "Tiller" or Helm server running.

**Q: Do you need to run `kubectl apply` after `helm install`?**

A: No. Helm applies the YAML for you via the Kubernetes API.

## Scenario Questions

**Scenario 1:** You need to deploy the same application to three environments with different replica counts and image tags. How do you manage this?

A: I would create a single Helm Chart. I would create three values files: `dev.yaml`, `staging.yaml`, and `prod.yaml`. Each file would override `replicaCount` and `image.tag`. I would run `helm install -f dev.yaml` for Dev, and so on.

**Scenario 2:** You just ran `helm upgrade` and the new Pods are crashing. How do you recover?

A: I would run `helm history <release>` to see the previous revision. Then I would run `helm rollback <release> <previous-revision>` to revert to the last working state.

**Scenario 3 (Mini Project - The Environment Split):**

Create a Helm chart for an Nginx web server. In `values.yaml` (Dev defaults), set `replicaCount: 1` and `image.tag: alpine`. Create a new file `prod.yaml`. Set `replicaCount: 4` and `image.tag: 1.25`. Install the chart twice: once as `dev-web` (using defaults), and once as `prod-web` using `-f prod.yaml`. Verify that `dev-web` has 1 pod and `prod-web` has 4 pods.

## Quiz

1. What is a Helm Chart?
   - A. A running instance of an application
   - B. A package containing templates and default values
   - C. A Kubernetes Secret
   - D. A Docker image

2. Where does Helm 3 store its release state?
   - A. In a ConfigMap
   - B. In a Kubernetes Secret
   - C. On the developer's laptop
   - D. In etcd directly

3. What does `helm template` do?
   - A. Deploys the chart to the cluster
   - B. Renders the YAML to the screen without deploying
   - C. Creates a new chart
   - D. Deletes a release

4. What is the benefit of using Helm over raw YAML?
   - A. Better performance
   - B. Templating and reusability
   - C. Built-in security
   - D. Automatic scaling

5. What happens when you run `helm rollback`?
   - A. Deletes the release
   - B. Reverts to a previous revision
   - C. Upgrades to the latest version
   - D. Creates a new release

Answers: 1-B, 2-B, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- Chart = Blueprint.
- Values = Crayons.
- Release = The colored picture.
- `helm template` = Dry run.
- `helm rollback` = Undo button.

Memory trick:

- **Templates:** The coloring book outline.
- **Values:** The crayons.
- **Helm Release:** A snapshot of a colored page. If you mess up, ask the book for the previous snapshot.

Key facts:

- Chart = Package.
- Values = Configuration.
- Release = Running instance.
- Helm 3 = Client-only.
- Rollback = Revert to previous revision.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `helm create <name>` | Scaffolds a blank chart directory |
| `helm template <name> <path>` | Dry-run. Renders YAML to screen |
| `helm install <name> <path>` | Deploys the chart to the cluster |
| `helm upgrade <name> <path> --set key=val` | Updates an existing release |
| `helm history <name>` | Shows the revision history |
| `helm rollback <name> <revision>` | Reverts a release to a previous state |
| `helm uninstall <name>` | Deletes the release and resources |

## References

- [Helm Documentation](https://helm.sh/docs/)
- [Helm Charts Repository](https://artifacthub.io/)
- [Kubernetes Documentation: Helm](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/)
- [Kustomize vs Helm](https://www.google.com/search?q=kustomize+vs+helm)

## Related Lessons

- [Lesson 19 - ConfigMaps and Secrets](../06-configuration/lesson-20-configmaps-and-secrets.md) - injecting configuration into Pods.
- [Helm Deep Dive](lesson-30-helm-deep-dive-writing-production-charts.md) - writing production charts with Helm.
- [Lesson 31 - GitOps Principles and Practices](../10-gitops/lesson-31-gitops-principles-and-practices.md) - using Git as the source of truth.

## Coming Next

Now that you understand Helm, the next lesson covers Kustomize — the Kubernetes-native alternative to templating that uses overlays instead of logic.
