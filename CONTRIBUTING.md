# CONTRIBUTING

Thank you for considering contributing to Kubernetes Zero to Production. This repository aims to be one of the best Kubernetes learning resources available, and every contribution matters.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How to Contribute](#how-to-contribute)
- [Contribution Types](#contribution-types)
- [Repository Conventions](#repository-conventions)
- [The Lesson Template](#the-lesson-template)
- [Markdown Standards](#markdown-standards)
- [Naming Conventions](#naming-conventions)
- [Quality Checklist](#quality-checklist)
- [Commit Messages](#commit-messages)
- [Review Process](#review-process)

---

## Code of Conduct

Be respectful and constructive. This is a learning-focused open-source project. Feedback is welcome and should always be actionable and kind.

## How to Contribute

1. Fork the repository
2. Create a feature branch: `git checkout -b docs/lesson-01`
3. Make your changes following the conventions below
4. Run the quality checklist
5. Commit with a meaningful message
6. Open a pull request

## Contribution Types

The following contributions are valuable:

- New lesson content
- Improvements to existing lessons
- New or improved labs
- New or corrected manifests
- Diagrams (ASCII or image)
- Interview questions
- Revision notes and cheat sheets
- Fixes for typos, formatting, or broken links
- Troubleshooting content

## Repository Conventions

- All documentation is written in Markdown
- Use US English spelling
- Use kebab-case for file names
- Numbered folders and lessons keep the curriculum in order
- Relative links only - never absolute local paths
- No emojis in content or headings
- Use tables for structured data
- Use fenced code blocks with language identifiers for commands and YAML

## The Lesson Template

Every lesson must follow the standardized template. The full template is available at [docs/_templates/lesson-template.md](docs/_templates/lesson-template.md).

Every lesson must contain these sections in order:

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

## Markdown Standards

- Use `#` for the lesson title and `##` for sections
- Use tables instead of lists where comparison or structure is involved
- Use `[text](path)` for relative links
- Call out warnings or notes using blockquotes or `> **Note:**` formatting
- Keep line length reasonable for readability
- Use code fences with the correct language tag for every command and YAML block

## Naming Conventions

- Module folders: `NN-name`, for example `docs/03-workloads`
- Lesson files: `lesson-NN-slug.md`, for example `lesson-10-pods-in-depth.md`
- Manifests: `kebab-case-name.yaml`
- Labs: `lab-NN-name.md`, matching the lesson number

## Quality Checklist

Before submitting a contribution, verify:

- Markdown renders correctly
- No duplicate content
- Internal links work
- Naming is consistent
- Numbering is correct
- README and navigation are updated when files change
- Content is beginner friendly and interview ready
- No emojis or non-standard formatting

You can run the automated checks locally before opening a pull request:

```bash
python3 scripts/check-links.py
python3 scripts/validate-lessons.py
```

The same checks run automatically in the repository's CI workflow.

## Commit Messages

Use conventional, meaningful commit messages:

- `docs: add Lesson 10 Pods in Depth`
- `docs: improve Deployment rollout diagrams`
- `docs: add interview questions for ConfigMaps`
- `refactor: reorganize networking section`
- `fix: correct StatefulSet explanation`
- `feat: add lab for Services`

Avoid vague messages such as "update files" or "minor changes".

## Review Process

All pull requests are reviewed for:

- Correctness of technical content
- Adherence to the lesson template
- Markdown formatting and link integrity
- Consistency with existing content

Small typo and formatting fixes are merged quickly. Larger content additions are reviewed more carefully to preserve consistency across the repository.
