---
title: Revision - Configuration
module: 06 Configuration
status: Complete
tags: [revision, configuration, configmap, secret, resources, quota]
---

# Revision - Configuration

## Core Ideas

- **ConfigMap**: non-secret key/value config. **Secret**: sensitive data (base64 in `data`, plain in `stringData`).
- Both are injected as env vars or mounted as volumes.
- **Resource requests/limits** control scheduling and limits. Requests reserve; limits enforce (memory limits can OOM-kill).
- **ResourceQuota** caps a namespace; **LimitRange** sets per-container defaults/mins/maxs.
- **QoS classes**: Guaranteed (req == limit), Burstable, BestEffort.

## Key Points

- ConfigMap/Secret updates propagate to mounted volumes; not to already-injected env vars.
- Secrets at rest in etcd are base64, not encrypted (enable encryption-provider-config).
- HPA needs `resources.requests.cpu`/memory to compute utilization.
- Eviction order under pressure: BestEffort -> Burstable -> Guaranteed.

## Examples

```yaml
env:
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef: {name: db-secret, key: password}
envFrom:
- configMapRef: {name: app-config}
volumes:
- name: cfg
  configMap: {name: app-config}
```

```yaml
resources:
  requests: {cpu: 100m, memory: 128Mi}
  limits: {cpu: 500m, memory: 256Mi}
```

## Commands

```bash
kubectl create configmap app-config --from-literal=key=val
kubectl create secret generic db-secret --from-literal=user=admin
kubectl get configmaps,secrets -A
kubectl describe resourcequota <name>
```

## Related Lessons

- [Lesson 23 - ConfigMaps and Secrets](../docs/06-configuration/lesson-23-configmaps-and-secrets.md)
- [Lesson 25 - Resource Requests, Limits, and Quotas](../docs/06-configuration/lesson-25-resource-requests-limits-and-quotas.md)

## Related Material

- [Configuration Cheat Sheet](../cheatsheets/configuration-cheatsheet.md)
- [Interview - Configuration](../interview/configuration.md)

[Back to Revision Index](README.md)