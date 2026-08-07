---
title: "Lab 38 - Advanced Stateful Workloads (Databases and Message Queues)"
lesson: 12
module: "03 Workloads"
tags: [kubernetes, statefulset, databases, headless, quorum, persistence]
---

# Lab 12 - Advanced Stateful Workloads (Databases and Message Queues)

## Objective

Deploy a stateful database workload in Kubernetes using a StatefulSet provided by the Bitnami PostgreSQL Helm chart. Verify stable network identity, per-replica persistence, and ordered scaling behavior. Then deploy a small message queue and demonstrate the same StatefulSet conventions for durability and ordering.

## Prerequisites

- Lesson 12 - Advanced Stateful Workloads (Databases and Message Queues).
- Completion of Lessons 1 through 37.
- A running kind cluster.
- `kubectl` and `helm` installed and configured.
- Familiarity with StatefulSets from Lesson 8 and Helm from Module 09.

## Pre-Lab Checklist

Verify the environment is ready before starting.

```bash
kind get clusters
kubectl cluster-info --context kind-learning
helm version --short
kubectl get nodes --context kind-learning
```

Expected output:

```text
learning
kubectl cluster-info is running at https://127.0.0.1:xxxxx
v3.16.0
NAME                     STATUS   ROLES
learning-control-plane   Ready    control-plane
learning-worker          Ready    <none>
```

### Quick Cluster Setup (kind)

```bash
kind create cluster --name learning
kubectl cluster-info --context kind-learning
```

## Steps

### 1. Add the Bitnami Repository

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo bitnami/postgresql
```

Expected output lists the `bitnami/postgresql` chart and its latest version.

### 2. Install the PostgreSQL StatefulSet

```bash
helm install lab38-db bitnami/postgresql \
  --namespace default \
  --set auth.postgresPassword=SuperSecret123 \
  --set primary.replicaCount=3 \
  --set primary.persistence.size=1Gi \
  --set primary.persistence.storageClass=standard
```

The chart renders a StatefulSet, a Headless Service for stable DNS, a Secret holding the password, and a PVC per replica via `volumeClaimTemplates`.

### 3. Verify the StatefulSet Topology

```bash
kubectl get statefulset
kubectl get pods -l app.kubernetes.io/name=postgresql
kubectl get pvc
kubectl get svc
```

Expected output shows the StatefulSet with 3 Pods, 3 bound PVCs, and headless and client Services.

```bash
kubectl get statefulset lab38-db-postgresql
```

Expected output:

```text
NAME                    READY   AGE
lab38-db-postgresql   3/3     3m
```

```bash
kubectl get pvc
```

Expected output:

```text
NAME                              STATUS   VOLUME
data-lab38-db-postgresql-0       Bound    pvc-abc
data-lab38-db-postgresql-1       Bound    pvc-def
data-lab38-db-postgresql-2       Bound    pvc-ghi
```

### 4. Verify Stable Network Identity

Each replica Pod gets a stable DNS name in the form `pod-N.service-name.namespace.svc`. Resolve the Headless Service and then an individual Pod.

```bash
kubectl get endpoints lab38-db-postgresql-headless
```

Expected output shows one endpoint IP per replica Pod.

Resolve an individual Pod name from inside the cluster:

```bash
kubectl run dns-test --rm --tty -i --restart='Never' --namespace=default \
  --image=busybox:1.36 \
  --command -- sh -c "nslookup lab38-db-postgresql-0.lab38-db-postgresql-headless"
```

Expected output resolves `lab38-db-postgresql-0` to the first replica IP. This stable network identity is what cluster members use to talk to a specific replica, and it does not change when a Pod restarts.

### 5. Insert Data and Confirm Persistence

Retrieve the generated password:

```bash
POSTGRES_PASSWORD=$(kubectl get secret lab38-db-postgresql --namespace default -o jsonpath="{.data.postgres-password}" | base64 --decode)
```

Run a temporary client Pod and connect through the Headless Service:

```bash
kubectl run pg-client --namespace default --rm --tty -i --restart='Never' \
  --image=docker.io/bitnami/postgresql:16 \
  --env="PGPASSWORD=$POSTGRES_PASSWORD" \
  --command -- psql -h lab38-db-postgresql-0.lab38-db-postgresql-headless -U postgres -d postgres -p 5432
```

Inside the psql prompt:

```sql
CREATE TABLE important_data (id int, message text);
INSERT INTO important_data VALUES (1, 'This must not be lost');
\q
```

Simulate a Pod crash:

```bash
kubectl delete pod lab38-db-postgresql-0
kubectl get pods -l app.kubernetes.io/name=postgresql
kubectl get pvc
```

The StatefulSet controller recreates the Pod and reattaches the same PVC. Verify the data survived:

```bash
kubectl run pg-client --namespace default --rm --tty -i --restart='Never' \
  --image=docker.io/bitnami/postgresql:16 \
  --env="PGPASSWORD=$POSTGRES_PASSWORD" \
  --command -- psql -h lab38-db-postgresql-0.lab38-db-postgresql-headless -U postgres -d postgres -p 5432
```

Inside psql:

```sql
SELECT * FROM important_data;
\q
```

Expected output shows your row; the persistent disk survived the restart because the StatefulSet reused the same PVC.

### 6. Scale the StatefulSet and Observe Ordering

Scale down and observe reverse-ordering deletion:

```bash
kubectl scale statefulset lab38-db-postgresql --replicas=1
kubectl get pods -l app.kubernetes.io/name=postgresql -w
```

Expected: Pods terminate from highest ordinal (`-2`) back to lowest, one at a time.

Scale back up and observe ordered startup:

```bash
kubectl scale statefulset lab38-db-postgresql --replicas=3
kubectl get pods -l app.kubernetes.io/name=postgresql -w
```

Expected: Pods start from the lowest ordinal (`-0`) up, only starting the next after the previous is `Ready`. This ordered start and reverse teardown is the key difference from a Deployment.

### 7. Deploy a Message Queue Workload

Deploy RabbitMQ with the Bitnami Helm chart to demonstrate the same durable-stateful pattern for a message queue.

```bash
helm install lab38-mq bitnami/rabbitmq \
  --namespace default \
  --set auth.username=user \
  --set auth.password=UserPass123 \
  --set persistence.enabled=true \
  --set persistence.storageClass=standard
```

Verify the topology:

```bash
kubectl get statefulset lab38-mq-rabbitmq
kubectl get pods -l app.kubernetes.io/name=rabbitmq
kubectl get pvc -l app.kubernetes.io/name=rabbitmq
```

Expected output shows the RabbitMQ StatefulSet, a running Pod, and a bound PVC.

### 8. Observe Quorum and Sequencing

Check the RabbitMQ endpoint reachability and the cluster status to confirm the queue is targetable by stable DNS:

```bash
kubectl get endpoints lab38-mq-rabbitmq
kubectl get svc lab38-mq-rabbitmq -o yaml | grep -A3 -E 'headless|clusterIP'
```

For a clustered queue, replicas negotiate quorum over the Headless Service. Delete the RabbitMQ Pod and confirm the queue data is retained:

```bash
kubectl delete pod lab38-mq-rabbitmq-0
kubectl get pods -l app.kubernetes.io/name=rabbitmq
```

Expected: the Pod is recreated with the same PVC, matching the database behavior. This demonstrates that durable message queues follow the same StatefulSet + PVC + Headless Service pattern.

## Cleanup

Remove the Helm releases. Helm does not delete PVCs by default, so remove each PVC explicitly.

```bash
helm uninstall lab38-db --namespace default
helm uninstall lab38-mq --namespace default
kubectl delete pvc -l app.kubernetes.io/name=postgresql
kubectl delete pvc -l app.kubernetes.io/name=rabbitmq
kubectl delete pod dns-test --ignore-not-found
```

Remove the cluster:

```bash
kind delete cluster --name learning
```

## Verification

- StatefulSet creates Pods sequentially (0, then 1, then 2).
- Each replica Pod has a stable DNS name and a unique persistent PVC.
- Pod deletion and re-creation reattach the same PVC, so data survives.
- Scaling up starts the lowest ordinal first; scaling down deletes the highest first.
- The message-queue workload uses the same ordered, durable pattern.

## Expected Output Snapshot

```text
$ kubectl get pods -l app.kubernetes.io/name=postgresql
NAME                    READY   STATUS    RESTARTS
lab38-db-postgresql-0   1/1     Running   1
lab38-db-postgresql-1   1/1     Running   0
lab38-db-postgresql-2   1/1     Running   0

$ kubectl get pvc -l app.kubernetes.io/name=postgresql
NAME                    STATUS   VOLUME
data-lab38-db-postgresql-0   Bound    pvc-abc
data-lab38-db-postgresql-1   Bound    pvc-def
data-lab38-db-postgresql-2   Bound    pvc-ghi
```

## Related

- Lesson file: [lesson-12-advanced-stateful-workloads.md](../docs/03-workloads/lesson-12-advanced-stateful-workloads.md)
- Lesson file: [lesson-08-statefulsets.md](../docs/03-workloads/lesson-08-statefulsets.md)
- Lab 13: [lab-08-statefulsets.md](lab-08-statefulsets.md)