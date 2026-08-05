# Labs

Hands-on lab exercises that accompany the lessons.

## Purpose

Every lesson with hands-on content should have a matching lab. Labs take the reader from understanding to doing, with exact commands and expected output.

## Conventions

- File naming: `lab-NN-name.md`, matching the lesson number
- Every lab lists the prerequisite lesson and a target environment
- Commands must be copy-paste runnable
- Expected output is shown so learners can verify their work
- Each lab ends with a cleanup section

## Layout

| File | Lesson | Topic |
|------|--------|-------|
| [lab-01-anatomy-of-a-container.md](lab-01-anatomy-of-a-container.md) | 1 | Namespaces and cgroups |
| [lab-10-pods-replicasets-and-deployments.md](lab-10-pods-replicasets-and-deployments.md) | 10 | Pods, ReplicaSets, Deployments |
| [lab-17-services-and-cluster-networking.md](lab-17-services-and-cluster-networking.md) | 17 | Services and Cluster Networking |
| [lab-18-ingress-and-ingress-controllers.md](lab-18-ingress-and-ingress-controllers.md) | 18 | Ingress and Ingress Controllers |
| [lab-23-configmaps-and-secrets.md](lab-23-configmaps-and-secrets.md) | 23 | ConfigMaps and Secrets |
| [lab-20-persistent-storage-pv-pvc-sc.md](lab-20-persistent-storage-pv-pvc-sc.md) | 20 | Persistent Storage (PVs, PVCs, StorageClasses) |
| [lab-07-scheduling-and-taints.md](lab-07-scheduling-and-taints.md) | 7 | Scheduling and Taints |
| [lab-25-resource-management-and-oomkiller.md](lab-25-resource-management-and-oomkiller.md) | 25 | Resource Management and OOMKiller |
| [lab-15-jobs-and-cronjobs.md](lab-15-jobs-and-cronjobs.md) | 15 | Jobs and CronJobs |
| pending | 2-5 | Fundamentals labs |
| pending | 10-15 | Workloads labs |
| pending | 16-19 | Networking labs |
| pending | 23-25 | Configuration labs |

This table is updated as labs are published.

## Target Environments

Labs run on any local cluster:

- kind
- minikube
- k3s
- Docker Desktop Kubernetes
- Managed clusters (EKS, AKS, GKE)

[Back to Repository Home](../README.md)
