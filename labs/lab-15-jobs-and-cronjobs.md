# Lab 15 - Jobs and CronJobs

## Objective

Create a Job that intentionally fails and observe the retry mechanism. Test parallel Jobs and create a CronJob.

## Prerequisites

- Lesson 15 - Jobs and CronJobs.
- A running kind cluster.
- kubectl installed and configured.

### Quick Cluster Setup (kind)

```bash
kind create cluster --name learning
kubectl cluster-info --context kind-learning
```

## Steps

### 1. Create a Failing Job

```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: failing-batch
spec:
  backoffLimit: 4
  activeDeadlineSeconds: 60
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: busybox:latest
        command: ["sh", "-c", "echo 'Doing work...' && exit 1"]
EOF
```

### 2. Observe the Retry Mechanism

```bash
kubectl get pods -l job-name=failing-batch --watch
```

Expected: New Pods are created. Old ones stay in `Error` state.

### 3. Investigate the Job Status

```bash
kubectl get jobs failing-batch
kubectl describe job failing-batch
```

Look at the `Pods Statuses` section for `Failed` counts.

### 4. Test a Successful Job

```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: success-batch
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: busybox:latest
        command: ["sh", "-c", "echo 'Task completed successfully!' && exit 0"]
EOF
```

```bash
kubectl get jobs success-batch
```

Expected: `COMPLETIONS 1/1`.

### 5. Test Parallel Jobs

```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: parallel-batch
spec:
  completions: 5
  parallelism: 2
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: busybox:latest
        command: ["sh", "-c", "sleep 5 && echo 'Done' && exit 0"]
EOF
```

```bash
kubectl get pods -l job-name=parallel-batch --watch
```

Expected: Exactly 2 Pods running at any given time until 5 have completed.

### 6. Create a CronJob

```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hourly-backup
spec:
  schedule: "0 * * * *"
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: busybox:latest
            command: ["sh", "-c", "echo 'Backup completed at \$(date)' && exit 0"]
EOF
```

```bash
kubectl get cronjobs
```

### 7. Manually Trigger a CronJob

```bash
kubectl create job manual-run --from=cronjob/hourly-backup
kubectl get jobs
```

### 8. Cleanup

```bash
kubectl delete job failing-batch success-batch parallel-batch manual-run
kubectl delete cronjob hourly-backup
kind delete cluster --name learning
```

## Verification

- Failing Job retries up to `backoffLimit`.
- Successful Job shows `COMPLETIONS 1/1`.
- Parallel Job runs exactly `parallelism` Pods at a time.
- CronJob creates Jobs on schedule.

## Expected Output Snapshot

```text
$ kubectl get jobs
NAME             COMPLETIONS   DURATION   AGE
failing-batch    0/1           60s        60s
success-batch    1/1           5s         30s
parallel-batch   5/5           25s        30s
```

## Related

- Lesson file: [lesson-15-jobs-and-cronjobs.md](../docs/03-workloads/lesson-15-jobs-and-cronjobs.md)
