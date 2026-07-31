# Lesson Template

Use this template for every lesson in the repository. Copy this file into the target module folder with the naming convention `lesson-NN-slug.md` and fill in each section. Do not remove sections and do not change the section order.

## Front Matter

```yaml
---
title: Lesson NN - Lesson Title
module: NN Module Name
lesson: NN
status: Draft
tags: [kubernetes, topic]
---
```

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

- Objective one
- Objective two
- Objective three

## Prerequisites

List the lessons and skills required before starting this lesson.

## Real-world Motivation

Explain why this topic matters in real production environments. Anchor the lesson in a realistic scenario.

## Core Concepts

Explain the fundamental concepts with clear, plain language.

## Architecture

Explain how the components fit together and interact.

## ASCII Diagrams

```text
+------------------+       +------------------+
|   Component A    | <---> |   Component B    |
+------------------+       +------------------+
```

## Hands-on

Step-by-step practical exercise. Reference the relevant lab file and expected output.

## Commands

```bash
# Every command must be copy-paste runnable
kubectl get pods
```

## YAML Explanation

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example
```

Explain each field and why it matters.

## Production Notes

- Production-specific considerations
- What changes when moving from learning to production

## Best Practices

- Best practice one
- Best practice two
- Best practice three

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Mistake one | Reason | Solution |

## Troubleshooting

Common failure modes and how to diagnose them.

## Interview Questions

Questions commonly asked in Kubernetes interviews, with concise answers.

## Scenario Questions

Realistic scenarios with the expected approach or answer.

## Quiz

1. Question one
   - Answer choice A
   - Answer choice B
   - Answer choice C

## Revision

A condensed summary suitable for fast review before an interview or exam.

## Cheat Sheet

The essential commands and YAML snippets for this lesson.

## References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- Relevant official documentation links

## Related Lessons

- Link to related lessons in other modules

## Coming Next

A short note about what the next lesson covers.
