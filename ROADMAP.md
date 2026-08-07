# ROADMAP

## Kubernetes Zero to Production

This document defines the delivery plan, phases, and milestones for the repository. It is a living document and is updated as the repository evolves.

## Table of Contents

- [Vision](#vision)
- [Phases](#phases)
- [Milestones](#milestones)
- [Phase Details](#phase-details)
- [Definition of Done](#definition-of-done)
- [Status Legend](#status-legend)

---

## Vision

Build a production-quality, beginner-friendly Kubernetes learning repository of 46 lessons that covers the full journey from "what is a container" to running and operating Kubernetes in production.

## Phases

| Phase | Name | Goal | Status |
|-------|------|------|--------|
| 1 | Repository Structure | Complete folder structure, navigation, and project foundations | Complete |
| 2 | Core Curriculum | Publish all 46 lessons across 14 modules | Complete |
| 3 | Labs and Manifests | Accompany every hands-on lesson with labs and manifests | Complete |
| 4 | Interview and Revision | Build interview, revision, and cheat sheet material | Complete |
| 5 | Community Polish | Refine navigation, add diagrams, and prepare for public contribution | Complete |

## Milestones

| Milestone | Deliverable | Phase | Status |
|-----------|-------------|-------|--------|
| M1 | Repository scaffolded: README, ROADMAP, CONTRIBUTING, LICENSE, folder map | 1 | Complete |
| M2 | Documentation hub and 14 module indexes published | 1 | Complete |
| M3 | Modules 01-03 complete (Fundamentals, Architecture, Workloads) | 2 | Complete |
| M4 | Modules 04-06 complete (Networking, Storage, Configuration) | 2 | Complete |
| M5 | Modules 07-08 complete (Security, Observability) | 2 | Complete |
| M6 | Modules 09-11 complete (Packaging, GitOps, Operators) | 2 | Complete |
| M7 | Modules 12-14 complete (Production, Troubleshooting, Certifications) | 2 | Complete |
| M8 | Labs and manifests published for all hands-on lessons | 3 | Complete |
| M9 | Interview guides, revision notes, and cheat sheets published | 4 | Complete |
| M10 | Full navigation review, link audit, and release-ready polish | 5 | Complete |

## Phase Details

### Phase 1: Repository Structure

- Create root documentation: README, ROADMAP, CONTRIBUTING, LICENSE
- Create the 14-module curriculum structure under `docs/`
- Create supporting directories: labs, manifests, assets, diagrams, interview, revision, cheatsheets, scripts
- Publish the documentation hub and per-module indexes
- Define the lesson template and contribution standards

### Phase 2: Core Curriculum

- Deliver all 46 lessons following the standardized lesson template
- Every lesson must include the full section list defined in the template
- Update the progress tracker and module indexes as lessons are published
- Review each lesson for correctness, consistency, and production readiness

### Phase 3: Labs and Manifests

- Provide a hands-on lab for every lesson with hands-on content
- Store manifests under `manifests/` in a predictable, numbered layout
- Every lab must list exact commands and expected output
- Labs must be reproducible on kind, minikube, k3s, or managed clusters

### Phase 4: Interview and Revision

- Publish topic-wise interview questions mapped to each module
- Create condensed revision notes for fast exam and interview review
- Publish cheat sheets for kubectl, YAML patterns, and troubleshooting
- Add scenario-based questions and answers

### Phase 5: Community Polish

- Add diagrams for every architecture lesson
- Audit all internal links across the repository
- Standardize formatting, tables, and callouts
- Prepare release notes and contribution onboarding material

## Definition of Done

A phase or milestone is complete when:

- All planned files exist and follow the naming conventions
- Markdown renders correctly and internal links resolve
- No duplicate content exists
- Progress tracker and indexes are updated
- A review pass has been completed for consistency and correctness

## Status Legend

- `Planned` - not started
- `In Progress` - actively being worked on
- `Complete` - finished and verified
