# Manifests

Ready-to-use Kubernetes YAML manifests referenced by the lessons and labs.

## Purpose

Keep every manifest that is explained in a lesson here so it can be reused, referenced, and verified. Manifests in this directory are the source of truth for the documentation.

## Conventions

- File naming: `kebab-case-name.yaml`
- Organize by module and lesson: `NN-lesson-slug/`
- Every manifest is annotated with the lesson and module it belongs to
- Manifests are validated against the Kubernetes version used in the lessons
- Secrets and credentials are never committed

## Layout

```text
manifests/
  README.md
  01-fundamentals/
  03-workloads/
  04-networking/
  05-storage/
  06-configuration/
  07-security/
```

[Back to Repository Home](../README.md)
