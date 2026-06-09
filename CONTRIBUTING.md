# Contributing to eks-production-platform-cavendish

## Workflow Overview

This project uses a **branch-based workflow** with protected `main`. No forks — everyone works from this repo directly.

```text
main (protected)
  │
  ├── feature/terraform-vpc        ← new functionality
  ├── fix/ingress-annotation        ← bug fix
  ├── docs/runbook-update           ← documentation
  └── chore/update-dependencies     ← maintenance
```

---

## Getting Started

### 1. Clone the Repository

```bash
git clone git@github.com:<org>/eks-production-platform-cavendish.git
cd eks-production-platform-cavendish
```

### 2. Install Pre-Commit Hooks

```bash
pip install pre-commit
pre-commit install
pre-commit install --hook-type commit-msg
```

### 3. Create a Branch

```bash
git checkout -b feature/your-feature-name
git switch -c feature/your-feature-name
```

---

## Branch Naming Convention

All branches must follow this pattern:

```text
<type>/<short-description>
```

| Type | Purpose | Example |
|------|---------|---------|
| `feature/` | New functionality | `feature/helm-networkpolicy` |
| `fix/` | Bug fixes | `fix/ingress-403-error` |
| `docs/` | Documentation only | `docs/runbook-day2` |
| `chore/` | Maintenance, refactoring | `chore/update-terraform-provider` |
| `ci/` | CI/CD pipeline changes | `ci/add-trivy-scan` |
| `security/` | Security patches | `security/patch-cve-2024-xxxx` |

---

## Commit Message Convention

We use [Conventional Commits](https://www.conventionalcommits.org/). The pre-commit hook enforces this automatically.

```text
<type>(scope): short description

[optional body]

[optional footer]
```

### Types

| Type | When |
|------|------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation changes |
| `style` | Formatting (no logic change) |
| `refactor` | Code restructuring (no feature/fix) |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `build` | Build system or dependencies |
| `ci` | CI/CD pipeline changes |
| `chore` | Maintenance tasks |
| `revert` | Reverting a previous commit |

### Scope (optional but encouraged)

Use the area of the project being changed:

```text
feat(terraform): add EKS managed node group
fix(helm): correct postgres port in statefulset
docs(runbook): add day 2 cert-manager steps
ci(workflows): add trivy image scan to ci.yml
security(pre-commit): update gitleaks to v8.19
```

### Examples

```bash
# Good
git commit -m "feat(terraform): provision VPC with 3 public and 3 private subnets"
git commit -m "fix(helm): correct IRSA annotation on pg-dump service account"
git commit -m "docs(runbook): add phase 0 day 2 cert-manager steps"

# Bad
git commit -m "fixed stuff"
git commit -m "update"
git commit -m "WIP"
```

---

## Pull Request Process

### 1. Push Your Branch

```bash
git push -u origin feature/your-feature-name
```

### 2. Open a Pull Request

- Target branch: `main`
- Fill in the PR template (see below)
- **Add labels** (required — see [Labels section](#pull-request-labels))

### 3. Required Labels

Every PR **must** have at least one type label and one priority label before merge.

#### Type Labels

| Label | Color | Description |
|-------|-------|-------------|
| `type: feature` | `#0E8A16` | New functionality |
| `type: fix` | `#D93F0B` | Bug fix |
| `type: docs` | `#0075CA` | Documentation |
| `type: chore` | `#FBCA04` | Maintenance |
| `type: ci` | `#6F42C1` | CI/CD changes |
| `type: security` | `#B60205` | Security patch |
| `type: refactor` | `#E4E669` | Code restructuring |

#### Priority Labels

| Label | Color | Description |
|-------|-------|-------------|
| `priority: critical` | `#B60205` | Blocks production |
| `priority: high` | `#D93F0B` | Needed this sprint |
| `priority: medium` | `#FBCA04` | Planned work |
| `priority: low` | `#0E8A16` | Nice to have |

#### Scope Labels

| Label | Color | Description |
|-------|-------|-------------|
| `scope: terraform` | `#5319E7` | Infrastructure as code |
| `scope: helm` | `#006B75` | Helm chart changes |
| `scope: app` | `#1D76DB` | Application code |
| `scope: monitoring` | `#D4C5F9` | Observability stack |
| `scope: ci-cd` | `#6F42C1` | Pipeline changes |
| `scope: argocd` | `#F9D0C4` | GitOps configuration |

### 4. PR Template

When opening a PR, use this structure:

```markdown
## Summary
Brief description of what this PR does.

## Changes
- Change 1
- Change 2

## Type of Change
- [ ] Feature
- [ ] Bug fix
- [ ] Documentation
- [ ] CI/CD
- [ ] Security patch
- [ ] Refactor

## Testing
How was this tested? What commands did you run?

## Checklist
- [ ] Pre-commit hooks pass locally (`pre-commit run --all-files`)
- [ ] Branch is up to date with main
- [ ] Labels added (type + priority)
- [ ] Documentation updated (if applicable)
- [ ] No secrets in code (checked with `pre-commit run gitleaks --all-files`)
```

### 5. Review

- CODEOWNERS automatically assigns reviewers based on files changed
- At least 1 approval required before merge
- CI must pass (pre-commit + lint + build)

### 6. Merge

- Only the project lead (`@jonesPlatformLead`) or designated reviewers merge
- Use **Squash and Merge** for feature branches (keeps main history clean)
- Branch is auto-deleted after merge

---

## Pull Request Labels

### Enforcing Labels with GitHub Actions

PR labels are enforced via CI. A PR without the required labels will fail the status check.

The workflow at `.github/workflows/pr-label-check.yml` validates that every PR has:

- At least one `type:` label
- At least one `priority:` label

See the [Label Enforcement](#label-enforcement-ci) section below for implementation details.

---

## Label Enforcement (CI)

Labels are enforced automatically by the GitHub Actions workflow below. PRs missing required labels will not pass status checks.

File: `.github/workflows/pr-label-check.yml`

This runs on every PR open/label change and blocks merge until labels are correct.

---

## Code Review Standards

### What Reviewers Check

| Area | What to verify |
|------|---------------|
| Security | No secrets, IRSA used correctly, NetworkPolicy coverage |
| Terraform | `terraform plan` output makes sense, no `0.0.0.0/0` without justification |
| Helm | Templates render for all 3 environments, values are parameterized |
| Python | Type hints present, no Bandit warnings, error handling |
| General | Conventional commit, descriptive PR, tests where applicable |

### Response Time

- **Critical/High priority**: Review within 4 hours
- **Medium**: Review within 24 hours
- **Low**: Review within 48 hours

---

## Security Rules

1. **Never commit secrets** — pre-commit hooks will block you, but be vigilant
2. **Never bypass pre-commit** without team lead approval and a justification comment in the PR
3. **Never push directly to main** — the ruleset blocks this, but don't try `--force`
4. **Report vulnerabilities** — if you find a security issue, notify `@jonesPlatformLead` directly before opening a public PR

---

## File Ownership

See `.github/CODEOWNERS` for who reviews what. Key rules:

- **Terraform, CI/CD, security configs** → Platform lead must approve
- **Helm chart** → Platform + backend engineers
- **Application code** → Backend engineers
- **Production values** → Platform lead only

---

## Questions?

Open a Discussion in the repo or reach out to `@jonesPlatformLead` directly.
