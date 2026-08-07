---
title: Lesson 40 - CKA Exam Masterclass (Speed and Shortcut Techniques)
module: 14 Certifications
lesson: 40
status: Complete
tags: [kubernetes, cka, certification, kubectl, aliases, vim, dry-run, exam, imperative]
---

# Lesson 40 - CKA Exam Masterclass (Speed and Shortcut Techniques)

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

- Explain the structure and rules of the Certified Kubernetes Administrator (CKA) exam.
- Configure the mandatory shell aliases and vim settings that save 15-20 minutes during the exam.
- Choose between imperative commands (`kubectl create`) and declarative YAML.
- Use the official Kubernetes documentation efficiently during the exam.

## Prerequisites

- Completion of Lessons 1 through 39.
- A Linux terminal (Ubuntu) with bash and vim.
- A running kind cluster to practice commands.

## Real-world Motivation

### From Lesson

The time crunch: the CKA exam consists of ~15-17 tasks in a remote Linux terminal. You have 2 hours. The biggest enemy is time. If you type out `kubectl get pods -n kube-system` 50 times, you waste 10 minutes. If you write a full Deployment YAML from scratch instead of using `kubectl create`, you will run out of time. If you do not know how to exit vim properly, you will panic.

Why this exists: the CNCF designed the CKA as a practical exam because multiple-choice questions do not prove you can actually fix a broken cluster. They want engineers who can type the commands and read the output under pressure. These speed techniques are not just for the exam; they are the exact shortcuts Senior SREs use every day to operate clusters efficiently.

### Additional Production Knowledge

The CKA score is a pass/fail threshold (66%) per exam, and every exam domain counts toward the total. There is no per-section cutoff, so maximizing total points matters more than any single task. This means the strategy of collecting all easy points first is not just a comfort tip; it is a scoring optimization. In real production, the same imperative-generation habit (`--dry-run=client -o yaml`) also reduces mistakes: the API schema is validated by kubectl itself, and a human reviews the generated manifest instead of a hand-typed one.

## Core Concepts

### From Lesson

- **Imperative commands**: Commands that create resources immediately (e.g. `kubectl create deploy`). Used for speed.
- **Declarative YAML**: Applying YAML files (e.g. `kubectl apply -f`). Used for complex configurations or when docs are copied.
- **`--dry-run=client -o yaml`**: The magic flag. Tells kubectl to generate the YAML for a resource without actually creating it in the cluster.
- **Aliases**: Shortcuts for long commands (e.g. `alias k=kubectl`).
- **vim configuration**: Settings in `~/.vimrc` that prevent YAML indentation errors.

### Additional Production Knowledge

- **Saving the aliases permanently**: In the exam terminal and in real life, aliases written to `~/.bashrc` survive shell restarts, but the current shell needs `source ~/.bashrc` (or a new terminal). On exam day, verify the aliases are live in the same shell you type in.
- **`kubectl explain`**: The fastest way to discover a field's schema without leaving the terminal. `kubectl explain deployment.spec.template.spec.containers.resources --recursive` is often faster than opening the docs and is fully allowed during the exam.
- **`--dry-run=server` vs `--dry-run=client`**: `client` validates locally against the OpenAPI schema and never contacts the API server; `server` dry-run sends the object to the API server, which performs admission webhook and validation checks without persisting it. During the exam, `client` is what you want for speed; `server` is useful to confirm a generated object passes admission policies.

## Architecture

### From Lesson

The exam environment provides a `student` user with sudo privileges on a jump host. You use this host to access multiple Kubernetes clusters via kubectl.

```text
[ Your Brain ] -> [ Aliased Fingers ] -> [ kubectl ] -> [ Cluster ]
      |
      v (If stuck)
[ Official K8s Docs ] -> Copy/Paste YAML -> [ Cluster ]
```

### Additional Production Knowledge

The jump host ships with multiple pre-configured contexts, one per cluster (`cluster1`, `cluster2`, etc.). Each question names the cluster it targets. Switching is done with `kubectl config use-context <name>`, and you can confirm with `kubectl config current-context`. Because `kubectl` reads the context at command time, forgetting to switch means you silently apply the workload to the wrong cluster. A single `kubectl config get-contexts` before starting a question is a cheap guard.

## ASCII Diagrams

### From Lesson

```text
[ Problem: Create a Service ]
      |
      +---> Junior: Writes 15 lines of YAML from memory (2 mins)
      |
      +---> Senior: Runs `k expose deploy app --port=80 --target-port=8080 $do > svc.yaml` (5 secs)
```

### Additional Production Knowledge

```text
kubectl create deployment my-app --image=nginx --replicas=3 $do
      |
      | 1. kubectl parses flags
      | 2. constructs a Deployment object in memory
      | 3. --dry-run=client: no request sent to API server
      | 4. -o yaml: serializes object to YAML on stdout
      v
> deploy.yaml  (redirect into a file)
      |
      v
vim deploy.yaml -> add missing fields -> kubectl apply -f deploy.yaml
```

## Hands-on

### From Lesson

Goal: configure your Ubuntu terminal with the exact aliases and vim settings you should use in the CKA exam, then test the speed of imperative commands.

Step 1 - The `.vimrc` setup. The exam terminal uses vim. By default vim uses tabs of 8 spaces, which breaks YAML formatting:

```bash
cat <<EOF > ~/.vimrc
set expandtab
set tabstop=2
set shiftwidth=2
set autoindent
set smartindent
set nu
set ic
EOF
```

- `expandtab`, `tabstop=2`, `shiftwidth=2`: crucial for YAML. Pressing Tab inserts 2 spaces.
- `autoindent`, `smartindent`: keep indentation aligned as you press Enter.
- `nu`: shows line numbers.
- `ic`: ignores case when searching.

Step 2 - The `.bashrc` aliases:

```bash
cat <<EOF >> ~/.bashrc

# --- CKA ALIASES ---
alias k='kubectl'
alias kg='kubectl get'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgd='kubectl get deploy'
alias kgns='kubectl get ns'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kdp='kubectl describe pod'
alias krm='kubectl delete'
alias kdr='kubectl drain --ignore-daemonsets --delete-emptydir-data'
alias kunc='kubectl uncordon'

# Export dry-run to save typing!
export do='--dry-run=client -o yaml'
export now='--force --grace-period 0'
EOF

# Apply the changes immediately
source ~/.bashrc
```

- `export do='--dry-run=client -o yaml'`: the holy grail of the CKA.
- `export now='--force --grace-period 0'`: forces deletion instantly.

Step 3 - Test the speed. Generate a ConfigMap without writing any YAML:

```bash
k create cm my-config --from-literal=key1=value1 $do > cm.yaml
cat cm.yaml
```

Generate a Deployment:

```bash
k create deploy my-app --image=nginx --replicas=3 $do > deploy.yaml
cat deploy.yaml
```

Step 4 - The imperative command cheat sheet:

```bash
# Namespace
k create ns my-namespace
# Pod
k run nginx --image=nginx
# Deployment
k create deploy nginx --image=nginx --replicas=4
# Service
k expose deploy nginx --port=80 --target-port=80 --type=NodePort
# ConfigMap
k create cm my-cm --from-literal=DB=postgres
# Secret
k create secret generic my-secret --from-literal=password=mypassword
# ServiceAccount
k create sa my-sa
# Role
k create role pod-reader --verb=get,list,watch --resource=pods
# RoleBinding
k create rolebinding my-rb --role=pod-reader --serviceaccount=default:my-sa
```

### Additional Production Knowledge

- When a Deployment's Pod spec needs a custom field (resources, liveness probe, volume), do not write the whole file. Generate the base with `$do`, edit only the added block in vim, and `kubectl apply -f`. Target the minimum delta between generated YAML and the question's requirement.
- For YAML that must be pasted inside `spec:` (e.g. adding `tolerations` to a Deployment), use `kubectl edit deploy <name>` and add the block at the correct indentation, or apply a small patch with `kubectl patch`.
- Practice the full loop under a timer at least three times before exam day: context switch, generate, edit, apply, verify.

## Commands

```bash
# Speed shell setup
cat <<EOF > ~/.vimrc
set expandtab
set tabstop=2
set shiftwidth=2
set autoindent
set smartindent
set nu
set ic
EOF

cat <<EOF >> ~/.bashrc
alias k='kubectl'
export do='--dry-run=client -o yaml'
export now='--force --grace-period 0'
EOF
source ~/.bashrc

# Context switching (never skip this)
kubectl config get-contexts
kubectl config use-context cluster2
kubectl config current-context

# Imperative generators
k create ns my-namespace
k run nginx --image=nginx
k create deploy nginx --image=nginx --replicas=4
k expose deploy nginx --port=80 --target-port=80 --type=NodePort
k create cm my-cm --from-literal=DB=postgres
k create secret generic my-secret --from-literal=password=mypassword
k create sa my-sa
k create role pod-reader --verb=get,list,watch --resource=pods
k create rolebinding my-rb --role=pod-reader --serviceaccount=default:my-sa

# Dry-run generation into a file
k create deploy my-app --image=nginx --replicas=3 $do > deploy.yaml
kubectl apply -f deploy.yaml
```

## YAML Explanation

The key to the CKA is that you almost never write YAML by hand. The `$do` flag produces schema-correct YAML that you then edit. For example, after running:

```bash
k create deploy my-app --image=nginx --replicas=3 $do > deploy.yaml
```

you get a Deployment with `metadata.name: my-app`, `spec.replicas: 3`, and a single container named `my-app` with `image: nginx`. You then open it in vim and change exactly what the question needs, e.g.:

```yaml
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: my-app
        image: nginx
        resources:
          limits:
            cpu: "500m"
            memory: "256Mi"
```

Adding the `resources` block inside the existing `container` item preserves correct indentation because `.vimrc` uses `expandtab` and `shiftwidth=2`. If instead you had to type the entire Deployment from memory, a single misplaced space on a `- name:` list item would fail `kubectl apply`.

The `expose` generator for a Service is similar: it produces a Service whose `selector` already matches the Deployment's labels (`app: nginx`), so no manual label surgery is needed.

## Production Notes

### From Lesson

- Skip hard questions first: the exam lets you move freely. Collect all easy points first (creating a namespace, creating a pod), then return to the hard ones.
- Use the docs: do not memorize complex YAML. Search the docs for the resource type and copy the example.
- Verify everything: after creating a Pod, run `kubectl get pods` to confirm it is `Running`. If it is `CrashLoopBackOff`, fix it before moving on.

### Additional Production Knowledge

- A question that says "if the resource already exists, delete it and recreate" is common. Use `k rm --ignore-not-found=true -f <file>` or `kubectl delete` with `--ignore-not-found` so your script does not fail when the object is absent.
- When a task involves multiple objects (e.g. Pod + Service + NetworkPolicy), create the leaf resources first in dependency order, then the Policy that references them, to avoid transient admission errors.
- Track remaining time roughly: two minutes per question is a healthy pace. If a single question eats more than ten minutes, leave it, mark it, and come back only if time remains.

## Best Practices

### From Lesson

- Configure `.vimrc` and `.bashrc` at the very start of the exam, before reading questions.
- Read the question, note the cluster context, then `kubectl config use-context <context>`.
- Choose imperative vs declarative based on complexity.
- Use `$do` to generate base YAML whenever you need a manifest.
- Apply and verify before moving on.

### Additional Production Knowledge

- Prefer `kubectl create` for objects that do not need repeated updates and `kubectl apply` for anything you generate to a file; mixing both on the same object leaves confusing annotations.
- Use `kubectl get events -n <ns> --sort-by=.lastTimestamp` to see why a Pod is stuck, instead of guessing.
- Bookmark the official docs pages you expect to use (CronJob, PersistentVolume, NetworkPolicy, RBAC) before exam day; bookmarks persist in the exam browser.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Writing YAML from scratch | Believing it is more reliable | Always use `kubectl create ... $do` to generate a base. |
| Typing `kubectl` fully every time | Habit | Use the `k` alias from `.bashrc`. |
| Getting stuck in vim | Not knowing basic commands | Practice `:wq` and `:q!` until they are reflex. |
| Forgetting to switch contexts | Question says cluster2, work lands on cluster1 | Run `kubectl config use-context` first; verify with `current-context`. |
| Leaving a broken resource unverified | Assuming the command succeeded | Always `kubectl get` the resource and check status. |

## Troubleshooting

### From Lesson

The YAML indentation trap: you copy a YAML block from the Kubernetes docs, paste it into vim, and apply. You get `error: error parsing YAML: yaml: line 4: found character that cannot start any token`.

- Cause: the pasted YAML contains Tab characters. YAML strictly forbids tabs for indentation.
- Fix in vim: open the file, type `:retab` and press Enter. This converts all tabs to spaces based on `.vimrc` settings, then save and apply.

### Additional Production Knowledge

- If `kubectl apply` fails with `error validating "x.yaml": error validating data`, the file contains a field the API does not know (often from a doc for a different version). Check `apiVersion` and run `kubectl explain <kind>` to confirm the field exists in this cluster's version.
- If a generated Pod stays `Pending`, run `kubectl describe pod <name>` and look at Events: it is almost always an unschedulable node (taint, insufficient CPU/memory) or a missing PVC, not a YAML error.
- If `kubectl expose` says "no pods" or "service already exists", confirm the selector matches and that you are on the correct namespace.

## Interview Questions

### From Lesson (Exam Prep)

Q: What resources are allowed during the CKA exam?

A: The official Kubernetes documentation (`kubernetes.io/docs`), the Kubernetes GitHub repos, and the Kubernetes blog. Generic search engines, StackOverflow, and AI tools are not allowed.

Q: What is the passing score for the CKA?

A: 66%.

Q: Why is `expandtab` important in `.vimrc` during the exam?

A: YAML strictly forbids tab characters for indentation. `expandtab` forces vim to convert tabs to spaces automatically, preventing API Server parsing errors.

### Additional Production Knowledge

Q: What is the difference between `--dry-run=client` and `--dry-run=server`?

A: `client` validates and renders locally against the OpenAPI schema without contacting the API server. `server` sends the object to the API server so admission webhooks and schema validation run, but nothing is persisted. `client` is the fast option for generating manifests in the exam; `server` validates against cluster policy.

Q: Why do exam questions require a context switch, and how do you confirm you are on the right cluster?

A: The exam provides several independent clusters and each question targets one. `kubectl` acts on whatever context is current. You confirm with `kubectl config current-context` (or `kubectl config get-contexts`) right after switching, before creating anything.

## Scenario Questions

**Scenario:** You need to create a ServiceAccount and bind it to a Role that can only read ConfigMaps. What is the fastest sequence of commands?

**Expected answer:**

```bash
k create sa my-sa
k create role cm-reader --verb=get,list --resource=configmaps
k create rolebinding my-rb --role=cm-reader --serviceaccount=default:my-sa
```

**Scenario:** You generated a Deployment YAML with `$do`, applied it, and the Pod is in `CrashLoopBackOff`. You have five minutes left.

**Expected answer:** Do not rewrite anything. Run `kubectl get events --sort-by=.lastTimestamp` and `kubectl logs <pod> --previous` to identify the failure (usually a bad command, missing env var, or missing ConfigMap). Fix the one field in the generated file with `kubectl edit` or a small patch, then re-verify. If it is not fixable quickly, move on and return if time permits.

**Scenario:** Question says "switch to context cluster2 and create a NetworkPolicy that allows only port 80 ingress."

**Expected answer:**

```bash
kubectl config use-context cluster2
kubectl config current-context
# generate a base NetworkPolicy from docs example, or write it with correct apiVersion
kubectl apply -f netpol.yaml
kubectl get netpol
```

## Quiz

1. What flag combination generates a resource's YAML without contacting the API server?
   - A. `--dry-run=client -o yaml`
   - B. `--dry-run=server -o json`
   - C. `-o yaml --validate=false`
   - D. `--dry-run=client -w`

2. What is the passing score for the CKA exam?
   - A. 75%
   - B. 70%
   - C. 66%
   - D. 80%

3. Which `.vimrc` setting converts tabs to spaces so YAML parses correctly?
   - A. `set nu`
   - B. `set expandtab`
   - C. `set ic`
   - D. `set smartindent`

4. Which command switches kubectl to another exam cluster?
   - A. `kubectl config use-context <name>`
   - B. `kubectl switch-context <name>`
   - C. `kubectl set-context <name>`
   - D. `kubectl context <name>`

5. True or False: In the CKA exam you may use k9s and other third-party CLI tools.
   - A. True
   - B. False

Answers: 1-A, 2-C, 3-B, 4-A, 5-B

## Revision

- The CKA is a 2-hour, ~15-17 task, performance-based exam; passing score is 66%.
- `alias k=kubectl` and `export do='--dry-run=client -o yaml'` are the two most valuable shell lines.
- `.vimrc` essentials: `expandtab`, `tabstop=2`, `shiftwidth=2`, `autoindent`, `nu`.
- Always switch context first, then verify with `current-context`.
- Generate base YAML with `$do`, edit only the delta in vim, then apply.
- Collect easy points first; never leave a question unverified.

## Cheat Sheet

```bash
# Aliases
alias k=kubectl
export do='--dry-run=client -o yaml'
export now='--force --grace-period 0'

# Imperative generators
k create deploy NAME --image=IMG --replicas=3 $do > deploy.yaml
k expose deploy NAME --port=80 --target-port=8080 --type=NodePort $do > svc.yaml
k create cm NAME --from-literal=key=val $do > cm.yaml
k create secret generic NAME --from-literal=key=val $do > sec.yaml
k create ns NAME
k run PODNAME --image=IMG
k create sa NAME
k create role NAME --verb=get,list,watch --resource=pods
k create rolebinding NAME --role=ROLE --serviceaccount=NS:SA
```

## References

- [CKA Exam Curriculum](https://github.com/cncf/curriculum)
- [Kubernetes Documentation: Managing Kubernetes Objects](https://kubernetes.io/docs/concepts/overview/working-with-objects/)
- [Kubernetes Documentation: kubectl reference](https://kubernetes.io/docs/reference/kubectl/)

## Related Lessons

- [Lesson 33 - Helm](../09-packaging/lesson-33-helm.md) - imperative vs declarative mindset that carries into exam tasks.
- [Lesson 27 - RBAC and Service Accounts](../07-security/lesson-27-rbac-and-service-accounts.md) - Role and RoleBinding generation patterns.
- [Module 14 Index](README.md) - where the CKA sits in the certification path; the full exam-domain guide follows in later lessons.

## Coming Next

Lesson 41 continues the certification track with the complete CKA Exam Guide: every exam domain mapped to this repository's lessons, plus a timed full-practice-exam strategy.