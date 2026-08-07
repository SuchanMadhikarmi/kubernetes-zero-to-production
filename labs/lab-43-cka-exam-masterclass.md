# Lab 43 - CKA Exam Masterclass (Speed and Shortcut Techniques)

## Prerequisite

- Completion of [Lesson 43 - CKA Exam Masterclass (Speed and Shortcut Techniques)](../docs/14-certifications/lesson-43-cka-exam-masterclass.md).
- A Linux terminal (Ubuntu) with bash and vim.
- A running kind cluster.
- kubectl installed and configured.

## Objective

Configure your terminal exactly as you would on exam day, then race to create, expose, and inspect workloads using only imperative commands and the `$do` flag. Reach the "60-Second Challenge" at the end.

## Estimated Time

15 minutes.

---

## Step 1: Configure .vimrc

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

Expected: editing `~/.vimrc` writes the settings; any vim session afterward uses 2-space indentation and shows line numbers.

## Step 2: Configure .bashrc aliases and exports

```bash
cat <<EOF >> ~/.bashrc

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
export do='--dry-run=client -o yaml'
export now='--force --grace-period 0'
EOF
source ~/.bashrc
```

Verify the aliases are active:

```bash
alias k
export | grep ' do='
```

Expected output: show both the `k` alias and the `do` export.

## Step 3: Context switching check

```bash
kubectl config get-contexts
kubectl config current-context
```

Expected output: the list of available contexts and the active one. In the exam you will switch before every task.

## Step 4: Imperative generators

Create a namespace, Deployment, and Service entirely from the CLI:

```bash
k create ns exam-lab
k create deploy my-app --image=nginx --replicas=3 -n exam-lab
k expose deploy my-app --port=80 --target-port=80 --type=NodePort -n exam-lab
kubectl get pods -n exam-lab
```

Expected output: three Pods running and a NodePort Service `my-app`.

## Step 5: The $do flag

Generate manifests into files without typing any YAML:

```bash
k create deploy my-app --image=nginx --replicas=3 $do > deploy.yaml
cat deploy.yaml
```

Expected output: a full, schema-valid Deployment YAML printed to the screen, with nothing created in the cluster yet (verify with `kubectl get deploy -n exam-lab`, which shows no Deployment).

## Step 6: Edit the generated YAML and apply

Open the generated file in vim, add a CPU/memory limit to the container, save, and apply:

```bash
vim deploy.yaml
kubectl apply -f deploy.yaml -n exam-lab
kubectl get deploy -n exam-lab
```

Apply the deployment.

## Step 7: The 60-Second Challenge

Time yourself. Create a Deployment with 4 replicas, expose it as a NodePort Service, and generate a ConfigMap, all using imperative commands and the `$do` flag:

```bash
time (
  k create ns speed-test
  k create deploy speed-app --image=nginx --replicas=4 -n speed-test $do > speed-deploy.yaml
  k apply -f speed-deploy.yaml -n speed-test
  k create cm speed-config --from-literal=loglevel=debug -n speed-test
  k expose deploy speed-app --port=80 --target-port=80 --type=NodePort -n speed-test
  k get po,svc -n speed-test
)
```

Goal: the whole script finishes in under 60 seconds. Practice until it does.

## Verification

```bash
kubectl get pods,svc,cm -n speed-test --no-headers
kubectl get pods -n exam-lab  # confirm the lab resources are Running
```

## Cleanup

```bash
kubectl delete ns exam-lab speed-test lab-test
```

## Summary

You set up the `.vimrc` and `.bashrc` speed layer, generated manifests with `$do` without touching the API server, switched contexts, and completed the 60-Second Challenge. Replicate this routine before any exam task.