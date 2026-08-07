---
title: YAML Cheat Sheet
topic: yaml
status: Complete
tags: [cheatsheet, yaml, manifest, api]
---

# YAML Cheat Sheet

## Anatomy of a Kubernetes Manifest

Every resource has these core fields. `apiVersion` and `kind` are the required type; `metadata` identifies it; `spec` is the desired state.

```yaml
apiVersion: apps/v1          # group/version, defines the resource kind
kind: Deployment             # resource type
metadata:
  name: web                  # must be unique within namespace
  namespace: default         # optional; defaults to active namespace
  labels:                    # optional, used by selectors
    app: web
    tier: frontend
  annotations:               # optional, non-identifying metadata
    owner: platform-team
spec:                        # desired state (kind-specific)
  replicas: 3
```

## apiVersions by Resource

| Kind | apiVersion | Group |
|------|-----------|-------|
| Pod | `v1` | core (no group) |
| ConfigMap, Secret, Service, PersistentVolume, Namespace, Node | `v1` | core |
| ReplicaSet, Deployment, StatefulSet, DaemonSet | `apps/v1` | apps |
| Job, CronJob | `batch/v1` | batch |
| Ingress | `networking.k8s.io/v1` | networking |
| NetworkPolicy | `networking.k8s.io/v1` | networking |
| PersistentVolumeClaim | `v1` | core |
| StorageClass | `storage.k8s.io/v1` | storage |
| Role, ClusterRole, RoleBinding, ClusterRoleBinding, ServiceAccount | `rbac.authorization.k8s.io/v1` | rbac |
| HorizontalPodAutoscaler | `autoscaling/v2` | autoscaling |
| PodDisruptionBudget | `policy/v1` | policy |
| Custom Resource (CRD/tool-specific) | varies, e.g. `argoproj.io/v1alpha1` | vendor |

Verify with `kubectl api-resources` and `kubectl api-versions`.

## Labels and Selectors

```yaml
metadata:
  labels:
    app.kubernetes.io/name: nginx
    app.kubernetes.io/instance: web-1
    environment: prod
```

Selectors match pods to controllers and services. `matchLabels` (exact equality) in controllers; services and network policies use a label selector too.

```yaml
selector:
  matchLabels:
    app: nginx
    environment: prod
  # optional but powerful in Deployments/RS:
  matchExpressions:
  - key: environment
    operator: In
    values: [prod, staging]
```

A Deployment whose selector does not match the Pod template labels is rejected:

```text
The Deployment "web" is invalid: spec.selector does not match template labels.
```

Note: The Deployment selector is immutable after creation; plan the pod labels up front.

## Multi-document YAML

Separate documents with `---`. Useful to group related resources (in a single file applied together or a directory).

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_ENV: prod
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  template:
    spec:
      containers:
      - name: web
        image: nginx
---
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
```

Apply a whole directory: `kubectl apply -f ./manifests/` and `kubectl delete -f ./manifests/`.

## Controller Template Pattern

Controller resources embed the Pod template. The labels under `spec.template.metadata.labels` must match the `spec.selector`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web        # must match the selector
    spec:
      containers:
      - name: web
        image: nginx:1.25-alpine
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
```

## Pod Spec Essentials

```yaml
spec:
  containers:
  - name: app
    image: nginx
    imagePullPolicy: IfNotPresent   # Always | IfNotPresent | Never
    command: ["/bin/sh", "-c"]      # overrides Docker ENTRYPOINT
    args: ["echo hi"]               # overrides Docker CMD
    resources:
      requests: {cpu: 100m, memory: 128Mi}
      limits: {cpu: "1", memory: 512Mi}
    ports:
    - containerPort: 80
    env:
    - name: MY_VAR
      value: "hello"
    volumeMounts:
    - name: data
      mountPath: /data
    readinessProbe:
      httpGet: {path: /ready, port: 8080}
      initialDelaySeconds: 5
      periodSeconds: 10
    livenessProbe:
      tcpSocket: {port: 8080}
      periodSeconds: 15
    startupProbe:
      httpGet: {path: /healthz, port: 8080}
      failureThreshold: 30
  restartPolicy: Always              # Always | OnFailure | Never
  nodeSelector:
    disktype: ssd
  serviceAccountName: app-sa
  securityContext:
    runAsUser: 1000
    runAsNonRoot: true
  volumes:
  - name: data
    emptyDir: {}
```

## ConfigMap and Secret Referencing

```yaml
env:
- name: APP_CONFIG
  valueFrom:
    configMapKeyRef:
      name: app-config
      key: APP_ENV
envFrom:
- configMapRef:
    name: app-config
- secretRef:
    name: app-secrets
volumes:
- name: cm-vol
  configMap:
    name: app-config
- name: secret-vol
  secret:
    secretName: app-secrets
```

Secrets are base64 values in `data:` (or string values under `stringData:` in a manifest you author).

## Namespaced vs Cluster-Scoped

| Cluster-scoped | Namespaced |
|----------------|-----------|
| Node | Pod |
| Namespace | Service |
| PersistentVolume (PV) | PersistentVolumeClaim (PVC) |
| StorageClass, ResourceQuota | Deployment, ConfigMap |
| ClusterRole, ClusterRoleBinding | Role, RoleBinding |
| CustomResourceDefinition | most others |

Check with `kubectl api-resources --namespaced=true|false`.

## EnvVar / Array Yaml Gotchas

- Booleans and numbers: quote them when you want a literal string, or YAML coerce.
  ```yaml
  - name: FEATURE
    value: "true"
  - name: RETRIES
    value: "3"
  ```
- Use `|` for preserved multi-line strings and `>` for folded multiline:
  ```yaml
  script: |
    line1
    line2
  ```
- `null`, `~`, empty are treated as null. In Kubernetes maps this often removes a field on `kubectl apply`.