---
title: Interview - Fundamentals
module: 01 Fundamentals
status: Complete
tags: [interview, fundamentals, containers, namespaces, cgroups, kubectl]
---

# Interview - Fundamentals

## Beginner

**Q: What is the difference between a container and a virtual machine?**

A: A VM virtualizes hardware and runs a full guest OS. A container is a Linux process isolated by namespaces and constrained by cgroups, sharing the host kernel. Containers start faster and have a smaller footprint.

**Q: What is the smallest unit you schedule in Kubernetes?**

A: A Pod. It wraps one or more containers that share a network namespace, IP address, and volumes.

**Q: What role does the container runtime play?**

A: It runs containers using the CRI protocol (containerd is the default). The kubelet asks the runtime to pull images and start/stop containers.

## Intermediate

**Q: How do namespaces and cgroups differ?**

A: Namespaces isolate what a process can see (processes, network, filesystem, mounts). Cgroups constrain what it can use (CPU, memory, I/O). Together they provide container isolation and resource limiting.

**Q: What is a kubeconfig and what is a context?**

A: A kubeconfig stores connection information in `~/.kube/config`. A context bundles a cluster, a user, and a namespace; you switch contexts with `kubectl config use-context`.

## Scenario

Q: You run `kubectl get pods` and get `Unable to connect to the server: dial tcp`. What do you check?

A: Check the current context (`kubectl config current-context`), the API server address/port in the kubeconfig, network reachability, and whether the API server is healthy. Verify `kubectl cluster-info`.

## Related

- [Revision - Fundamentals](../revision/fundamentals.md)
- [kubectl Cheat Sheet](../cheatsheets/kubectl-cheatsheet.md)

[Back to Interview Index](README.md)