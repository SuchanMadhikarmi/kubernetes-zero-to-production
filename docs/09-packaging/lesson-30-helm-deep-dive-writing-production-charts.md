---
title: Lesson 30 - Helm Deep Dive (Writing Production Charts)
module: 09 Packaging
lesson: 30
status: Complete
tags: [kubernetes, helm, templating, charts, values, conditionals, loops, production, packaging]
---

# Lesson 30 - Helm Deep Dive (Writing Production Charts)

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

- Explain the limitations of raw YAML and why templating is required for scale.
- Use advanced Helm templating: conditionals (`if`/`else`) and loops (`range`).
- Structure a `values.yaml` file for multi-environment deployments.
- Build a production-style Helm chart from scratch.
- Use `helm lint` and `helm template` to validate charts before deploying.

## Prerequisites

- Completion of Lessons 1 through 38.
- A running kind cluster.
- Helm CLI installed (see Lesson 33).
- kubectl installed and configured.

## Real-world Motivation

### From Lesson

The YAML Proliferation Nightmare: imagine you have a web application. For each environment (Dev, Staging, Prod) you need a Deployment, Service, ConfigMap, Secret, and Ingress. That is 5 files. Across 3 environments, that is 15 files. Now multiply that by 50 microservices. You have 750 YAML files. If you need to change the memory limit for the Dev environment, you have to manually search and edit 250 files. This leads to configuration drift, human error, and outages.

Why this exists: Kubernetes needed a way to reuse and parameterize configurations. Helm was created to turn static YAML into reusable templates. You write one blueprint (a Chart) and feed it different configurations (Values) for Dev, Staging, and Prod. It also tracks the history of your deployments, allowing for instant rollbacks.

### Additional Production Knowledge

The YAML-proliferation problem compounds with team size. With one team owning five services, maintaining `kubectl apply -f` manifest folders is tolerable. Once responsibilities split across platform, app, and compliance teams, the divergent copies drift. A single chart with a strict environment-values convention is a forcing function that keeps Dev, Staging, and Prod behavior consistent while still allowing per-environment tuning. This is the same architecture that drives GitOps: the chart is versioned in Git, every environment references the same revision, and review happens on the diff rather than on hundreds of parallel files.

## Core Concepts

### From Lesson

- **Chart**: A collection of files (templates and defaults) that define a Kubernetes application. It is the "blueprint".
- **Values (`values.yaml`)**: The configuration variables. You can override these using additional YAML files (e.g. `prod.yaml`) or command-line flags (`--set`).
- **Template engine**: Helm uses Go templates (`{{ .Values.appName }}`) to inject variables into standard Kubernetes YAML.
- **Conditionals (`{{ if .Values... }}`)**: Logic to include or exclude resources based on values (e.g. only create an Ingress if `ingress.enabled` is true).
- **Loops (`{{- range ... }}`)**: Logic to generate multiple items (e.g. multiple environment variables) from a list.

### Additional Production Knowledge

- **Built-in objects**: beyond `Values`, Helm provides `Release` (name, namespace, service, revision, isUpgrade, isInstall), `Chart`, and `Capabilities`. Most critical for production are `Release.Namespace` (always scope resource names via the release so two releases can coexist) and `Release.Name` (used to make resource names unique).
- **Named sub-templates**: with `{{ define }}` and `{{ include }}` you can refactor repeated blocks (e.g. shared selector labels) into `_helpers.tpl`, avoiding copy-paste across Deployment and Service. This is why production charts ship a `_helpers.tpl` by default.
- **`tpl` function**: `tpl .Values.someString .` re-renders a string you provided as a template, used for passing templated snippets inside values (e.g. Nginx config that references a service name).

## Architecture

### From Lesson

Helm 3 is entirely client-side. It does not run a server inside your cluster. It renders the YAML on your workstation and applies it via the Kubernetes API server.

```text
[ Developer ]                             
     |                                    
     | 1. Runs `helm install my-app ./my-chart -f prod-values.yaml`
     v
[ Helm Client (Local Machine) ]
     |
     | 2. Merges default values with prod-values.yaml
     | 3. Renders Go templates into final Kubernetes YAML
     v
[ Kubernetes API Server ] (Helm acts like `kubectl apply`)
     |
     v
[ Cluster creates Pods, Services, etc. ]
     |
     +---> [ Secret: sh.helm.release.v1.my-app.v1 ]
              (Stores release state for rollbacks)
```

### Additional Production Knowledge

The chart repository and the release state are two separate concerns. A chart is versioned and stored in an OCI registry or a Chart Repository. A release is the stateful instance that Helm tracks as a Kubernetes secret named `sh.helm.release.v1.<release>.<revision>`. Because that secret lives in the namespace where the release was installed, Helm determines which namespace a release belongs to from the secret's location. Managing releases across many namespaces therefore requires either namespaced `-n` release commands or a dedicated tool/Tiller-like layer. In production this is why most people do not run per-developer `helm install`; instead Helm is invoked inside a CI pipeline or a GitOps controller such as Argo CD or Flux.

## ASCII Diagrams

### From Lesson

```text
[ values.yaml ] + [ templates/*.yaml ]           
      |                                        
      v (Helm Template Engine)                  
[ Final Kubernetes YAML ]                          
      |                                            
      v (kubectl apply equivalent)               
[ Kubernetes API Server ]                          
      |                                            
      v (Creates Pods, Services, etc.)            
```

### Additional Production Knowledge

```text
helm create my-app
      |
      v
my-app/
  Chart.yaml        <- metadata (name, version, dependencies)
  values.yaml       <- default configuration (the Blueprint)
  values.schema.json<- optional JSON schema to validate user values
  charts/           <- sub-charts (vendored dependencies)
  templates/
    _helpers.tpl     <- reusable named sub-templates
    deployment.yaml
    service.yaml
    ingress.yaml
  .helmignore
```

## Hands-on

### From Lesson

Goal: build a production-style Helm chart from scratch using advanced templating (conditionals and loops).

Step 1 - Scaffold the chart:

```bash
helm create my-api
cd my-api
```

Step 2 - Simplify the templates. The default chart creates a lot of complex resources. Delete them to focus on core concepts:

```bash
rm templates/*.yaml templates/*.tpl
rm -rf templates/tests
rm templates/NOTES.txt
```

Step 3 - Replace `values.yaml` with a clean structure:

```yaml
replicaCount: 2
image:
  repository: nginx
  tag: alpine

service:
  port: 80

ingress:
  enabled: true
  path: /

env:
  LOG_LEVEL: "debug"
  DB_HOST: "postgres-svc"
```

Step 4 - Write `templates/deployment.yaml` with a loop:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-api
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      containers:
      - name: app
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        ports:
        - containerPort: {{ .Values.service.port }}
        env:
        {{- range $key, $value := .Values.env }}
        - name: {{ $key }}
          value: {{ $value | quote }}
        {{- end }}
```

Step 5 - Write `templates/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-svc
spec:
  selector:
    app: {{ .Release.Name }}
  ports:
  - port: {{ .Values.service.port }}
    targetPort: {{ .Values.service.port }}
```

Step 6 - Write a conditional Ingress `templates/ingress.yaml`:

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Release.Name }}-ingress
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: {{ .Values.ingress.path }}
        pathType: Prefix
        backend:
          service:
            name: {{ .Release.Name }}-svc
            port:
              number: {{ .Values.service.port }}
{{- end }}
```

Step 7 - Lint and dry-run render:

```bash
helm lint .
helm template my-release .
```

Step 8 - Override for Staging (1 replica, no Ingress) in `staging.yaml`:

```yaml
replicaCount: 1
ingress:
  enabled: false
```

```bash
helm install staging-release . -f staging.yaml
kubectl get deployments
kubectl get ingress
```

Step 9 - Simulate a bad update and roll back:

```bash
helm upgrade staging-release . --set image.tag=broken-tag-123
kubectl get pods   # ImagePullBackOff
helm rollback staging-release 1
kubectl get pods   # recovered
```

Cleanup:

```bash
helm uninstall staging-release
```

## Commands

```bash
# Scaffold a fresh chart
helm create my-app

# Dry-run: render templates to stdout without sending to the cluster
helm template my-app .

# Lint: validate chart metadata and template syntax
helm lint .

# Install a chart with a values override file
helm install my-app ./my-app -f prod-values.yaml

# Upgrade an existing release using an inline value
helm upgrade my-app ./my-app --set image.tag=v2

# List releases
helm list

# Show all revisions of a release
helm history my-app

# Roll back to a specific revision
helm rollback my-app 1

# Uninstall a release (resources + Helm secrets)
helm uninstall my-app
```

## YAML Explanation

The three templates above demonstrate every place a writer makes an error. In the Deployment template:

- `{{ .Release.Name }}` is a built-in Helm object populated at install time (the name given on the CLI). Using it in resource names guarantees uniqueness across releases.
- `{{- range $key, $value := .Values.env }}` iterates the `env` map. For each key, Helm emits one `- name:` / `value:` block. The leading `{{-` trims preceding whitespace and the trailing `-}}` trims following whitespace so the emitted lines keep proper YAML block indentation.
- `| quote` wraps the value in literal quotes (e.g. `"debug"`). Without it, a boolean or number would be emitted unquoted.

In the Service template the selector and ports are parameterized from `values.yaml`. If you change `service.port`, both the Service `port` and the container `containerPort` stay consistent because both read `{{ .Values.service.port }}`.

In the Ingress template the entire file is wrapped in `{{- if .Values.ingress.enabled }}` / `{{- end }}`. When `ingress.enabled` is false the team renders to nothing, so no Ingress is created. Keeping this conditional is what lets a single chart serve Dev without an Ingress and Prod with one.

## Production Notes

### From Lesson

- Never use `latest` for chart versions. Always semantic-version your charts (e.g. `1.2.3`) so you can tie an installed release to the exact template logic.
- Use values file per environment (`dev.yaml`, `prod.yaml`). Avoid `--set` on the CLI for production because it is not reproducible or auditable.
- Run `helm lint` before pushing a chart to catch syntax errors.
- Use `| nindent 4` when injecting multi-line strings, e.g. `{{ .Values.config | nindent 4 }}` for ConfigMap data.

### Additional Production Knowledge

- Set `apiVersion` and explicit `type` in `Chart.yaml`; in practice they keep chart commits reported in `helm list`. Prefer `helm upgrade --install` so the same command creates or updates a release, a pattern used in CI.
- Use `.Release.Namespace` and `include` in `_helpers.tpl` for labels so every resource carries the same `app.kubernetes.io/name`, `instance`, and `managed-by` labels, which tools (Prometheus, Kiali, kube-state-metrics) rely on.
- Set precise CPU/memory requests and limits in the chart defaults so the chart is safe to deploy in a namespaced ResourceQuota without immediately hitting the quota.
- Adopt OCI registry chart hosting (`helm push`) so charts are immutable and referenceable. In production, treat the chart itself as a reviewed artifact, not something every developer can push.
- Add a `values.schema.json` to catch typos and type errors early with `helm lint`.

## Best Practices

### From Lesson

- Never use `latest` for image tags or chart versions; always pin.
- Prefer per-environment values files over `--set`.
- Run `helm lint` before deploying anything.
- Use `{{ .Values.config | nindent 4 }}` for multi-line strings.

### Additional Production Knowledge

- Keep all resource names derived from `Release.Name` (or a helper) so releases can be rolled back and coexist in the same namespace.
- Store `values` in Git and render with `helm template` in CI to review the exact YAML that will go to the cluster.
- Keep template logic minimal: when a template becomes a complex `if/else` tree, split resources into separate files using the file-level `{{- if -}}` guard (as done for the Ingress), which is far easier to read than deeply nested conditionals.

## How It Works Internally

When you run `helm install`, Helm:

1. Reads `Chart.yaml` to validate the chart and read metadata.
2. Reads the default `values.yaml` and merges in any overrides (`--set`, `-f`, `--reuse-values`).
3. Parses every file in `templates/`, evaluates Go template directives, and substitutes values.
4. Validates the rendered YAML against the Kubernetes OpenAPI schema.
5. Sends the manifest set to the API Server (creating Pods, Services, etc.).
6. Stores a copy of the rendered YAML and the merged values in a Kubernetes Secret named `sh.helm.release.v1.<release>.<revision>`.

The stored Secret is exactly what makes `helm rollback` instantaneous in the common case: Helm reads the previous revision from the Secret and re-applies it, so it does not need to reconstruct the chart from Git history.

## Lifecycle

| Stage | Action | Helm behavior |
|-------|--------|---------------|
| Install | `helm install` | Creates Revision 1, saves Secret v1. |
| Upgrade | `helm upgrade` | Computes diff, patches, saves Secret v2. |
| Rollback | `helm rollback <rev>` | Reapplies a past revision's rendered YAML. |
| Uninstall | `helm uninstall` | Deletes release resources and Helm Secrets. |

## Comparison Tables

| Capability | Raw Kubernetes YAML | Helm |
|------------|---------------------|------|
| Reusability | Copy/paste (drift prone) | Templates (DRY) |
| Environment handling | Manual editing | `values.yaml` overrides |
| Rollbacks | `kubectl rollout undo` (Deployment-only) | `helm rollback` (all resource types) |
| Packaging | Loose manifests | Versioned Charts |

### Helm vs Kustomize

| Capability | Helm | Kustomize |
|------------|------|-----------|
| Philosophy | Templating (logic in YAML) | Overlays (patching only) |
| Logic | `if`/`range`/functions supported | No imperative logic |
| Release mgmt | Tracked via Secrets, rollback | No release tracking |
| Best fit | Third-party apps, multi-env scaling | Plain environment overlays with no logic |

## When to Use / When Not to Use

### When to Use

- Managing multiple environments (Dev/Staging/Prod) from a single source.
- Deploying third-party tools (Prometheus, Argo CD, Nginx Ingress Controller).
- Strict version control of infrastructure templates and repeatable installs.

### When Not to Use

- A single, simple, static resource that never changes.
- When you prefer Kustomize's overlay-based patching without logic.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Hardcoded value in template | Forgetting `{{ .Values.xxx }}` and typing `image: nginx:1.25` | Keep all runtime values parameterized in `values.yaml`. |
| Overusing `--set` | Quick one-off overrides become a long unreadable CLI call | Put logic in environment-specific YAML files. |
| Whitespace errors | Missing the `-` in `{{- }}` / `{{- end }}` leaves blank lines | Use `helm template` to inspect rendered output. |
| Deleting the release Secret | Manual cleanup of `sh.helm.release.v1.*` | Never hand-delete release Secrets; they enforce rollback. |

## Troubleshooting

### The Whitespace Trap

Symptom: `error: error parsing Y: yaml: line 4: did not find expected key.`

1. Run `helm template my-release .`.
2. Inspect line 4. Is there a blank line or wrong indentation?
3. Cause: a missing `-` in `{{- range }}` or `{{- end }}` leaves blank lines.
4. Fix: use `{{-` and `-}}` to trim whitespace and `| nindent` to inject multi-line strings with correct indentation.

### The Ingress Never Appears

Symptom: Ingress missing after install.

- Check `templates/ingress.yaml` is wrapped in `{{- if .Values.ingress.enabled }}` and the value is `true` in the effective values. Run `helm get values <release>` to see merged values, then `helm template --set ingress.enabled=true .` to confirm.

### ImagePullBackOff After Upgrade

- Often caused by `--set image.tag` typo. Verify with `kubectl describe pod`, the event shows the image tag it tried to pull. Roll back with `helm rollback`.

## Interview Questions

### Beginner

Q: What is a Helm Chart?

Rationale: A Chart is a collection of Go-template files and a default `values.yaml` that define a Kubernetes application. It packages and reuses configuration as a versioned artifact.

Q: Where does Helm 3 store its release state?

A: As Kubernetes Secrets named `sh.helm.release.v1.<release>.<revision>` in the namespace where the release was deployed.

Q: What is a Helm Release?

A: A single deployed instance of a Chart, tracked by Helm across revisions.

### Intermediate

Q: What is the difference between `helm install` and `helm upgrade`?

A: `helm install` creates a brand-new release (Revision 1). `helm upgrade` modifies an existing release, computes the diff and patches resources, creating Revision 2+.

Q: How do you handle different configs for Dev and Prod?

A: A single chart plus `dev.yaml` / `prod.yaml` override files, selected with `helm install -f <file>`. Keep the overrides in Git for auditability.

### Advanced

Q: How does `helm template` work and how is whitespace controlled?

A: `helm template` renders templates to stdout without talking to the cluster. Go templates control whitespace with `{{-` (trim left) and `-}}` (trim right).

Q: What does `nindent` do and why is it used?

A: It injects captured content starting at a given indentation level, which keeps multi-line values (e.g. ConfigMap data) correctly nested.

### Scenario Questions

**Scenario:** A CI job runs `helm upgrade --install`, then tries to `kubectl apply` the same Deployment and fails. What's wrong?

**Expected answer:** Using both is unnecessary. The fix is to use `helm upgrade --install` for the whole workload, or place 100% of resources in the chart and let Helm own them; `kubectl apply` against chart-owned resources causes ownership conflict (metadata `managedFields`) and drift.

**Scenario:** Dev vs Prod in one cluster: same chart, Deploys 1 vs 10 replicas.

**Expected:** Use a single chart with `-f dev.yaml` and `-f prod.yaml`; route workloads into separate namespaces so labels and Services do not collide.

## Quiz

1. Which template would you use to create the Deployment only when `deployment.enabled` is true?
   - A. `{{- range ... }}`
   - B. `{{- if .Values.deployment.enabled }}`
   - C. `{{- with .Values }}`
   - D. `{{- include ... }}`

2. Which built-in object always holds the release namespace?
   - A. `.Capabilities`
   - B. `.Release.Namespace`
   - C. `.Chart`
   - D. `.Files`

3. In `{{- range $key, $value := .Values.env }}`, what does the leading `{{-` do?
   - A. Prints a newline before each item
   - B. Trims preceding whitespace in the rendered output
   - C. Escapes the loop variable
   - D. Marks the item as a comment

4. Where does Helm store the rendered release state?
   - A. In a ConfigMap in `kube-system`
   - B. In a Secret named `sh.helm.release.v1.<release>.<rev>`
   - C. On the remote chart repository
   - D. In a local `.helm/` folder

5. True or False: Helm 3 runs a `tiller`-style server inside the cluster.
   - A. True
   - B. False

Answers: 1-B, 2-B, 3-B, 4-B, 5-B

## Revision

- __Core model__: Chart = blueprint; `Values` = crayons; Release = the colored picture.
- `helm template` = dry run; `helm rollback` = undo button.
- `{{- if }}` to include/exclude; `{{- range }}` to generate many items; `nindent` for multi-line YAML.
- Helm stores releases as Kubernetes Secrets, which is what makes rollbacks work.
- Client-only: Helm 3 renders locally, a serverless in-cluster component.

## Cheat Sheet

| Command | Purpose |
|---------|---------|
| `helm create <name>` | Scaffold a blank chart directory |
| `helm template <name> <path>` | Dry-run: render YAML to stdout |
| `helm lint <path>` | Validate chart syntax |
| `helm install <name> <path> -f <file>` | Install with values override |
| `helm upgrade <name> <path> --set key=val` | Update a release, bump revision |
| `helm history <name>` | Show revision history |
| `helm rollback <name> <rev>` | Revert to a previous revision |
| `helm uninstall <name>` | Remove the release and its resources |

## Additional Reading & Homework

- Read about Helm repositories: how to `helm repo add` a repo such as Bitnami and `helm search repo <chart>`.
- Read the official Helm documentation on templating.

## References

- [Helm Documentation - Charts](https://helm.sh/docs/topics/charts/)
- [Helm Documentation - Templates](https://helm.sh/docs/chart_template_guide/)
- [Kustomize vs Helm discussion](https://helm.sh/docs/faq/charts/)

## Related Lessons

- [Lesson 42 - Helm](lesson-29-helm.md) - the Helm fundamentals that this lesson deepens.
- [Lesson 12 - Backups and Disaster Recovery with Velero](../12-production/lesson-38-backups-and-disaster-recovery-with-velero.md) - treats Helm-managed state as a record in DR.
- [Lesson 30 - Multi-Cluster Kubernetes](../12-production/lesson-39-multi-cluster-kubernetes.md) - how same chart is applied across clusters with GitOps.

## Coming Next

Lesson 43 (tentatively) continues with production concerns; the next lessons explore how charts are adopted and managed at scale via GitOps.