# Pre-Commit Framework — DevSecOps Shift-Left Strategy

## Philosophy

Every bug caught before `git push` is a bug that never reaches CI, never blocks a teammate, and never touches production. This pre-commit framework enforces security, correctness, and consistency across every technology in the stack.

---

## Coverage Matrix

| Stack Layer | Tool | What It Catches |
|-------------|------|----------------|
| **Secrets** | Gitleaks | AWS keys, tokens, passwords, private keys committed to Git |
| **Secrets** | detect-secrets | Baseline-aware secret detection (fewer false positives over time) |
| **Terraform** | terraform_fmt | Inconsistent formatting → merge conflicts |
| **Terraform** | terraform_validate | Syntax errors, invalid resource references |
| **Terraform** | TFLint + AWS plugin | Deprecated syntax, invalid instance types, unused variables |
| **Terraform** | tfsec | Security misconfigs (open SGs, unencrypted storage, public S3) |
| **Terraform** | Checkov | CIS benchmarks, SOC2-relevant controls for AWS resources |
| **Helm/K8s** | helm lint | Chart structure errors, invalid templates |
| **Helm/K8s** | helm template | Template rendering failures for all value files |
| **Helm/K8s** | KubeLinter | Missing resource limits, no readiness probes, running as root |
| **Docker** | Hadolint | Using `latest` tag, running as root, inefficient layering |
| **Python** | Ruff | Import errors, undefined variables, style violations |
| **Python** | Ruff format | Inconsistent formatting (Black-compatible) |
| **Python** | Mypy | Type errors caught before runtime |
| **Python** | Bandit | SQL injection patterns, hardcoded passwords, unsafe deserialization |
| **Shell** | ShellCheck | Unquoted variables, unsafe glob expansion, POSIX compatibility |
| **GitHub Actions** | ActionLint | Invalid workflow syntax, undefined secrets, type mismatches |
| **YAML/JSON** | pre-commit-hooks | Syntax validation, merge conflicts, large files |
| **Markdown** | markdownlint | Consistent documentation formatting |
| **Git workflow** | no-commit-to-branch | Prevents direct pushes to main/master |
| **Git workflow** | conventional-pre-commit | Enforces conventional commit messages |

---

## Installation

### Prerequisites

```bash
# Python 3.8+
pip install pre-commit

# Terraform tools
# - terraform (>= 1.5)
# - tflint (install via https://github.com/terraform-linters/tflint)
# - tfsec (install via https://github.com/aquasecurity/tfsec)
# - checkov: pip install checkov

# Kubernetes tools
# - helm (>= 3.12)
# - kube-linter (install via https://github.com/stackrox/kube-linter)

# Docker
# - hadolint (pulled as Docker image automatically, or install binary)

# Shell
# - shellcheck (install via package manager)

# GitHub Actions
# - actionlint (install via https://github.com/rhysd/actionlint)
```

### Setup

```bash
# From repository root
pre-commit install                    # Install pre-commit hook
pre-commit install --hook-type commit-msg  # Install commit-msg hook

# Initialize detect-secrets baseline
detect-secrets scan > .secrets.baseline

# Initialize TFLint plugins
cd terraform && tflint --init && cd ..

# Run against all files (first time)
pre-commit run --all-files
```

---

## Usage

### Automatic (on every commit)

Once installed, hooks run automatically on `git commit`. Only staged files are checked.

```bash
git add terraform/main.tf
git commit -m "feat(terraform): add EKS cluster resource"
# → All relevant hooks run automatically
```

### Manual (check everything)

```bash
pre-commit run --all-files
```

### Run specific hook

```bash
pre-commit run terraform_tfsec --all-files
pre-commit run gitleaks --all-files
pre-commit run bandit --all-files
```

### Skip hooks (emergency only — requires justification in PR)

```bash
git commit --no-verify -m "hotfix: emergency patch (hooks bypassed)"
```

---

## Security-First Design Decisions

### 1. Secrets Never Reach Git

Two layers of secret detection:
- **Gitleaks**: Pattern-based detection (AWS keys, GCP credentials, generic tokens)
- **detect-secrets**: Entropy-based detection with a baseline file that reduces false positives over time

### 2. Terraform Security Scanning

Three complementary tools:
- **tfsec**: Fast, focused on AWS security misconfigurations
- **Checkov**: Policy-as-code with CIS benchmark coverage
- **TFLint**: Catches valid-but-wrong configs (e.g., invalid instance types)

### 3. Kubernetes Security Posture

KubeLinter catches the exact issues that caused Cavendish's incidents:
- Pods running as root → Pod Security Standards violation
- Missing NetworkPolicy → flat networking (the pen test finding)
- No resource limits → noisy neighbour, OOM kills
- Default ServiceAccount → over-privileged Pods

### 4. No Direct Commits to Main

The `no-commit-to-branch` hook enforces the branch-based workflow that the CI/CD pipeline depends on. Every change goes through a PR.

---

## Handling False Positives

### detect-secrets baseline

```bash
# After confirming a detection is a false positive:
detect-secrets scan --update .secrets.baseline
git add .secrets.baseline
```

### tfsec inline suppression (with justification)

```hcl
#tfsec:ignore:aws-vpc-no-public-ingress-sgr -- ALB security group requires public access
resource "aws_security_group_rule" "alb_ingress" {
  # ...
}
```

### KubeLinter annotation

```yaml
metadata:
  annotations:
    # kube-linter ignore reason: postgres requires stable storage identity
    ignore-check.kube-linter.io/no-read-only-root-fs: "PostgreSQL requires writable data directory"
```

---

## CI Integration

The same checks run in GitHub Actions CI to catch anything that bypassed local hooks:

```yaml
# .github/workflows/ci.yml (relevant section)
- name: Run pre-commit
  uses: pre-commit/action@v3.0.1
  with:
    extra_args: --all-files
```

This ensures the pipeline is the final gate — local hooks are the fast feedback loop, CI is the enforcement layer.

---

## Maintenance

```bash
# Update all hook versions
pre-commit autoupdate

# Clear cache if hooks misbehave
pre-commit clean
pre-commit install
```

Run `pre-commit autoupdate` monthly to stay current with security scanner rule updates.
