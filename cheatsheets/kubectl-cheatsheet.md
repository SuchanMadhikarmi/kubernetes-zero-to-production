---
title: kubectl Cheat Sheet
topic: kubectl
status: Complete
tags: [cheatsheet, kubectl, cli, cka]
---

# kubectl Cheat Sheet

## Configuration and Contexts

```bash
kubectl config view                                  # show merged kubeconfig
kubectl config get-contexts                          # list contexts
kubectl config current-context                       # current context
kubectl config use-context <name>                    # switch context
kubectl config set-context --current --namespace=<ns> # set default namespace
kubectl config set-context <name> --user=... --cluster=... --namespace=...
kubectl config rename-context <old> <new>
kubectl config delete-context <name>
kubectl config set-cluster <name> --server=https://1.2.3.4:6443 --certificate-authority=ca.crt
kubectl config set-credentials <name> --client-certificate=... --client-key=...
```

## Namespaces

```bash
kubectl get namespaces
kubectl create namespace <name>
kubectl delete namespace <name>                      # deletes everything inside
kubectl config set-context --current --namespace=<ns> # persist default ns
kubectl get all -n <ns>                              # common resources in a namespace
kubectl get all -A                                    # all namespaces
```

Aliases commonly used in exams: `-n` = namespace, `-A` = all namespaces.

## Resource CRUD

```bash
kubectl apply -f file.yaml           # declarative create/update (recommended)
kubectl create -f file.yaml          # create (errors if exists)
kubectl create deployment nginx --image=nginx
kubectl create job pi --image=busybox -- echo hi
kubectl create configmap cm --from-literal=key=value --from-file=config.txt
kubectl create secret generic creds --from-literal=user=admin --from-literal=pass=secret
kubectl get <resource>               # list
kubectl get <resource> <name>        # single
kubectl get <resource> -o yaml       # full object as yaml
kubectl get <resource> -o wide       # extra columns (IPs, nodes)
kubectl get <resource> -o json       # json output
kubectl describe <resource> <name>   # details + events
kubectl edit <resource> <name>       # open in editor and apply
kubectl delete <resource> <name>
kubectl delete -f file.yaml
kubectl delete pods --all -n <ns>    # all pods in namespace
kubectl delete <resource> -l app=foo # by label selector
```

## Output Formatting and Querying

```bash
kubectl get pods -o wide
kubectl get pods -A
kubectl get pods -n <ns> -l app=nginx,version=v1      # label selector
kubectl get pods -l 'app in (nginx,redis),env notin (dev)'
kubectl get pods --field-selector=status.phase=Running
kubectl get pods --sort-by=.metadata.creationTimestamp
kubectl get pods --sort-by=.status.startTime
kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase
kubectl get pods -o jsonpath='{.items[*].metadata.name}'
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
kubectl get pods --show-labels
kubectl label pods <name> newlabel=value --overwrite
kubectl annotate pods <name> description="my pod"
kubectl get events --sort-by='.lastTimestamp'
kubectl get events -A --field-selector type=Warning
```

## Pod Operations

```bash
kubectl logs <pod>                     # current container logs
kubectl logs <pod> -c <container>      # specific container in multi-container pod
kubectl logs <pod> --previous          # logs of previous (crashed) instance
kubectl logs <pod> -f                  # follow (stream)
kubectl logs -l app=nginx              # all pods matching label
kubectl logs --tail=200 <pod>
kubectl logs --since=10m <pod>

kubectl exec -it <pod> -- /bin/sh      # shell into pod
kubectl exec <pod> -- ls /app          # run command
kubectl exec -it <pod> -c <container> -- sh

kubectl cp <pod>:/path/file ./local
kubectl cp ./local <pod>:/path/file

kubectl port-forward <pod> 8080:80      # forward localhost:8080 -> pod:80
kubectl port-forward svc/<svc> 8080:80
```

## Scaling and Rollouts

```bash
kubectl scale deployment <name> --replicas=5
kubectl scale rs <name> --replicas=3
kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>
kubectl rollout history deployment/<name> --revision=2
kubectl rollout undo deployment/<name>
kubectl rollout undo deployment/<name> --to-revision=2
kubectl rollout restart deployment/<name>   # restart without new image
kubectl rollout pause deployment/<name>
kubectl rollout resume deployment/<name>
kubectl set image deployment/<name> <container>=<image>:<tag>
kubectl autoscale deployment <name> --cpu-percent=70 --min=2 --max=10
```

## Dry Run and Generation

```bash
kubectl run nginx --image=nginx --dry-run=client -o yaml
kubectl create deployment web --image=nginx --replicas=3 --dry-run=client -o yaml
kubectl create job test --image=busybox --dry-run=client -o yaml
kubectl create secret generic creds --from-literal=a=b --dry-run=client -o yaml
kubectl apply -f file.yaml --dry-run=client        # validation without changes
kubectl diff -f file.yaml                          # diff live vs desired
kubectl apply -f file.yaml --server-side           # server-side apply
```

CKA speed tips:

```bash
export k='kubectl'
alias k=kubectl
export do='--dry-run=client -o yaml'
export now='--grace-period=0 --force'
k run nginx --image=nginx $do > pod.yaml
k create deployment d1 --image=nginx --replicas=2 $do > dep.yaml
```

## Taints, Tolerations, and Scheduling Checks

```bash
kubectl taint nodes <node> key=value:NoSchedule
kubectl taint nodes <node> key=value:NoSchedule-
kubectl describe node <node> | grep -i taint
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
kubectl cordon <node>        # prevent new scheduling
kubectl uncordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl top nodes            # cpu/memory usage per node
kubectl top pods             # cpu/memory usage per pod
```

## Verify API and Connectivity

```bash
kubectl api-resources                         # list all resource types
kubectl api-resources --namespaced=false
kubectl api-versions
kubectl explain pod.spec.containers           # built-in documentation
kubectl explain deployment.spec.strategy
kubectl auth can-i create deployments --as=system:serviceaccount:ns:sa
kubectl auth can-i --list -n <ns>
kubectl cluster-info
kubectl version --client
kubectl get componentstatuses                  # control plane health (deprecated in newer versions)
```

## Imperative Cheat Lines

```bash
# Run a one-off pod and wait
kubectl run busybox --image=busybox --restart=Never --command -- sleep 3600
kubectl wait --for=condition=Ready pod/nginx
kubectl wait --for=condition=complete job/pi --timeout=60s

# Delete quickly (CKA)
kubectl delete pod <name> --grace-period=0 --force
kubectl delete namespace <ns> --grace-period=0 --force
```
