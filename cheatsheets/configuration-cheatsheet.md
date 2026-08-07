---
title: Configuration Cheat Sheet
topic: configuration
status: Complete
tags: [cheatsheet, configmap, secret, resource-requests, limits, quota]
---

# Configuration Cheat Sheet

## ConfigMap

ConfigMaps hold non-secret configuration as key/value pairs or files.

```bash
kubectl create configmap my-config --from-literal=key=value --from-file=file.txt --from-literal=host=db
kubectl create configmap my-config --from-env-file=env.properties
kubectl get configmaps
kubectl describe configmap my-config
kubectl get cm my-config -o yaml
kubectl delete configmap my-config
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_MODE: prod
  config.json: |
    {"retries": 3}
binaryData:
  keyfile.bin: <base64>
```

Referencing a ConfigMap:

```yaml
# As env vars
spec:
  containers:
  - name: app
    envFrom:
    - configMapRef:
        name: app-config
    env:
    - name: MODE
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: APP_MODE

# As a file volume
    volumeMounts:
    - name: cfg
      mountPath: /etc/app
  volumes:
  - name: cfg
    configMap:
      name: app-config
```

ConfigMaps are mounted as read-only. The `configMapRef` / `configMapKeyRef` name is available to pods; injection is final (changes in the ConfigMap propagate to mounted volumes, but not env vars automatically).

## Secrets

Secrets hold sensitive data. In `data:` values are base64-encoded; in `stringData:` they are plain (encoded on write).

```bash
kubectl create secret generic db-secret --from-literal=user=admin --from-literal=password=hunter2
kubectl create secret tls tls-secret --cert=cert.crt --key=key.key
kubectl create secret docker-registry regcred --docker-server=... --docker-username=... --docker-password=...
kubectl get secrets
kubectl describe secret db-secret
kubectl get secret db-secret -o jsonpath='{.data.password}' | base64 -d
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
data:
  user: YWRtaW4=          # base64 of "admin"
stringData:
  password: hunter2       # plain; newly encoded into data on apply
```

Referencing a Secret:

```yaml
env:
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: db-secret
      key: password
envFrom:
- secretRef:
    name: db-secret
volumes:
- name: secrets
  secret:
    secretName: db-secret
```

Security notes: Secret values are base64, not encrypted, at rest in etcd (unless etcd is encrypted). Use external secrets (Sealed Secrets, External Secrets Operator, Vault) in production. Keep Secrets minimal and scoped.

## Resource Requests and Limits

```yaml
spec:
  containers:
  - name: app
    resources:
      requests:
        cpu: "100m"          # 0.1 CPU; m = milli
        memory: "128Mi"      # Mi = MiB
      limits:
        cpu: "500m"
        memory: "256Mi"
```

Units:

| Resource | Unit | Meaning |
|----------|------|---------|
| CPU | `m` or integer cores | `100m` = 0.1 core, `1` = 1 core |
| Memory | `Mi`, `Gi`, `M`, `G`, `Ki` | binary (Mi/Gi) vs decimal (M/G) |

Behavior:

- `requests` are used by the scheduler for placement and by the HPA for scaling.
- `limits` on CPU throttle; limits on memory **can kill** the container (OOMKilled).
- `requests <= limits` normally enforced.

## ResourceQuota and LimitRange

ResourceQuota caps total usage in a namespace:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: quota
spec:
  hard:
    requests.cpu: 4
    requests.memory: 8Gi
    limits.cpu: 6
    limits.memory: 12Gi
    pods: "10"
    persistentvolumeclaims: "5"
    configmaps: "10"
```

LimitRange sets per-container default/min/max:

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

When a pod command is denied due to quota, review events:

```bash
kubectl get events -n <ns> --sort-by='.lastTimestamp'
kubectl describe quota
kubectl describe pods
```

## QoS Classes

| QoS | condition | 
|-----|-----------|
| `Guaranteed` | request == limit for both cpu and memory on all containers |
| `Burstable` | some requests/limits set, not requiring equal |
| `BestEffort` | no requests/limits set |

`Guaranteed` pods are least likely to be evicted first; `BestEffort` are evicted first under pressure.

## Effective commands

```bash
kubectl get configmaps,secrets -n <ns>
kubectl create secret generic app-secrets --from-literal=KEY=VAL
kubectl exec -it <pod> -- env | grep KEY
kubectl describe resourcequota quota
kubectl apply -f quota.yaml
```