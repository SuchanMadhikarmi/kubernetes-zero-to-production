---
title: Lesson 46 - Progressive Delivery (Argo Rollouts)
module: 12 Production
lesson: 46
status: Complete
tags: [kubernetes, argocd, argo-rollouts, progressive-delivery, canary, blue-green, analysis-template, deployment, production]
---

# Lesson 46 - Progressive Delivery (Argo Rollouts)

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

- Explain the limitations of standard Kubernetes Deployments for production releases.
- Describe Progressive Delivery and Canary Deployments.
- Explain the Argo Rollouts architecture (Custom Resource Definitions).
- Deploy an application using a Rollout instead of a Deployment.
- Intentionally deploy a bad update, watch the metrics fail, and observe the automatic rollback.

## Prerequisites

- Completion of Lessons 1 through 45.
- A running kind cluster.
- kubectl installed and configured.
- Argo Rollouts CLI installed (we will do this in the lab).

## Real-world Motivation

### From Lesson

The blind rolling update: in an earlier lesson we learned about Rolling Updates. But a Rolling Update blindly pushes the new version to everyone. If the new code has a memory leak or a bug that causes 500 errors, all users get a degraded experience before you realize it and hit `kubectl rollout undo`. In production, this causes massive revenue loss and user trust erosion.

Why this exists: to limit the blast radius of bad deployments. Progressive Delivery (specifically Canary Deployments) sends a new version to a small percentage of users (e.g. 10%), watches error rates, and if everything is green, slowly ramps up to 100%. If errors spike, the system automatically rolls back. Argo Rollouts is the industry-standard tool for this in Kubernetes.

### Additional Production Knowledge

Progressive Delivery is a mindset as much as a tool. The goal is not merely to move a percentage slider but to gate every ramp step on observable evidence that the new version is behaving. Done well, it combines feature flags, traffic shifting, and automated analysis so that the release decision is made by data, not by a human with a stopwatch. The danger is treating Argo Rollouts as a box to tick: without a monitoring stack feeding the AnalysisTemplate, the canary is only as smart as a slow rolling update.

## Core Concepts

### From Lesson

- **Progressive Delivery**: a deployment strategy that gradually shifts traffic to the new version.
- **Canary Deployment**: sending a small percentage of traffic to the new version to test it in production before a full rollout.
- **Rollout CRD**: a drop-in replacement for Deployments with a strategy block supporting canary or blueGreen.
- **AnalysisTemplate**: a CRD defining a metric query (e.g. Prometheus). During a rollout the controller periodically runs it; if the result crosses a threshold, it fires a Failed condition.
- **Stable vs Canary**: the Stable ReplicaSet serves the majority of traffic; the Canary ReplicaSet serves the test traffic.

### Additional Knowledge

- **Blue/Green**: the other native Argo strategy. It spins up 100% of the new version immediately but routes 0% traffic until a hard "promote" switch is flipped. It is safer from a traffic-isolation view but slower to recover and doubles resource usage.
- **Service traffic routing vs Pod scaling**: real canary routing uses the Ingress Controller or Service Mesh to shift proportion of live requests. Without it, Argo can only scale replica counts, which is a rough approximation.
- **ArgoCD + Argo Rollouts**: they complement, not replace. ArgoCD keeps the Rollout YAML in sync from Git; the separate Argo Rollouts controller executes the canary steps inside the cluster.

## Architecture

### From Lesson

Argo Rollouts replaces the standard Deployment object with a Rollout object. It maintains two ReplicaSets, the Stable and the Canary, dynamically splitting traffic between them.

```text
[ User Traffic ]
      |
      v
[ NGINX Ingress ] (Argo Rollouts modifies weights)
      |
      +---> 90% ---> [ Stable ReplicaSet (v1) ]
      |
      +---> 10% ---> [ Canary ReplicaSet (v2) ]
                           |
                           v
                    [ AnalysisTemplate ]
                    (Checks Prometheus: 5xx errors?)
                           |
                           v
                    [ Error rate > 5% ] -> ABORT & Revert to 100% Stable
```

### Additional Production Knowledge

The controller component list: `argo-rollouts` controller (in `argo-rollouts` namespace) watches Rollout resources, creates ReplicaSets, and patches the Ingress/Service to adjust traffic weights. It evaluates AnalysisRuns (instantiated from AnalysisTemplates) and promotes or aborts the canary accordingly. The Rollouts UI plugin for ArgoCD shows the live rollout graph.

## ASCII Diagrams

### From Lesson

```text
[ Rollout v2 Deployed ]
      |
      v
[ Traffic Split: 90% Stable / 10% Canary ]
      |
      v
[ Analysis runs: Prometheus query for 5xx errors ]
      |
      +---> Success (Errors < 5%) -> Ramp to 20% Canary
      |
      +---> Failure (Errors > 5%) -> ABORT! Revert to 100% Stable
```

### Additional Knowledge

Lifecycle of a canary step:

```text
v2 image set
   --> controller creates Canary ReplicaSet
   --> Ingress weight set to 10/90
   --> AnalysisRun evaluates metric
        --> success -> next step weight
        --> failure -> abort (canary scaled to 0, traffic to stable)
   --> when weight hits 100 -> Canary promoted, old Stable scaled down
```

## Hands-on

### From Lesson

Step 1 - Install the Argo Rollouts controller:

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

Step 2 - Install the CLI:

```bash
curl -sLO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
kubectl argo rollouts version
```

Step 3 - Create a Rollout with a 20 -> 40 -> 60 -> 80 -> 100 canary strategy:

```bash
cat <<EOF > rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app-rollout
spec:
  replicas: 4
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: app
        image: nginx:alpine
  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause: {duration: 10s}
      - setWeight: 40
      - pause: {duration: 10s}
      - setWeight: 60
      - pause: {duration: 10s}
      - setWeight: 80
      - pause: {duration: 10s}
EOF
kubectl apply -f rollout.yaml
```

Step 4 - Watch the initial deployment reach 100%:

```bash
kubectl argo rollouts get rollout my-app-rollout --watch
```

Wait until it shows Healthy at weight 100, then Ctrl+C.

Step 5 - The good update:

```bash
kubectl argo rollouts set image my-app-rollout app=nginx:1.25-alpine
kubectl argo rollouts get rollout my-app-rollout --watch
```

Watch it step 20 -> 40 -> 60 -> 80 -> 100, then Ctrl+C.

Step 6 - Break things on purpose: simulate the metric failure path with a manual abort.

```bash
kubectl argo rollouts set image my-app-rollout app=nginx:broken-tag-123
kubectl argo rollouts get rollout my-app-rollout --watch
```

In a second terminal:

```bash
kubectl argo rollouts abort my-app-rollout
```

Step 7 - Investigate:

1. What happened to the Canary ReplicaSet (broken-tag-123) on abort? (Scaled to 0; quarantined.)
2. What happened to the Stable ReplicaSet (nginx:1.25-alpine)? (Scaled back to 4 replicas, 100% traffic.)
3. How did this protect users? (Only a small percentage ever saw the broken Canary; on failure, traffic reverted instantly to Stable, so the majority of users never saw the broken version.)

Cleanup:

```bash
kubectl delete rollout my-app-rollout
kubectl delete namespace argo-rollouts
```

## Commands

```bash
# Install controller and CLI
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
curl -sLO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
kubectl argo rollouts version

# Manage a rollout
kubectl apply -f rollout.yaml
kubectl argo rollouts get rollout my-app-rollout --watch
kubectl argo rollouts set image my-app-rollout app=nginx:1.25-alpine
kubectl argo rollouts abort my-app-rollout
kubectl argo rollouts promote my-app-rollout
kubectl get rollout
```

## YAML Explanation

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app-rollout
spec:
  replicas: 4
  selector:
    matchLabels:
      app: my-app
  template:      # the pod template, same shape as a Deployment
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: app
        image: nginx:alpine
  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause: {duration: 10s}
      - setWeight: 40
      - pause: {duration: 10s}
      - setWeight: 60
      - pause: {duration: 10s}
      - setWeight: 80
      - pause: {duration: 10s}
```

- `apiVersion: argoproj.io/v1alpha1` distinguishes a Rollout from an `apps/v1` Deployment; the rollout controller watches this resource type.
- `spec.template` is the standard Pod spec. It is what makes a Rollout look just like a Deployment until the `strategy` block.
- `strategy.canary.steps` sequences the traffic shift. Each `setWeight` reconfigures the traffic weights; each `pause` waits either a fixed `duration` (here 10s to simulate analysis) or, if omitted, until manual `promote`.
- A `pause: {}` with no duration waits indefinitely for `kubectl argo rollouts promote`. That is intentional for manual-gating stages.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  metrics:
  - name: success-rate
    interval: 60s
    successCondition: result[0] >= 0.95
    failureCondition: result[0] < 0.95
    provider:
      prometheus:
        address: http://prometheus:9090
        query: |
          sum(rate(http_requests_total{job="myapp", status=~"5.."}[1m]))
```

During a rollout Argo creates an `AnalysisRun` from the template, runs the query at the interval, and evaluates `successCondition`/`failureCondition`. A breach of `failureCondition` aborts the rollout.

## Production Notes

### From Lesson

- Use real traffic routing: for true Canary use a Service Mesh (Istio) or NGINX Ingress integration. Scaling ReplicaSets alone (e.g. 9 stable + 1 canary) doesn't isolate long-lived requests.
- Start small: begin with 5% or 10% canary. Starting at 50% risks half your users.
- Analyze latency as well as errors: a new version may be 2x slower without throwing 500s. Query P99 latency too.

### Additional Knowledge

- Couple each canary step with the external metrics provider it depends on; if Prometheus isn't reachable, the analysis can hang or never complete.
- For stateful workloads, use blue/green periodic or a manual strategy; a canary for a database's asymmetric quirk is dangerous.

## Best Practices

- Virtual-address true traffic routing with Ingress/Service Mesh for a real canary.
- Start small (5-10%); ramp in small increments with pauses long enough for meaningful metrics (2-5 minutes).
- Monitor both error rate and latency (P99), plus apdex when available.
- Use a `shiftWeight`/`pause` step ordering that allows manual promote for gating when needed.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Rollout without a traffic router | Only scales replicas; broken canary still errors for 10% | Configure NGINX/Istio traffic routing. |
| Pauses too short | Metrics not yet scraped | Use 2-5 minute pauses, not seconds in prod. |
| Manual workflow without flags | Operator guesses status | Use `kubectl argo rollouts get rollout --watch`. |
| Empty `pause` expecting auto-advance | `pause: {}` waits for manual promote | Add a duration or provide `promote`. |

## Troubleshooting

### From Lesson

Scenario: rollout stuck in `Paused` at 20%.
- Check the strategy: did you set `pause: {duration}` or `pause: {}`? Empty pause waits for manual `promote`.
- Check analysis: `kubectl argo rollouts get rollout <name>` shows analysis status (Error/Pending).
- Check metrics: is Prometheus scraping the app? Empty query results can hang/fail the analysis.

### Additional Knowledge

- If the rollout appears `Degraded` with no traffic shift, confirm the controller has RBAC to patch the Ingress.
- If weights stay at a previous step but the pod image changed, confirm the `pause: {}` wasn't reached. Otherwise promote.

## Comparison Tables

| Feature | Kubernetes Deployment | Argo Rollouts |
|---------|------------------------|---------------|
| Traffic shifting | None (Rolling Update) | Canary (10%, 20%, ...) |
| Metric analysis | None | Automated (Prometheus/Datadog) |
| Auto-rollback | None (manual undo) | Automated on metric failure |
| Pause | None | Yes (manual or timed) |
| Resource | `apps/v1` Deployment | `argoproj.io/v1alpha1` Rollout |

## When to Use / When Not to Use

Use Argo Rollouts:
- Critical production APIs where bad deploys cost revenue.
- You have robust monitoring (Prometheus/Datadog) to feed the AnalysisTemplate.
- You want to test a feature in production on real users with limited risk.

Not for:
- Local development / simple staging.
- No monitoring stack (without metrics it's a slower Deployment).
- Stateful apps (databases).

## Performance & Security Considerations

- Performance: the controller polls the metric provider often during a deploy; in huge clusters this loads Prometheus.
- Security: Rollouts patches Ingress and Mesh configs to shift traffic, so scope the controller's RBAC to only its namespaces.

## Real Company Examples

Intuit during tax season uses Argo Rollouts for every microservice. A new version starts at 5% and an AnalysisTemplate checks latency and 5xx error rates; a latency spike of 10ms aborts automatically, protecting revenue and trust.

## Common Myths

- Myth: "Argo Rollouts replaces ArgoCD." False; they work together. ArgoCD syncs the Rollout YAML; the Argo Rollouts controller executes the steps.
- Myth: "Canary = scaling replicas." False; scaling alone still lets 10% of user's errors if the canary is broken. True canary uses Ingress/Mesh to cut 0% instantly.

## Summary

- Progressive Delivery limits blast radius by gradual traffic shifting.
- Argo Rollouts replaces Deployments with Rollouts and enables canary.
- It analyzes metrics, ramps slowly, and auto-aborts on failure (scales canary to 0, traffic to stable).
- This prevents a bad commit from taking down the whole app.

## Revision Notes & Cheat Sheet

- Rollout = Deployment + Canary.
- Canary = 10% traffic, analyze, 20%, analyze...
- AnalysisTemplate = check Prometheus.
- Abort = instant revert to stable.

Memory trick: canary in the coal mine. Send the canary first; if it stops singing, pull it out and don't send the miners (100%) down. The controller is the safety inspector who hits the red abort when the canary dies.

| Command | What it does |
|---------|--------------|
| `kubectl argo rollouts get rollout <name> --watch` | Live view of canary progress |
| `kubectl argo rollouts set image <name> <container>=<image>` | Trigger a new canary update |
| `kubectl argo rollouts abort <name>` | Manually fail the canary, instant rollback |
| `kubectl argo rollouts promote <name>` | Skip pauses, fast-forward to 100% |

## Interview Preparation

### Beginner

Q: What is Progressive Delivery?

A: A strategy that gradually shifts to the new version rather than updating everything. Limits blast radius.

Q: How does Argo Rollouts differ from a standard Deployment?

A: Deployments do an instant, blind rollout. Argo Rollouts applies Canary progressive shifting and automatic metric analysis to keep platform health positive.

### Intermediate

Q: How does Argo Rollouts determine if the canary is healthy?

A: It uses an AnalysisTemplate to query metric providers (Prometheus) for error/latency; threshold breach aborts the rollout.

Q: What happens to traffic at abort?

A: The Canary ReplicaSet scales to 0, and 100% of traffic reverts to the Stable ReplicaSet immediately.

### Scenario

Q: A new version passes readiness but users report it broken. Fix + prevention?

A: Revert with `kubectl rollout undo`. Prevention: use Argo Rollouts with a canary and an AnalysisTemplate checking 5xx rates; on spike it aborts and reverts automatically.

### True/False

- "Argo Rollouts replaces ArgoCD" → False.
- "Canary deployments require a Service Mesh or Ingress controller for true routing" → True.

## Quiz

1. Which resource does Argo Rollout replace for canary?
   - A. Ingress
   - B. Service
   - C. Deployment
   - D. ConfigMap

2. Which component rewards the analysis of a canary's health?
   - A. AnalysisTemplate
   - B. ServiceMonitor
   - C. NetworkPolicy
   - D. CronJob

3. What happens when the canary is aborted?
   - A. It stays at 100% canary
   - B. Canary scales to 0, traffic reverts to Stable
   - C. Nothing
   - D. Admin must remove Rollout

4. Which traffic router is commonly used to split canary traffic?
   - A. ClusterIP Service
   - B. Nginx Ingress controller
   - C. CoreDNS
   - D. kube-proxy

5. True/False: `pause: {}` with no duration auto-advances.
   - A. True
   - B. False (it waits for a manual promote)

Answers: 1-C, 2-A, 3-B, 4-B, 5-B

## Revision

- Rollout CRD replaces Deployment; canary/blueGreen strategies.
- AnalysisTemplate drives Metric-to-threshold decision.
- Abort → canary to 0, stable back to 100.
- Use Ingress/Mesh for real traffic, short pause w/ metrics-first.

## Cheat Sheet

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
kubectl apply -f rollout.yaml
kubectl argo rollouts get rollout my-app-rollout --watch
kubectl argo rollouts set image my-app-rollout app=nginx:1.25-alpine
kubectl argo rollouts abort my-app-rollout
kubectl argo rollouts promote my-app-rollout
```

## References

- [Argo Rollouts Documentation](https://argoproj.github.io/argo-rollouts/)
- [Progressive Delivery Patterns](https://launchdarkly.com/blog/progressive-delivery/)
- [Argo Rollouts Concepts: Canary](https://argoproj.github.io/argo-rollouts/features/canary/)

## Related Lessons

- [Lesson 12 - Deployments and Rollout Strategies](../03-workloads/lesson-12-deployments-and-rollout-strategies.md) - the Deployment object and its default rolling strategy.
- [Lesson 15 - Jobs and CronJobs](../03-workloads/lesson-15-jobs-and-cronjobs.md) - related on the workload graph.
- [Lesson 43 - Observability Deep Dive (Prometheus and Grafana)](../08-observability/lesson-43-observability-deep-dive-prometheus-and-grafana.md) - feeds the AnalysisTemplate metrics.
- [Lesson 46 related - ArgoCD pipelines](../10-gitops/lesson-35-gitops-principles-and-practices.md) - ArgoCD deploys the Rollout YAML.

## Coming Next

A more production-oriented topic continues: how Argo Rollouts' blue/green strategy and AnalysisTemplate mate with modern service meshes to give full progressive delivery in a mesh-native environment.