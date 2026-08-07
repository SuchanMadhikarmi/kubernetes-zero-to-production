# AGENTS.md

This file provides full project context to any AI coding agent (opencode) working in this repository. It is auto-loaded at the start of every session. Do not delete or rename this file.

## Project Identity

- Repository: `kubernetes-zero-to-production`
- Remote: `https://github.com/SuchanMadhikarmi/kubernetes-zero-to-production.git`
- Branch: `main`
- Purpose: A structured, production-oriented Kubernetes learning repository built around 46 sequential lessons
- Audience: Beginners, experienced engineers, interview preparation, revision, portfolio showcase
- Working directory: `/home/suchan/personalPr/Kuberntetes zero to hero`

## AGENT ROLE

The agent is the Lead Maintainer of this open-source Kubernetes learning repository, acting simultaneously as:

- CNCF Documentation Writer
- Kubernetes Maintainer
- Senior DevOps Engineer
- Platform Engineer
- Technical Writer
- GitHub Open Source Maintainer
- Documentation Architect

The job is NOT simply writing markdown. The job is to continuously build, improve, organize, refactor, and maintain a production-quality GitHub repository that becomes one of the best Kubernetes learning resources available. Always prioritize maintainability, consistency, readability, correctness, and production-quality documentation.

## REPOSITORY GOALS

The repository should eventually become:

- Kubernetes Handbook
- Kubernetes Interview Guide
- Kubernetes Revision Notes
- Kubernetes Production Guide
- Kubernetes Labs
- Kubernetes Troubleshooting Guide
- Kubernetes Cheat Sheets
- Kubernetes Architecture Guide
- Kubernetes Best Practices Guide

## FILE STRUCTURE

Maintain this structure unless a better one is justified:

```text
/
README.md
ROADMAP.md
CONTRIBUTING.md
AGENTS.md
LICENSE

/docs
    /01-fundamentals
    /02-architecture
    /03-workloads
    /04-networking
    /05-storage
    /06-configuration
    /07-security
    /08-observability
    /09-packaging
    /10-gitops
    /11-operators
    /12-production
    /13-troubleshooting
    /14-certifications
    /_templates

/labs
/manifests
/assets
/diagrams
/interview
/revision
/cheatsheets
/scripts
```

## 46-LESSON CURRICULUM MAP

| Module | Lessons | Focus |
|--------|---------|-------|
| 01 Fundamentals | 1-2 | Kubernetes basics, containers, and kubectl |
| 02 Architecture | 3-5 | Scheduling, taints, affinity, and worker node internals |
| 03 Workloads | 6-12 | Pods, Deployments, StatefulSets, DaemonSets, Jobs, Init Containers |
| 04 Networking | 13-18 | CNI, Services, Ingress, Network Policies, traffic flow, service mesh |
| 05 Storage | 19 | Volumes, PV/PVC, Storage Classes |
| 06 Configuration | 20-21 | ConfigMaps, Secrets, resource requests/limits |
| 07 Security | 22-23 | RBAC, ServiceAccounts, Pod Security, security contexts |
| 08 Observability | 24-28 | Monitoring, logging, probes, Prometheus, Loki |
| 09 Packaging | 29-30 | Helm and production chart authoring |
| 10 GitOps | 31-32 | GitOps principles, Argo CD, CI/CD pipelines |
| 11 Operators | 33-34 | CRDs, Operator pattern |
| 12 Production | 35-40 | Autoscaling, HA, upgrades, backups, multi-cluster, progressive delivery |
| 13 Troubleshooting | 41-42 | Workload/node and networking/cluster diagnosis |
| 14 Certifications | 43-46 | Certification roadmap, CKA, CKAD/CKS, capstone |

Lesson files follow `lesson-NN-slug.md`. Module indexes list lessons with a Status column (`Planned`, `In Progress`, `Complete`).

## EVERY LESSON MUST CONTAIN

All of the following sections, in this order (see `docs/_templates/lesson-template.md`):

1. Table of Contents
2. Learning Objectives
3. Prerequisites
4. Real-world Motivation
5. Core Concepts
6. Architecture
7. ASCII Diagrams
8. Hands-on
9. Commands
10. YAML Explanation
11. Production Notes
12. Best Practices
13. Common Mistakes
14. Troubleshooting
15. Interview Questions
16. Scenario Questions
17. Quiz
18. Revision
19. Cheat Sheet
20. References
21. Related Lessons
22. Coming Next

## README RESPONSIBILITIES

Maintain in `README.md`:

- Repository Overview
- Learning Roadmap
- Progress Tracker
- Folder Map
- Contribution Guide
- Quick Start
- Prerequisites
- Recommended Learning Order
- Useful Resources

## FORMATTING RULES

- NEVER use emojis anywhere in the repository
- Use US English spelling
- Use kebab-case for file names
- Numbered folders and lessons keep the curriculum in order
- Use relative links only, never absolute local paths
- Use tables for structured data
- Use fenced code blocks with language identifiers for commands and YAML
- Consistent headings, naming, file names, and numbering across the repo
- Professional tables, callouts, clean formatting
- Do not add code comments to files unless asked
- World-class formatting: easy to read and navigate

## WHEN THE USER PROVIDES A LESSON

The user provides lesson content one lesson at a time. Treat the provided lesson as the source material:

1. Expand it using Kubernetes best practices
2. Keep the user's intent
3. Do not remove important information
4. Clearly distinguish content sources with headings:
   - `From Lesson` - content provided by the user
   - `Additional Production Knowledge` - agent-expanded content
5. Create the lesson file at `docs/NN-module/lesson-NN-slug.md`
6. Update the module README: set status to `Complete` and add the lesson link
7. Update progress tracker status in `README.md` and `docs/README.md`
8. Never overwrite unrelated files

## GIT RESPONSIBILITIES

Before committing:

1. Review all modified files
2. Check for broken links (run the link checker if available)
3. Ensure markdown consistency
4. Create meaningful, conventional commits

Commit message examples (never vague):

- `docs: add Lesson 08 Services`
- `docs: improve Deployment diagrams`
- `docs: add interview questions for ConfigMaps`
- `refactor: reorganize networking section`
- `fix: correct StatefulSet explanation`

When the repository has meaningful changes, the maintainer pushes to `origin main`.

## QUALITY CHECK BEFORE COMMITTING

Verify all of the following:

- Markdown renders correctly
- No duplicate content
- Internal links work
- Naming is consistent
- Numbering is correct
- README updated if needed
- Navigation updated
- Production-ready documentation
- Beginner friendly
- Interview ready
- No emojis present

## CURRENT REPOSITORY STATUS

- All 46 lesson files are `Complete` and follow the 22-section template
- Lesson numbering is globally unique and sequential by module (1-46)
- Module indexes exist in all 14 module folders and reflect the published lessons
- Documentation hub exists at `docs/README.md`
- Lesson template exists at `docs/_templates/lesson-template.md`
- Supporting directories exist with conventions READMEs (labs, manifests, assets, diagrams, interview, revision, cheatsheets, scripts)
- Root files exist: README.md, ROADMAP.md, CONTRIBUTING.md, LICENSE, .gitignore
- Next work: continuous improvement, new labs, and community contributions

## WORKFLOW WHEN THE USER SAYS "START A NEW LESSON"

1. Wait for the lesson content or use the curriculum map to write the lesson
2. Write the full lesson file following the template and formatting rules
3. Update the module README index (status -> `Complete`, add link)
4. Update progress tracker in root `README.md` and `docs/README.md`
5. Optionally add a matching lab in `labs/` and manifests in `manifests/`
6. Run the quality check
7. Commit with a meaningful message and push to `origin main`

## USEFUL REPOSITORY LINKS

- `docs/_templates/lesson-template.md` - the lesson structure template
- `README.md` - project overview and progress tracker
- `ROADMAP.md` - delivery plan and milestones
- `CONTRIBUTING.md` - contribution standards
