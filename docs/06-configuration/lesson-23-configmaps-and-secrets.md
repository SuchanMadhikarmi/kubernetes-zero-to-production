---
title: Lesson 23 - ConfigMaps and Secrets
module: 06 Configuration
lesson: 23
status: Complete
tags: [kubernetes, configmaps, secrets, configuration, environment-variables, volumes, twelve-factor]
---

# Lesson 23 - ConfigMaps and Secrets

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

- Explain the Twelve-Factor App methodology regarding configuration.
- Describe how ConfigMaps store non-sensitive data.
- Describe how Secrets store sensitive data.
- Inject configuration into Pods using Environment Variables and Volumes.
- Debug a Pod that fails to start due to a missing configuration key.

## Prerequisites

- Completion of Lessons 1 through 4 (containers, Pods, Services, Ingress).
- A running Kubernetes cluster (see [Lesson 01](../01-fundamentals/lesson-01-anatomy-of-a-container.md) for kind setup instructions).
- kubectl installed and configured.

## Real-world Motivation

### The "Rebuild for Every Environment" Problem

Imagine you build a Docker image for your Node.js API. You hardcode the database URL: `mongodb://localhost:27017`. You run it locally, and it works. You push the image to your Dev environment. It fails, because the Dev database is at `mongodb://dev-db:27017`. You change the code, rebuild the image, and push it to Staging. It fails again. You are rebuilding the image for every environment, which is slow and error-prone.

### The Security Risk

To fix the above, an engineer puts the production database password directly inside the Docker image. Now, anyone who can pull that Docker image can extract the production database password.

### Why This Exists

Kubernetes follows the Twelve-Factor App methodology, which states: Config should be strictly separated from code. ConfigMaps and Secrets exist to allow the exact same Docker image to be promoted from Dev to Staging to Production without any changes. Only the configuration attached to the Pod at runtime changes.

### Real Company Examples

**Shopify:** Shopify uses a tool called "SecretSyncer". Developers put their secrets in a central HashiCorp Vault. A controller watches Vault and automatically creates Kubernetes Secrets in the correct namespaces. The developers just mount those Secrets into their Pods as environment variables. They never touch base64 encoding directly.

## Core Concepts

### Explain Like I'm 12

Imagine you bought a robot. The robot comes with a hardwired program (the Container Image). But you want the robot to speak English today and Spanish tomorrow. Instead of buying a whole new robot, you just insert a different SD card (ConfigMap) into its slot. If the SD card has secret information (like your house alarm code), you put it in a locked box first (Secret).

### Explain Like I'm a Junior Engineer

A ConfigMap and a Secret are just dictionaries in Kubernetes. You write a YAML file with key-value pairs. When you create a Pod, you tell Kubernetes, "Take the value of the key `DB_HOST` from the ConfigMap named `app-config`, and set it as the environment variable `DB_HOST` inside the container." The application just reads `DB_HOST` like it normally would. It has no idea Kubernetes provided it.

### Explain Technically

- **ConfigMap:** Stores plain text data in etcd.
- **Secret:** Stores base64-encoded data in etcd.
- When the kubelet receives the Pod spec, it sees the `env.valueFrom` field. It makes a call to the API Server to fetch the referenced ConfigMap or Secret.
- The kubelet passes these values to the Container Runtime Interface (CRI) via the OCI (Open Container Initiative) runtime spec. The runtime configures the container's namespace to expose these as environment variables or mounted tmpfs volumes.

### How Kubernetes Implements It Internally

For environment variables, the values are injected at container creation time. They are immutable once the container starts. If you update a ConfigMap, the running container will NOT see the change until the Pod is restarted. (If mounted as a Volume, it does update, but it takes a minute).

### Why Kubernetes Was Designed That Way

By separating configuration from the image, Kubernetes allows the same image to run in any environment. This is a core principle of cloud-native architecture. It also means you can rotate secrets without rebuilding or redeploying your application.

## Architecture

```
[ etcd ] (Stores ConfigMaps and Secrets)
   |
   v
[ API Server ]
   |
   v (Kubelet requests config before starting container)
[ Kubelet ] -> [ Container Runtime (containerd) ]
                      |
                      v
              [ Container Process ]
                - ENV vars populated
                - Files mounted
```

### Terminology

| Term | Definition |
|------|------------|
| ConfigMap | An API object used to store non-confidential data in key-value pairs. |
| Secret | An API object used to store sensitive data, encoded in base64. |
| env | A field in the Pod spec used to define environment variables for a container. |
| valueFrom | A field used to reference a value from a ConfigMap or Secret instead of hardcoding it. |
| Twelve-Factor App | A methodology for building SaaS apps that states config should be separated from code. |
| Encryption at Rest | encrypting Secrets in etcd so they are not readable as plain base64. |

### How It Works Internally

1. You create a ConfigMap with `LOG_LEVEL=debug`.
2. You create a Pod YAML referencing that ConfigMap.
3. API Server saves the Pod to etcd. The Scheduler assigns it to a Node.
4. The kubelet on that Node sees the Pod.
5. Before starting the container, kubelet calls the API Server: "Give me the `app-config` ConfigMap."
6. kubelet passes `LOG_LEVEL=debug` to containerd.
7. containerd starts the container process, injecting `LOG_LEVEL=debug` into its environment.
8. If a referenced key does not exist, kubelet refuses to start the container.

### Step-by-Step Workflow

1. Developer creates a ConfigMap YAML storing app settings.
2. Developer creates a Secret YAML storing a password (base64 encoded).
3. Developer creates a Pod/Deployment YAML that references both.
4. `kubectl apply` sends these to the API Server.
5. kubelet on the target node fetches the Config and Secret.
6. kubelet starts the container with the variables injected.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | ConfigMap/Secret is created and stored in etcd. |
| Injection | A Pod starts and reads the values. |
| Update (Env Vars) | If the ConfigMap is updated, existing Pods do NOT see the change. A Pod restart is required. |
| Update (Volumes) | If mounted as a Volume, the kubelet updates the files in the container, but it takes ~60-90 seconds to propagate. |
| Deletion | If a ConfigMap is deleted, Pods that reference it as an Environment Variable will crash on restart (`CreateContainerConfigError`). |

### ConfigMap vs Secret

| Feature | ConfigMap | Secret |
|---------|-----------|--------|
| Data Type | Plain text | Base64 encoded |
| Use Case | Log levels, URLs, flags | Passwords, Tokens, Certs |
| Security | Not secure | Slightly better (can be encrypted at rest) |
| Size Limit | 1MB | 1MB |

### Common Myths

| Myth | Fact |
|------|------|
| "Kubernetes Secrets are encrypted." | False. By default, they are only base64 encoded. base64 is an encoding scheme, not encryption. You must explicitly configure Encryption at Rest to encrypt them in etcd. |
| "Environment variables update in real-time when a ConfigMap is updated." | False. Environment variables are injected at container creation time and are immutable. You must restart the Pod to see changes. |
| "ConfigMaps can only store small strings." | False. ConfigMaps can store entire configuration files (up to 1MB). |

## ASCII Diagrams

Mental Model: The ConfigMap is a dictionary. The Pod says, "I need the definition for the word 'LOG_LEVEL' from the 'App-Config' dictionary." The kubelet looks it up and hands it to the container.

```
[ ConfigMap: app-config ]    [ Secret: db-secret ]
  LOG_LEVEL: "debug"           DB_PASS: c3VwZXJzZWNyZXQ=
      |                              |
      v                              v
+---------------------------------------------------+
|  Pod Spec (References them)                       |
|  env:                                             |
|    - name: LOG_LEVEL                              |
|      valueFrom: configMapKeyRef: name: app-config |
|    - name: DB_PASSWORD                            |
|      valueFrom: secretKeyRef: name: db-secret     |
+---------------------------------------------------+
              |
              v
+---------------------------------------------------+
|  Container (App reads Env Vars)                   |
|  $LOG_LEVEL = "debug"                             |
|  $DB_PASSWORD = "supersecret" (decoded by K8s)    |
+---------------------------------------------------+
```

### Volume Mount Flow

```
[ ConfigMap: nginx-config ]
  default.conf: "server { listen 80; ... }"
      |
      v
[ Pod Spec ]
  volumes:
  - name: nginx-config
    configMap:
      name: nginx-config
  containers:
  - name: nginx
    volumeMounts:
    - name: nginx-config
      mountPath: /etc/nginx/conf.d/
      |
      v
[ Container Filesystem ]
  /etc/nginx/conf.d/default.conf -> "server { listen 80; ... }"
```

## Hands-on

### Objective

Create a ConfigMap and a Secret. Inject them into a Pod as Environment Variables. Then, intentionally break the Pod by referencing a missing key.

### Step 1: Create the Configuration

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  LOG_LEVEL: "info"
  MAX_CONNECTIONS: "100"
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
data:
  DB_PASSWORD: c3VwZXJzZWNyZXQ=
EOF
```

### Step 2: Create the Pod

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: config-app
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "echo LOG_LEVEL=\$LOG_LEVEL && echo DB_PASSWORD=\$DB_PASSWORD && sleep 3600"]
    env:
    - name: LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: LOG_LEVEL
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: app-secret
          key: DB_PASSWORD
  restartPolicy: Never
EOF
```

### Step 3: Verify It Worked

```bash
kubectl logs config-app
```

Expected:

```
LOG_LEVEL=info
DB_PASSWORD=supersecret
```

### Step 4: Test Volume Mount

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    server {
      listen 80;
      server_name localhost;
      location / {
        return 200 "Hello from custom Nginx config!";
      }
    }
---
apiVersion: v1
kind: Pod
metadata:
  name: nginx-custom
spec:
  containers:
  - name: nginx
    image: nginx:1.25-alpine
    ports:
    - containerPort: 80
    volumeMounts:
    - name: nginx-config
      mountPath: /etc/nginx/conf.d/
  volumes:
  - name: nginx-config
    configMap:
      name: nginx-config
EOF
```

```bash
kubectl exec nginx-custom -- curl -s localhost
```

Expected: "Hello from custom Nginx config!"

### Step 5: Debug a Missing Key

```bash
kubectl delete pod config-app

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: config-app-broken
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "echo \$LOGGING_LEVEL && sleep 3600"]
    env:
    - name: LOGGING_LEVEL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: LOGGING_LEVEL
  restartPolicy: Never
EOF
```

```bash
kubectl get pod config-app-broken
kubectl describe pod config-app-broken
```

The Pod fails with `CreateContainerConfigError` because the key `LOGGING_LEVEL` doesn't exist in the ConfigMap.

### Step 6: Cleanup

```bash
kubectl delete pod config-app nginx-custom config-app-broken
kubectl delete configmap app-config nginx-config
kubectl delete secret app-secret
```

## Commands

```bash
# Create ConfigMap imperatively
kubectl create configmap app-config --from-literal=LOG_LEVEL=info --from-literal=MAX_CONNECTIONS=100

# Create Secret imperatively
kubectl create secret generic app-secret --from-literal=DB_PASSWORD=supersecret

# List ConfigMaps
kubectl get configmaps

# List Secrets
kubectl get secrets

# Decode a Secret value
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d

# Describe a ConfigMap
kubectl describe configmap app-config

# Describe a Secret
kubectl describe secret app-secret

# Check Pod logs
kubectl logs config-app

# Debug a broken Pod
kubectl describe pod config-app-broken
```

## YAML Explanation

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  LOG_LEVEL: "info"
  MAX_CONNECTIONS: "100"
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
data:
  DB_PASSWORD: c3VwZXJzZWNyZXQ=
```

### Field-by-Field Explanation

- `kind: ConfigMap`: Stores non-sensitive configuration data.
- `kind: Secret`: Stores sensitive data (base64 encoded).
- `type: Opaque`: The default Secret type for arbitrary key-value pairs.
- `data`: Stores the key-value pairs. In Secrets, values must be base64 encoded.

### Pod Reference Fields

```yaml
env:
- name: LOG_LEVEL
  valueFrom:
    configMapKeyRef:
      name: app-config
      key: LOG_LEVEL
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: app-secret
      key: DB_PASSWORD
```

- `valueFrom.configMapKeyRef`: Points to the specific key in the ConfigMap.
- `secretKeyRef`: Points to the specific key in the Secret.

## Production Notes

- **Use Secrets for Sensitive Data.** Never put passwords, API keys, or certificates in a ConfigMap.
- **Enable Encryption at Rest.** By default, Secrets are just base64 encoded in etcd. Anyone with etcd access can read them. In production, you MUST configure `EncryptionConfiguration` on the API Server to encrypt secrets at rest using a KMS (Key Management Service).
- **Use External Secret Stores.** For enterprise production, use tools like External Secrets Operator to sync secrets from AWS Secrets Manager or HashiCorp Vault into Kubernetes Secrets, rather than storing base64 strings in Git.
- **Immutable ConfigMaps.** If your app doesn't support hot-reloading config, set `immutable: true` on your ConfigMaps. This improves cluster performance because the API Server stops watching them for changes.
- **Restrict RBAC for Secrets.** Only allow specific ServiceAccounts to read Secrets. Use least-privilege access.

### When to Use / When NOT to Use

**Use ConfigMaps/Secrets when:**

- You need to change application behavior without rebuilding Docker images.
- You have multiple environments (Dev/Staging/Prod) using the same image.

**Do NOT use ConfigMaps when:**

- The file is over 1MB. Use a Persistent Volume or an Object Store (S3) instead.
- You need strict access control and rotation. Use HashiCorp Vault or AWS KMS.

### Performance and Security Considerations

**Performance:** Injecting config as Environment Variables has zero runtime performance overhead. Mounting them as Volumes uses tmpfs (RAM-backed filesystem), which consumes a tiny amount of Pod memory.

**Security:** Anyone with `kubectl get secrets` permissions can decode your passwords. You MUST restrict RBAC permissions for Secrets. In production, enable Encryption at Rest so secrets are encrypted in etcd.

## Best Practices

- Use ConfigMaps for non-sensitive data, Secrets for sensitive data.
- Enable Encryption at Rest for Secrets in production.
- Use External Secret Stores (Vault, AWS Secrets Manager) for enterprise environments.
- Set `immutable: true` on ConfigMaps if your app doesn't support hot-reloading.
- Restrict RBAC access to Secrets.
- Never commit Secrets to Git in plain text.
- Use `kubectl create secret` imperatively for quick creation, but prefer YAML for GitOps.
- Validate that all referenced ConfigMap/Secret keys exist before deploying.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Leaving `optional: false` (default) on critical config | Pod refuses to start if key is missing | Set `optional: true` for non-critical config |
| Assuming Secrets are secure by default | Base64 is encoding, not encryption | Enable Encryption at Rest |
| Writing logs to files | Not understanding cloud-native logging | Print to stdout/stderr |
| Not updating Pods after ConfigMap change | Env vars are immutable | Restart Pods or use Volume mounts |
| Committing Secrets to Git | Convenience | Use External Secrets Operator |

## Troubleshooting

**Symptom: Pod stuck in `CreateContainerConfigError`**

Cause: A referenced ConfigMap or Secret key doesn't exist.

```bash
kubectl describe pod <pod-name> | grep -A 5 Events
```

Fix: Verify the ConfigMap/Secret has the correct key. Check with `kubectl get configmap <name> -o yaml`.

**Symptom: Pod starts but env var is empty**

Cause: The ConfigMap/Secret key exists but has an empty value.

```bash
kubectl get configmap <name> -o yaml
kubectl get secret <name> -o jsonpath='{.data.<key>}' | base64 -d
```

Fix: Ensure the key has a non-empty value in the ConfigMap or Secret.

**Symptom: Updated ConfigMap but Pod still shows old value**

Cause: Environment variables are injected at container creation time and are immutable.

Fix: Restart the Pod to pick up the new values. Or use Volume mounts for dynamic updates.

## Interview Questions

**Q: What is the difference between a ConfigMap and a Secret?**

A: A ConfigMap stores plain text configuration data. A Secret stores sensitive data (like passwords) encoded in base64.

**Q: Is a Kubernetes Secret secure by default?**

A: No. It is only base64 encoded. Anyone with API access can decode it. For true security, you must enable Encryption at Rest for Secrets in the API Server configuration.

**Q: If you update a ConfigMap, does the running Pod see the change immediately?**

A: It depends on how it was injected. If it was an Environment Variable, no. The Pod must be restarted. If it was mounted as a Volume, yes, but it takes a minute for the kubelet to sync the new files.

**Q: A Pod is in `CreateContainerConfigError`. What are two likely causes?**

A: 1) The Pod references a ConfigMap or Secret that does not exist. 2) The Pod references a specific key inside a ConfigMap/Secret that does not exist.

**Q: How do you encode a value for a Secret?**

A: Use `echo -n "value" | base64`. The `-n` flag prevents a trailing newline from being encoded.

**Q: Can ConfigMaps store binary data?**

A: Yes, using the `binaryData` field instead of `data`. The values must be base64 encoded.

## Scenario Questions

**Scenario 1:** You update a ConfigMap that is mounted as a Volume in a running Pod. How long does it take for the Pod to see the change?

A: It takes approximately 60-90 seconds for the kubelet to sync the updated files. This is not instant because the kubelet has a sync period.

**Scenario 2:** You need to rotate a database password without downtime. How do you do it?

A: Update the Secret with the new password. If the Pod uses the Secret as an Environment Variable, you need to restart the Pod. If it's mounted as a Volume, the file updates automatically (with a delay). For zero-downtime, use a Rolling Update strategy on your Deployment.

**Scenario 3 (Mini Project - The Mounted Volume):**

Create a ConfigMap that contains a multi-line Nginx configuration file. Mount this ConfigMap as a Volume into an Nginx Pod at `/etc/nginx/conf.d/default.conf`. Verify that Nginx uses your custom configuration.

## Quiz

1. What is a ConfigMap used for?
   - A. Storing passwords
   - B. Storing non-sensitive configuration data
   - C. Storing Docker images
   - D. Storing logs

2. What encoding do Secrets use by default?
   - A. AES-256
   - B. base64
   - C. UTF-8
   - D. SHA-256

3. What happens if a Pod references a missing ConfigMap key?
   - A. Pod starts with empty value
   - B. Pod fails with CreateContainerConfigError
   - C. Pod uses a default value
   - D. Pod restarts automatically

4. Do environment variables update when a ConfigMap is updated?
   - A. Yes, immediately
   - B. No, Pod must be restarted
   - C. Yes, after 60 seconds
   - D. Only if using Volume mounts

5. How do you enable true encryption for Secrets?
   - A. Use base64 encoding
   - B. Enable Encryption at Rest on the API Server
   - C. Use ConfigMaps instead
   - D. Use environment variables

Answers: 1-B, 2-B, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- ConfigMaps store non-sensitive plain text data.
- Secrets store sensitive base64-encoded data.
- They can be injected into Pods as Environment Variables or mounted as Files (Volumes).
- If a Pod references a missing key, it fails with `CreateContainerConfigError`.
- Kubernetes separates code from config to allow the same image to run anywhere.

Memory trick:

- ConfigMap: The lunch menu.
- Secret: The locked recipe box.
- `CreateContainerConfigError`: The waiter refusing to serve the table because the kitchen is out of the required ingredient.

Key facts:

- ConfigMap = Plain text config.
- Secret = Base64 config.
- Missing key = `CreateContainerConfigError`.
- Env Vars don't update dynamically. Volumes do.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl create configmap <name> --from-literal=key=val` | Imperatively create a ConfigMap |
| `kubectl create secret generic <name> --from-literal=key=val` | Imperatively create a Secret |
| `echo -n "val" \| base64` | Encode a string for a Secret |
| `kubectl get secrets` | Lists Secrets |
| `kubectl get secret <name> -o jsonpath='{.data.<key>}' \| base64 -d` | Decode a Secret value |
| `kubectl describe pod <name>` | Debug Pod startup issues |

## References

- [Kubernetes Documentation: ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Kubernetes Documentation: Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Kubernetes Documentation: Twelve-Factor App](https://12factor.net/config)
- [Kubernetes Documentation: Encryption at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- [Kubernetes Documentation: External Secrets Operator](https://external-secrets.io/)

## Related Lessons

- [Lesson 01 - The Anatomy of a Container](../01-fundamentals/lesson-01-anatomy-of-a-container.md) - containers, namespaces, and cgroups.
- [Lesson 10 - Pods, ReplicaSets, and Deployments](../03-workloads/lesson-10-pods-replicasets-and-deployments.md) - how Pods work.
- [Lesson 24 - Secrets Deep Dive](lesson-24-secrets.md) - advanced Secret management.
- [Lesson 25 - Resource Requests, Limits, and Quotas](lesson-25-resource-requests-limits-and-quotas.md) - resource management.
- [Module 07 - Security](../07-security/README.md) - RBAC and Pod Security Standards.

## Coming Next

Now that you understand how to inject configuration into Pods, the next lesson dives deeper into Secrets, covering advanced use cases like TLS certificates, docker registry credentials, and external secret stores.
