---
title: Lesson 15 - Jobs and CronJobs
module: 03 Workloads
lesson: 15
status: Complete
tags: [kubernetes, jobs, cronjobs, batch-processing, backoff-limit, completions, parallelism]
---

# Lesson 15 - Jobs and CronJobs

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

- Explain why Deployments are the wrong tool for finite tasks.
- Describe what a Job is and how it tracks successful Pod completions.
- Explain the importance of `backoffLimit` and `activeDeadlineSeconds`.
- Describe what a CronJob is and how it schedules Jobs on a recurring loop.

## Prerequisites

- Completion of Lessons 1 through 10.
- A running Kubernetes cluster (see [Lesson 01](../01-fundamentals/lesson-01-anatomy-of-a-container.md) for kind setup instructions).
- kubectl installed and configured.

## Real-world Motivation

### The Infinite Restart Loop

Imagine you write a Python script that connects to a database, dumps the data to a file, and then exits. You deploy this script using a standard Kubernetes Deployment.

1. The container starts, runs the script, and exits with code 0 (Success).
2. The ReplicaSet controller notices the container died. It thinks, "Oh no, an app crashed! I need to maintain my desired replica count of 1!"
3. The ReplicaSet starts a new Pod. The script runs again, dumps the database, and exits.
4. This happens infinitely, filling up your disk with duplicate database backups and wasting compute resources.

### Why This Exists

Kubernetes needed a native way to support the "batch processing" paradigm. The Job object was created to run a task to completion. It expects the Pod to exit. If the Pod exits with code 0, the Job is marked as successful and no more Pods are created. If the Pod exits with a non-zero code (failure), the Job can be configured to retry a certain number of times before giving up.

### Real Company Examples

**Banking Industry:** A major bank runs a CronJob every night at midnight UTC. The Job spins up a Pod that connects to the PostgreSQL database, dumps the database to a file, encrypts it with GPG, and uploads it to AWS S3. Once the upload is successful, the Pod exits with code 0. If the S3 upload fails, the Job retries 3 times before paging the on-call engineer.

## Core Concepts

### Explain Like I'm 12

- A **Deployment** is like a security guard. Their job is to stand at the door forever. If they sit down, the manager makes them stand back up.
- A **Job** is like washing the dishes. You do it until the sink is empty, and then you stop.
- A **CronJob** is an alarm clock that wakes you up to do the Job at the exact same time every day.

### Explain Like I'm a Junior Engineer

When you create a Job, it creates a Pod. If the Pod's container process exits with code 0, the Job is successful. If it exits with a non-zero code, the Job controller will create a new Pod to try again, up to the `backoffLimit`. You use Jobs for data migrations, backups, or processing queue items.

### Explain Technically

- The `JobController` runs inside the `kube-controller-manager`. It watches the API Server for Job objects. When it sees one, it creates a Pod with an `ownerReference` pointing to the Job.
- It tracks the Pod's status. If the Pod's `status.phase` becomes `Failed`, the `JobController` increments its failure counter.
- If the counter exceeds `spec.backoffLimit`, the Job is marked as `Failed` and no more Pods are created.
- It uses an exponential backoff for retries (10s, 20s, 40s, etc.) to avoid spamming the API server.

### How Kubernetes Implements It Internally

For a CronJob, the `CronJobController` runs a loop every 10 seconds. It checks if the current time matches the cron schedule of any CronJob. If it matches, it creates a new Job object. That Job object is then picked up by the `JobController`, which creates the actual Pods.

### Why Kubernetes Was Designed That Way

By separating Jobs from Deployments, Kubernetes allows you to express two fundamentally different intents: "keep this running forever" versus "run this to completion." The Job controller knows that a Pod exit is expected, not a failure, and handles retries appropriately.

## Architecture

```
[ CronJob (Schedule: 0 2 * * *) ]
      |
      v (At 2 AM, creates a Job)
[ Job (completions: 1, backoffLimit: 4) ]
      |
      +---> [ Pod 1 ] -> Exits with Code 1 (Failed)
      +---> [ Pod 2 ] -> Exits with Code 1 (Failed)
      +---> [ Pod 3 ] -> Exits with Code 0 (Success)
      |
      v
[ Job Status: Completed (1/1) ]
```

### Terminology

| Term | Definition |
|------|------------|
| Job | A controller that runs a task to completion. |
| CronJob | A controller that schedules Jobs on a time-based schedule. |
| completions | The number of successful Pod exits required for the Job to be considered complete. |
| parallelism | The number of Pods to run at the same time. |
| backoffLimit | The number of times the Job controller will retry creating a new Pod after a failure before marking the Job as failed. |
| activeDeadlineSeconds | A hard wall-clock timeout. If the Job takes longer than this, it is killed. |
| Exit Code 0 | The Unix standard for a successful process exit. |
| Exit Code 1+ | The Unix standard for a failed process exit. |
| Exponential Backoff | A retry strategy where the wait time between retries increases exponentially. |

### How It Works Internally

1. You create a Job with `backoffLimit: 4`.
2. The `JobController` creates Pod 1.
3. Pod 1's container runs the script. The script crashes (Exit Code 1).
4. The `JobController` sees the failure. It increments the failure counter to 1.
5. It waits 10 seconds (exponential backoff).
6. It creates Pod 2. The script runs successfully (Exit Code 0).
7. The `JobController` increments the success counter to 1.
8. Since `completions` defaulted to 1, the Job is marked as Completed.

### Step-by-Step Workflow

1. Developer creates a Job YAML with a command to run.
2. `kubectl apply` sends it to the API Server.
3. `JobController` creates a Pod.
4. Pod runs and exits.
5. If exit is 0, Job is complete.
6. If exit is non-zero, `JobController` waits and creates a new Pod.
7. Process repeats until success or `backoffLimit` is reached.

### Lifecycle

| State | Description |
|-------|-------------|
| Pending | Job is created, Pod is being scheduled. |
| Running | The Pod is actively executing the script. |
| Completed | The Pod exited with code 0. The desired number of completions has been reached. |
| Failed | The Pod exited with a non-zero code, and the `backoffLimit` was exceeded. |
| Suspended | The Job was manually paused or is waiting for a condition. |

### Deployment vs Job

| Feature | Deployment | Job |
|---------|------------|-----|
| Goal | Keep app running forever | Run task to completion |
| Desired State | N replicas running | N successful exits |
| On Pod Exit (0) | Restart Pod | Mark as Complete |
| On Pod Exit (1) | Restart Pod | Retry (up to backoffLimit) |
| Use Case | Web server, API | Backup, Data migration, Batch script |

### Common Myths

| Myth | Fact |
|------|------|
| "If a Job fails, it restarts the same container." | False. If `restartPolicy: Never`, the Job controller creates a brand new Pod with a new name and new IP. The old failed Pod stays in the cluster with status `Error` so you can inspect its logs. |
| "CronJobs run in the timezone of the cluster admin." | False. CronJobs always run in UTC. |
| "A completed Job's Pod is automatically deleted." | False. It stays for logs unless `ttlSecondsAfterFinished` is set. |

## ASCII Diagrams

Mental Model: A Job is a contract worker. You hire them to build 3 walls (`completions: 3`). If they break a wall (fail), you give them a chance to try again (`backoffLimit`). But if they break the wall 6 times, you fire them (Job Failed).

```
[ Developer: kubectl apply -f job.yaml ]
      |
      v
[ API Server ] -> [ etcd ] (Job: backoffLimit=4)
      |
      v
[ Job Controller ] (Watches for Jobs)
      |
      +---> Pod 1 (Exit 1) -> Failure Count: 1 (Wait 10s)
      +---> Pod 2 (Exit 1) -> Failure Count: 2 (Wait 20s)
      +---> Pod 3 (Exit 0) -> Success Count: 1
      |
      v
[ Job Status: Completed ]
```

### CronJob Flow

```
[ CronJob: schedule="0 2 * * *" ]
      |
      v (At 2:00 AM UTC)
[ CronJob Controller creates Job ]
      |
      v
[ Job Controller creates Pod ]
      |
      v
[ Pod runs, exits with code 0 ]
      |
      v
[ Job marked as Completed ]
      |
      v (Next day at 2:00 AM UTC)
[ CronJob Controller creates new Job ]
```

## Hands-on

### Objective

Create a Job that intentionally fails, observe the retry mechanism, and watch it eventually time out.

### Step 1: Create the Job

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

### Step 2: Observe the Retry Mechanism

```bash
kubectl get pods -l job-name=failing-batch --watch
```

Expected: New Pods are created with names like `failing-batch-xxxxx`. Old ones stay in `Error` state.

### Step 3: Investigate the Job Status

```bash
kubectl get jobs failing-batch
kubectl describe job failing-batch
```

Look at the `Pods Statuses` section. You will see `1 Failed`, then `2 Failed`, etc. The Events section will show `Error: backoff limit exceeded`.

### Step 4: Test a Successful Job

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

### Step 5: Test Parallel Jobs

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

### Step 6: Create a CronJob

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

### Step 7: Cleanup

```bash
kubectl delete job failing-batch success-batch parallel-batch
kubectl delete cronjob hourly-backup
```

## Commands

```bash
# List Jobs
kubectl get jobs

# Describe a Job (shows Pod statuses and events)
kubectl describe job <name>

# List CronJobs
kubectl get cronjobs

# Check Job logs
kubectl logs -l job-name=<name>

# Delete a Job and its Pods
kubectl delete job <name>

# Manually trigger a CronJob
kubectl create job manual-run --from=cronjob/hourly-backup
```

## YAML Explanation

```yaml
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
```

### Field-by-Field Explanation

- `spec.backoffLimit: 4`: The Job will try 4 times before giving up.
- `spec.activeDeadlineSeconds: 60`: If the whole Job takes longer than 60 seconds, kill it.
- `spec.template.spec.restartPolicy: Never`: Mandatory for Jobs. Creates a new Pod on failure instead of restarting the same container.
- `command: ["... && exit 1"]`: The script prints a message and then intentionally exits with code 1 (error).

### CronJob Fields

```yaml
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
            command: ["sh", "-c", "echo 'Backup completed' && exit 0"]
```

- `schedule`: Standard Linux cron syntax (always UTC).
- `successfulJobsHistoryLimit`: Keep only 3 successful Job objects.
- `failedJobsHistoryLimit`: Keep only 3 failed Job objects.

## Production Notes

- **Always set `activeDeadlineSeconds`.** If a database backup script hangs waiting for a lock, it will run forever, consuming node resources silently. Set a hard timeout so the Job is killed if it hangs.
- **Set `ttlSecondsAfterFinished`.** By default, completed Job Pods stay in the cluster forever so you can read their logs. This fills up etcd. Set `ttlSecondsAfterFinished: 3600` to automatically delete the Pods 1 hour after completion.
- **Remember CronJob Timezones.** Kubernetes CronJobs always run in UTC. If you are in EST and want a job to run at 2 AM local time, you must calculate the UTC offset (e.g., 7 AM UTC).
- **Set history limits.** For CronJobs, set `successfulJobsHistoryLimit` and `failedJobsHistoryLimit` (e.g., to 3). Otherwise, every run creates a Job and Pods that stay forever, eventually crashing etcd.
- **Use `restartPolicy: OnFailure`** if you want the kubelet to restart the same container in place (saves Pod creation overhead). Use `Never` if you want a fresh Pod each time.

### When to Use / When NOT to Use

**Use a Job/CronJob when:**

- Database backups (pg_dump to S3).
- Data ETL pipelines (process a file and exit).
- Queue workers that process a finite number of items and stop.
- Running database schema migrations before an application deploy.

**Do NOT use a Job when:**

- Web servers or APIs. They should never exit. Use a Deployment.
- Message queue consumers that listen forever. Use a Deployment.

### Performance and Security Considerations

**Performance:** If you set `parallelism: 5` and `completions: 100`, the Job controller will run 5 Pods at once. Ensure your application supports concurrent execution (e.g., multiple workers pulling from the same queue without locking each other).

**Security:** Jobs often run with high privileges (e.g., accessing database credentials). Ensure the ServiceAccount attached to the Job has strict RBAC and is not the default account.

## Best Practices

- Always set `activeDeadlineSeconds` to prevent hanging Jobs.
- Set `ttlSecondsAfterFinished` to clean up completed Jobs.
- Set history limits on CronJobs to prevent etcd bloat.
- Use `restartPolicy: OnFailure` for efficiency, `Never` for debugging.
- Monitor Job failures with alerts on `backoffLimit exceeded`.
- Use `concurrencyPolicy: Forbid` on CronJobs to prevent overlapping runs.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Using `restartPolicy: Always` | Copying from Deployment YAML | Jobs require `Never` or `OnFailure` |
| Forgetting `activeDeadlineSeconds` | Assuming scripts always finish | Always set a hard timeout |
| Not setting history limits | CronJobs accumulate forever | Set `successfulJobsHistoryLimit` and `failedJobsHistoryLimit` |
| Running CronJobs in local timezone | Assuming Kubernetes respects local time | CronJobs always run in UTC |

## Troubleshooting

**Symptom: Job stuck in Running forever**

Cause: Script is hung or `activeDeadlineSeconds` not set.

```bash
kubectl logs -l job-name=<name>
kubectl describe job <name>
```

Fix: Set `activeDeadlineSeconds` or manually delete the Job.

**Symptom: Job failed with `backoff limit exceeded`**

Cause: Script exits with non-zero code and retries were exhausted.

```bash
kubectl logs -l job-name=<name> --previous
```

Fix: Debug the script, fix the error, and re-run the Job.

**Symptom: CronJob not running**

Cause: Schedule is in UTC, or `concurrencyPolicy: Forbid` is blocking due to a previous run.

```bash
kubectl get cronjobs
kubectl describe cronjob <name>
```

Fix: Verify the schedule matches your intended UTC time. Check if a previous Job is still running.

## Interview Questions

**Q: What is the difference between a Deployment and a Job?**

A: A Deployment ensures a specific number of Pods are always running (self-healing). A Job ensures a specific number of Pods successfully terminate (run to completion).

**Q: Why must a Job have `restartPolicy: Never`?**

A: So the Job controller creates a brand new Pod for a retry, rather than just restarting the same failed container in place. This ensures a clean slate for the retry.

**Q: What is the difference between `backoffLimit` and `activeDeadlineSeconds`?**

A: `backoffLimit` is the max number of retries (e.g., 4 failed attempts). `activeDeadlineSeconds` is a hard wall-clock time limit. If the deadline hits, the Job is killed even if retries are left.

**Q: You have a Python script that takes 1 hour to run. You deploy it as a Job. It keeps failing after 30 minutes. How do you debug it?**

A: I would run `kubectl logs -l job-name=<name> --previous` to see the output of the failed Pod before it restarted. If the logs show a timeout, I might need to increase `activeDeadlineSeconds` if it was set too low. If it's a memory leak, I'd check `kubectl describe pod` for OOMKilled.

**Q: How do you prevent CronJob runs from overlapping?**

A: Set `concurrencyPolicy: Forbid` in the CronJob spec. This prevents a new Job from being created if the previous one is still running.

**Q: Do CronJobs run in the cluster's timezone?**

A: No. CronJobs always run in UTC. You must calculate the UTC offset for your desired local time.

## Scenario Questions

**Scenario 1:** You have a CronJob scheduled to run every 5 minutes. It processes a queue of messages. Sometimes, a single run takes longer than 5 minutes, causing overlapping Jobs. How do you fix this?

A: Set `concurrencyPolicy: Forbid` on the CronJob. This prevents a new Job from being created until the previous one completes.

**Scenario 2:** You need to run a database migration script before every deployment. Should you use a CronJob or a Job?

A: Use a Job. It's a one-time task that runs to completion. A CronJob is for recurring schedules.

**Scenario 3 (Mini Project - The Parallel Queue Processor):**

Create a Job with `completions: 5` and `parallelism: 2`. Use the busybox image with a command that sleeps for 5 seconds and exits 0. Watch the Pods. You should see exactly 2 Pods running at any given time, until 5 have successfully completed.

## Quiz

1. What exit code indicates success for a Job?
   - A. 1
   - B. 0
   - C. 137
   - D. 200

2. What happens when a Job Pod exits with code 1?
   - A. Job is marked as Complete
   - B. Job retries (up to backoffLimit)
   - C. Pod is restarted immediately
   - D. Job is deleted

3. What is `activeDeadlineSeconds`?
   - A. The time between retries
   - B. A hard timeout that kills the Job
   - C. The schedule for a CronJob
   - D. The number of completions

4. What timezone do CronJobs use?
   - A. Local timezone
   - B. UTC
   - C. The node's timezone
   - D. The user's timezone

5. What `restartPolicy` is required for Jobs?
   - A. Always
   - B. OnFailure or Never
   - C. UnlessStopped
   - D. Any

Answers: 1-B, 2-B, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- Jobs are for finite tasks (batch processing, backups, migrations).
- A Pod exiting with code 0 is a success. A non-zero exit code is a failure.
- `backoffLimit` defines the max number of retries.
- `activeDeadlineSeconds` is a hard timeout that kills hanging Jobs.
- CronJobs schedule Jobs on a repeating loop (always in UTC).
- `restartPolicy: Never` is mandatory for Jobs so the controller creates a fresh Pod on failure.

Memory trick:

- Deployment: A lighthouse keeper. Stays forever.
- Job: A painter. Paints the house, then goes home.
- `activeDeadlineSeconds`: The homeowner saying, "If you aren't done by 5 PM, pack up your brushes and leave."

Key facts:

- Exit Code 0 = Success.
- Exit Code 1+ = Failure.
- `backoffLimit` = Retries.
- `activeDeadlineSeconds` = Hard timeout.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl get jobs` | Lists Jobs. Check the COMPLETIONS column. |
| `kubectl describe job <name>` | Shows Pods Statuses (Failed/Succeeded) and Events. |
| `kubectl get cronjobs` | Lists CronJobs and their schedules. |
| `kubectl logs -l job-name=<name>` | Shows logs of Job Pods. |
| `kubectl delete job <name>` | Deletes a Job and its Pods. |
| `kubectl create job manual-run --from=cronjob/<name>` | Manually triggers a CronJob. |

## References

- [Kubernetes Documentation: Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Kubernetes Documentation: CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- [Kubernetes Documentation: Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [Linux man page: exit(2)](https://man7.org/linux/man-pages/man2/exit.2.html)

## Related Lessons

- [Lesson 10 - Pods, ReplicaSets, and Deployments](lesson-10-pods-replicasets-and-deployments.md) - for long-running workloads.
- [Lesson 13 - StatefulSets](lesson-13-statefulsets.md) - for stateful workloads.
- [Lesson 14 - DaemonSets](lesson-14-daemonsets.md) - for cluster-wide agents.
- [Module 06 - Configuration](../06-configuration/README.md) - ConfigMaps and Secrets for Job configuration.
- [Module 12 - Production](../12-production/README.md) - production hardening.

## Coming Next

Now that you understand how to run both long-running and finite workloads, the next lesson covers DaemonSets, which ensure a Pod runs on every node in the cluster.
