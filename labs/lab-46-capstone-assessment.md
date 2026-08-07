---
title: Lab 46 - Final Capstone Assessment and Portfolio Project
lesson: 46
module: 14 Certifications
status: Complete
tags: [lab, capstone, assessment, portfolio, career, interview, gitops]
---

# Lab 46 - Final Capstone Assessment and Portfolio Project

## Prerequisites

- Lesson 46 completed.
- All previous labs 1 through 46 attempted.
- A GitHub account for the portfolio project.

## Objective

Validate readiness for senior roles with a 5-question assessment, then build the portfolio repository that becomes your new resume.

## Part A - Prefer the Assessment

Answer the following without looking back at earlier lessons.

1. A Pod is in `CrashLoopBackOff`. You run `kubectl logs <pod>` and see the app started fine. Why do you need `kubectl logs <pod> --previous`?
2. You deploy an HPA, but it shows `<unknown>/50%` for the target. What are the two most likely reasons?
3. You delete a PVC, but it stays in `Terminating` forever. Why is this happening, and how do you fix it?
4. How does ArgoCD detect and fix "Configuration Drift" if an engineer manually runs `kubectl edit`?
5. Why do we use a Headless Service (`clusterIP: None`) for a StatefulSet instead of a normal ClusterIP Service?

### Check

| Q | Expected Idea |
|---|---------------|
| 1 | Fresh logs on the current container; `--previous` reads the crashed instance's logs (stack trace / `OOMKilled`). |
| 2 | (a) Metrics Server not present or unreachable; (b) missing `resources.requests.cpu` so the HPA has no baseline. |
| 3 | The `kubernetes.io/pvc-protection` finalizer waits for a consumer Pod to terminate or a stuck `Retain` PV/disk. Fix: `kubectl patch pvc <name> -p '{"metadata":{"finalizers":null}}'`. |
| 4 | ArgoCD polls Git, compares to live state, flags it Out of Sync; with `selfHeal` it patches the cluster back to the Git state. |
| 5 | A headless Service exposes per-Pod DNS A records so StatefulSet peers (`db-0`, `db-1`) can address each other directly instead of random load balancing. |

## Part B - The Portfolio Project

1. Create a new public GitHub repository named e.g. `kubernetes-platform-demo`.
2. Add your Helm chart from Lesson 30.
3. Add your GitHub Actions workflow from Lesson 32.
4. Write a `README.md` explaining the architecture (reuse the diagram from Lesson 46), listing the stack: GitHub Actions, ArgoCD, Argo Rollouts, Prometheus, Grafana, Loki, Istio, Cilium.
5. Push a sanitized GitOps directory (no proprietary code or secrets).

## Success Criteria

- You can answer all 5 questions correctly without notes.
- Your repository renders the full platform architecture and includes a runnable Helm chart plus a CI workflow linked to ArgoCD.

## Cleanup

No cluster cleanup is required for this lab; it is portfolio and interview preparation.

[Back to Labs](README.md)