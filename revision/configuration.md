---
title: Revision - Configuration
module: 06 Configuration
status: Complete
tags: [revision, configuration, configmap, secret, resources, quota]
---

# Revision - Configuration

## 1. The Mental Model

Kubernetes has two unrelated jobs in this module: (1) get configuration and secrets into your container without rebuilding the image, and (2) decide how much CPU and memory every container is allowed to use.

Think of it like a food truck:

- **ConfigMap** = the plain printed menu. Anyone can read it. It holds non-sensitive settings (log levels, URLs, flags).
- **Secret** = the locked recipe box. It holds sensitive values (passwords, tokens, certs), base64-encoded.
- **Request** = your reservation. The scheduler books you a table that can hold at least this much. It guarantees you get the seat.
- **Limit** = a waiter who watches your plate. If you try to eat more than the limit, you are asked to leave.

The two ideas only meet inside a Pod spec: the Pod pulls config from ConfigMaps/Secrets and tells the scheduler/kernel how much resource it needs.

## 2. Core Concepts

### ConfigMaps

- A namespaced object storing key/value pairs in `data` (plain text) or `binaryData` (base64, for binary files).
- Values can be scalars (`APP_MODE: prod`) or whole files (a multi-line block such as `config.json: |`). Size limit is 1 MiB.
- Delivered two ways: as environment variables (`env`/`envFrom`) or as files mounted from a `configMap` volume.
- **Env vars are frozen at container creation.** Editing the ConfigMap does not change running containers; you must restart the Pod (or rollout).
- **Mounted volumes do update**, but only after the kubelet sync period (~1 minute). `subPath` mounts do NOT update.
- `immutable: true` stops the API server watching the object; use it when the app does not hot-reload config.

### Secrets

- Same idea, but for sensitive data. Values in `data` must be base64-encoded; `stringData` accepts plain text and is encoded for you at apply time.
- Common types: `Opaque` (arbitrary pairs), `kubernetes.io/tls` (certs), `kubernetes.io/dockerconfigjson` (registry credentials).
- Consumed identically via `secretKeyRef`/`envFrom` or a `secret` volume.
- **A Secret is NOT a security boundary.** base64 is encoding, not encryption. Anyone with read access can decode it in seconds.
- At rest in etcd, Secrets are plain base64 unless you configure **Encryption at Rest** (KMS) on the API server.
- Production rotation: mount as a volume, update the Secret, and the file refreshes. Env-var injection needs a rollout.

### Requests vs Limits

| | Request | Limit |
|--|---------|-------|
| Meaning | Guaranteed minimum | Hard maximum |
| Used by | Scheduler (node placement) | Kernel via cgroups |
| CPU overflow | Fine - you burst | Throttled (app slows down) |
| Memory overflow | Fine | **OOMKilled** (process killed, exit code 137) |

- Units: CPU in millicores (`100m` = 0.1 core, `1` = 1 core); memory in bytes or `Ki/Mi/Gi` (binary) vs `K/M/G` (decimal). `128Mi` is a mebibyte.
- Limits must be >= requests, otherwise the API server rejects the Pod.
- Node pressure (kubelet eviction) kills Pods by QoS class, not by the OOMKiller.

### QoS classes

| QoS | Condition | Node-pressure priority |
|-----|-----------|------------------------|
| Guaranteed | request == limit for CPU and memory | Last to be evicted |
| Burstable | has a request, but limit > request (or limit unset) | Middle |
| BestEffort | no requests, no limits at all | First to be evicted |

Check with `kubectl get pod <name> -o jsonpath='{.status.qosClass}'`.

### LimitRange and ResourceQuota

- **LimitRange** acts per container in a namespace: enforces `max`/`min`, and fills in `default` (limits) and `defaultRequest` (requests) when a Pod omits them. Violations are rejected at admission.
- **ResourceQuota** caps the namespace total (`requests.cpu`, `limits.memory`, `pods`, `persistentvolumeclaims`, and more). New work over the hard cap is rejected.
- **PriorityClass** sets scheduling priority with an optional `globalDefault`; higher-priority Pods can preempt lower-priority ones when the cluster is full.

## 3. Key Commands

```bash
kubectl create configmap app-config --from-literal=APP_MODE=prod
kubectl create configmap app-config --from-file=config.json=config.json
kubectl create secret generic db-secret --from-literal=password=hunter2
echo -n "hunter2" | base64                          # encode for secret data
kubectl get configmaps,secrets
kubectl get secret db-secret -o jsonpath='{.data.password}' | base64 -d
kubectl get pod <name> -o yaml | grep -A 6 resources
kubectl get pod <name> -o jsonpath='{.status.qosClass}'
kubectl top pod <name>                              # needs Metrics Server
kubectl get limitrange,resourcequota -A
kubectl describe resourcequota <name>               # shows Used vs Hard
kubectl describe node <node> | grep -A 8 "Allocated resources"
```

## 4. YAML Patterns

### ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_MODE: prod
  RETRIES: "3"
  config.json: |
    {"feature": "on"}
```

- `data`: plain-text key/value pairs. Numbers and booleans must be quoted strings (`"3"`), because values are always strings.
- `config.json:` with a `|` block: stores an entire file as a value; mounted, it becomes a file named `config.json`.
- `binaryData`: same shape but base64-encoded values for binary content.

### Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
stringData:
  user: admin
  password: hunter2
```

- `stringData`: write plain text; the API server base64-encodes it when stored. Read back via `kubectl get secret db-secret -o yaml` and you will see the values under `data`, encoded.
- `type: Opaque`: default type for arbitrary pairs. Use `kubernetes.io/tls` or `kubernetes.io/dockerconfigjson` for certs and registry login.

### Pod consuming config and resources

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: config-app
spec:
  containers:
  - name: app
    image: busybox:latest
    env:
    - name: APP_MODE
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: APP_MODE
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: password
    envFrom:
    - configMapRef:
        name: app-config
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        memory: 256Mi
    volumeMounts:
    - name: config-volume
      mountPath: /etc/app-config
  volumes:
  - name: config-volume
    configMap:
      name: app-config
```

- `env[].valueFrom.configMapKeyRef` / `.secretKeyRef`: inject one specific key as one environment variable. The referenced ConfigMap/Secret (and key) must exist, or the container fails with `CreateContainerConfigError`. Add `optional: true` to ignore a missing key.
- `envFrom.configMapRef`: dumps every key as an env var. Risk: key names that are not valid env-var names are skipped silently.
- `resources.requests.cpu: 100m`: scheduler guarantees at least 0.1 core free on the node.
- `resources.limits.memory: 256Mi`: kernel enforces a hard 256Mi cgroup cap; over it means OOMKilled. With a request of 128Mi and a limit of 256Mi (memory), this Pod is Burstable.
- No CPU limit: the app can burst past 100m; useful for latency-sensitive services.
- `volumes[].configMap` + `volumeMounts`: exposes each data key as a file at the mount path. This combo updates after ConfigMap edits.

### LimitRange

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
spec:
  limits:
  - max:
      cpu: "2"
      memory: 2Gi
    default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
```

- `max`/`min`: the allowed range per container. A Pod asking for more than `max` is rejected at admission.
- `default`: limits injected when the Pod declares none.
- `defaultRequest`: requests injected when the Pod declares none.
- `type: Container`: applies to containers; `Pod` limits the whole-Pod aggregate.

### ResourceQuota

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: quota
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "6"
    limits.memory: 12Gi
    pods: "10"
    persistentvolumeclaims: "5"
```

- `spec.hard`: the namespace ceiling. Any request that would push a dimension over its hard value is rejected (admission denies it with an error, not silently).
- Track usage with `kubectl describe resourcequota quota` (shows `Used` vs `Hard`).

## 5. How It Works Together

**Config reaching the Pod:** you apply a ConfigMap/Secret (stored in etcd, Secrets base64; encrypted only if configured), then a Pod that references them via `valueFrom`/`envFrom`/volume. The kubelet on the scheduled node fetches the referenced object before starting the container and injects the values as env vars (frozen at creation) or tmpfs files (refreshing). A missing key stops the start with `CreateContainerConfigError`.

**Requests scheduling, limits enforcing:**

1. The scheduler sums each node's used `requests`; a new Pod fits only if its request is within the node's allocatable capacity.
2. Once placed, the kubelet writes cgroup settings from `limits` (`cpu.cfs_quota_us`, `memory.limit_in_bytes`).
3. CPU over the limit -> the kernel throttles (less CPU time). Memory over the limit -> the kernel OOM-kills the process (exit 137) and it restarts, often CrashLoopBackOff.
4. If the whole node runs out of memory, the kubelet evicts Pods by QoS: BestEffort first, then Burstable, then Guaranteed.

```
[ ConfigMap ] [ Secret ] --> [ Pod spec ] --requests--> [ Scheduler ] picks node
                                     \--limits--> [ Kubelet -> cgroups ]
[ Pod ] env vars frozen; mounted files refresh; limit = OOMKill or throttle
```

## 6. Common Mistakes and Gotchas

| Mistake | Why | Fix |
|---------|-----|-----|
| Assuming Secrets are secure | base64 is not encryption | Enable Encryption at Rest (KMS); restrict RBAC; use External Secrets/Sealed Secrets |
| Committing plain-text credentials to Git | Convenience | `kubectl create secret` or a secrets manager; `stringData` still lands in etcd encoded |
| Editing a ConfigMap and expecting env vars to change | Env vars are frozen at container creation | Restart the Pod / rollout, or mount as a volume |
| `subPath` mounts not updating | subPath breaks the kubelet config refresh | Avoid `subPath` for config you rotate, or accept a restart |
| Env vars with `envFrom` silently missing | Invalid key names are skipped | Use explicit `env[].valueFrom` for critical keys |
| Limit < request | Invalid spec | Always keep limits >= requests |
| Setting a tight CPU limit on latency-sensitive APIs | CFS throttling adds artificial latency | Set CPU requests, leave CPU limits unset |
| No memory limits | A leak can kill the whole node | Always set memory requests and limits |
| New Pod rejected right after adding a quota | Hard cap already reached | `kubectl describe resourcequota` and raise or prune |
| Not setting any requests/limits | Pod becomes BestEffort and dies first | Give every container at least requests; Guaranteed for critical apps |

## 7. Quick Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Pod stuck `CreateContainerConfigError` | Missing ConfigMap/Secret object or missing key (or wrong namespace) | `kubectl describe pod` -> Events; `kubectl get configmap/secret <name> -o yaml` and confirm the key |
| Pod starts but env var is empty | Key exists with empty value, or `envFrom` skipped the name | `kubectl get secret <name> -o jsonpath='{.data.<key>}' \| base64 -d`; use explicit refs |
| Container `OOMKilled`, exit code 137 | Container exceeded its memory limit (its own cgroup) | `kubectl describe pod` -> Last State; raise limit or fix the leak; not the same as node eviction |
| Pod `Evicted` | Node under memory pressure; kubelet evicted by QoS order | `kubectl describe node` -> Conditions; reduce requests or scale cluster |
| Random latency spikes at low CPU | CPU limit causing CFS throttling | Remove/raise the CPU limit; keep CPU requests |
| Apply fails with "exceeded quota" | Namespace ResourceQuota hard cap hit | `kubectl describe resourcequota`; reduce requests or delete other Pods |
| Config change not seen in the container | Env injection is immutable | Restart the Pod; check if a volume mount needs the ~1 minute sync |

## 8. 30-Second Recap

- ConfigMap = plain config; Secret = base64-encoded sensitive data (NOT a security boundary - enable Encryption at Rest).
- Inject via `env`/`envFrom` (frozen at creation, restart to change) or volumes (refresh in ~1 minute; `subPath` does not).
- Requests are promises to the scheduler; Limits are ceilings enforced by the kernel.
- Exceed CPU limit = throttled; exceed memory limit = OOMKilled (exit code 137).
- QoS: Guaranteed (req == limit) survives longest; BestEffort (no req/limit) dies first; Burstable is in the middle.
- LimitRange fills per-container defaults; ResourceQuota caps the namespace; PriorityClass orders scheduling/preemption.
- Missing key = `CreateContainerConfigError`; over limit = `OOMKilled`; node pressure = `Evicted`.

## Related Lessons

- [Lesson 20 - ConfigMaps and Secrets](../docs/06-configuration/lesson-20-configmaps-and-secrets.md)
- [Lesson 21 - Resource Management and the OOMKiller (Requests vs Limits)](../docs/06-configuration/lesson-21-resource-requests-limits-and-quotas.md)

## Related Material

- [Configuration Cheat Sheet](../cheatsheets/configuration-cheatsheet.md)
- [Interview - Configuration](../interview/configuration.md)

[Back to Revision Index](README.md)
