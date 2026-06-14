# eks-production-platform-cavendish

## Production-Grade EKS Platform Engineering with Terraform, GitOps, and Observability

A fully auditable, security-hardened AWS EKS platform built for Cavendish Analytics —
an 85-person fintech firm serving twelve institutional clients with near-real-time
portfolio analytics. This project addresses six production incidents traced to structural
infrastructure gaps and delivers a platform that a real engineering team could inherit,
operate, and hand to a Series B due diligence auditor.

---

## Table of Contents

- [eks-production-platform-cavendish](#eks-production-platform-cavendish)
  - [Production-Grade EKS Platform Engineering with Terraform, GitOps, and Observability](#production-grade-eks-platform-engineering-with-terraform-gitops-and-observability)
  - [Table of Contents](#table-of-contents)
  - [Project Overview](#project-overview)
    - [The Problem](#the-problem)
    - [The Solution](#the-solution)
  - [Architecture](#architecture)
    - [Key Architecture Decisions](#key-architecture-decisions)
  - [Shift-Left Security Strategy](#shift-left-security-strategy)
    - [Why Shift-Left?](#why-shift-left)
    - [Pre-Commit Security Layers](#pre-commit-security-layers)
    - [Security Coverage by Cavendish Incident](#security-coverage-by-cavendish-incident)
    - [Tools in the Framework](#tools-in-the-framework)
  - [Technology Stack](#technology-stack)
  - [Repository Structure](#repository-structure)
  - [Phase 0 — Reverse Proxy Foundations](#phase-0--reverse-proxy-foundations)
  - [Deliverables](#deliverables)
  - [Branch Protection \& Contribution Strategy](#branch-protection--contribution-strategy)
    - [Branch Model](#branch-model)
    - [Enforcement Layers](#enforcement-layers)
    - [Pre-Commit Enforcement](#pre-commit-enforcement)
    - [How Contributors Onboard](#how-contributors-onboard)
  - [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Pre-Commit Setup](#pre-commit-setup)
    - [Infrastructure Deployment](#infrastructure-deployment)
    - [Environment Promotion Strategy](#environment-promotion-strategy)
  - [Documentation](#documentation)
  - [License](#license)

---

## Project Overview

### The Problem

Cavendish Analytics grew from two engineers to fourteen in under three years. The infrastructure accumulated debt silently — until six incidents in eighteen months exposed a pattern:

| Incident | Root Cause |
| ---------- | ----------- |
| IAM access key with S3FullAccess committed to Git, undetected for 4 months | No IRSA — hardcoded AWS credentials |
| EKS cluster config lost when engineer left; 3-day rebuild | No Terraform — console-provisioned cluster |
| Staging had 2 replicas, production had 1; discovered during outage | No Helm — 47 YAML files per environment |
| Analytics API collapsed during end-of-quarter spike; 55 min to recover | No HPA — fixed replica count |
| PostgreSQL node failed; PVC unavailable 40 min, no restore procedure | No backup or DR procedure |
| Pen test: compromised front-end Pod had unrestricted TCP to PostgreSQL | No NetworkPolicy — flat cluster networking |

### The Solution

A complete platform re-architecture addressing every root cause:

- **Infrastructure as Code** — Every AWS resource provisioned via Terraform. State locked in S3/DynamoDB. Zero console-created resources.
- **Credential Elimination** — IRSA for all AWS access. No IAM users, no access keys, no secrets in Git.
- **Environment Parity** — Single Helm chart with per-environment values. ArgoCD ApplicationSet
  deploys to staging, UAT, and production from one template. Three environments mirror real-world
  promotion: staging (dev integration) → UAT (client acceptance) → production (live traffic).
- **Observability Before Incidents** — kube-prometheus-stack with postgres-exporter, four-panel Grafana dashboard, PrometheusRule alerting.
- **Tested Disaster Recovery** — Velero backup to S3 + pg_dump CronJob every 6 hours. Full namespace restore tested and timed.
- **Network Segmentation** — Default-deny NetworkPolicy with explicit allow rules per communication path.

---

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                            AWS Cloud (eu-west-2)                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐     ┌──────────────────────────────────────────────────┐  │
│  │  Route 53   │────▶│              Application Load Balancer            │  │
│  │ (ExternalDNS│     │              (ACM TLS Certificate)               │  │
│  │  managed)   │     └───────────────────────┬──────────────────────────┘  │
│  └─────────────┘                             │                             │
│                                              ▼                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                        EKS Cluster (Terraform)                        │  │
│  │                                                                       │  │
│  │  ┌────────────────────┐  ┌────────────────────┐  ┌────────────────┐  │  │
│  │  │ cavendish-staging  │  │  cavendish-uat     │  │cavendish-prod  │  │  │
│  │  │                    │  │                    │  │                │  │  │
│  │  │ ┌──────────┐      │  │ ┌──────────┐      │  │ ┌──────────┐  │  │  │
│  │  │ │Analytics │      │  │ │Analytics │      │  │ │Analytics │  │  │  │
│  │  │ │API       │      │  │ │API       │      │  │ │API + HPA │  │  │  │
│  │  │ └────┬─────┘      │  │ └────┬─────┘      │  │ └────┬─────┘  │  │  │
│  │  │      │NetworkPolicy│  │      │NetworkPolicy│  │      │NetPol  │  │  │
│  │  │      ▼            │  │      ▼            │  │      ▼        │  │  │
│  │  │ ┌──────────┐      │  │ ┌──────────┐      │  │ ┌──────────┐  │  │  │
│  │  │ │PostgreSQL│      │  │ │PostgreSQL│      │  │ │PostgreSQL│  │  │  │
│  │  │ │+exporter │      │  │ │+exporter │      │  │ │+exporter │  │  │  │
│  │  │ └────┬─────┘      │  │ └────┬─────┘      │  │ └────┬─────┘  │  │  │
│  │  │      │            │  │      │            │  │      │        │  │  │
│  │  └──────┼─────────────┘  └──────┼─────────────┘  └──────┼────────┘  │  │
│  │         │                       │                        │           │  │
│  │         ▼                       ▼                        ▼           │  │
│  │  ┌───────────────────────────────────────────────────────────────┐   │  │
│  │  │  Promotion Flow:  staging ──▶ UAT ──▶ production              │   │  │
│  │  │  (dev integration)  (client acceptance)  (live traffic)       │   │  │
│  │  └───────────────────────────────────────────────────────────────┘   │  │
│  │           │                                │                          │  │
│  │  ┌────────┼────────────────────────────────┼──────────────────────┐  │  │
│  │  │  Observability (kube-prometheus-stack)  │                      │  │  │
│  │  │  ┌──────────┐  ┌────────┐  ┌──────────────────┐               │  │  │
│  │  │  │Prometheus│  │Grafana │  │PrometheusRule    │               │  │  │
│  │  │  │          │◀─┤4-panel │  │(API errors + DB) │               │  │  │
│  │  │  │          │  │dashboard│  └──────────────────┘               │  │  │
│  │  │  └──────────┘  └────────┘                                      │  │  │
│  │  └────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                       │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────┐  ┌───────────────┐    │  │
│  │  │  ArgoCD  │  │  Velero  │  │Cluster       │  │AWS LB         │    │  │
│  │  │  AppSet  │  │  → S3    │  │Autoscaler    │  │Controller     │    │  │
│  │  └──────────┘  └──────────┘  └──────────────┘  └───────────────┘    │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   ECR    │  │   S3 Bucket  │  │AWS Secrets   │  │  IRSA (OIDC)     │  │
│  │(scanned) │  │(backups/state)│  │Manager       │  │  5 roles         │  │
│  └──────────┘  └──────────────┘  └──────────────┘  └──────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                         GitHub Actions (OIDC → AWS)                          │
│  ci.yml: helm lint → docker build → ECR push                                │
│  deploy.yml: helm upgrade --atomic (on merge to main)                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Architecture Decisions

| Decision | Rationale |
| ---------- | ----------- |
| IRSA over instance profiles | Pod-level least privilege. Blast radius of a compromised Pod limited to one role. |
| ALB + ACM over Nginx + cert-manager | AWS-native TLS lifecycle. No certificate secrets in-cluster. Automatic renewal. |
| ArgoCD ApplicationSet over multiple helm install | Single template generates N environments. Adding UAT was one line in the generators list. |
| Three environments (staging → UAT → prod) | Mirrors real-world promotion gates. UAT validates client-facing behaviour before production. |
| StatefulSet + EBS CSI over RDS | Full control over PostgreSQL config, sidecar metrics, and backup strategy. Cost-effective for this workload. |
| Velero + pg_dump dual backup | Velero covers Kubernetes state. pg_dump covers point-in-time database recovery. Belt and suspenders. |
| NetworkPolicy default-deny | Assumes breach. Every allowed path is explicit and auditable. |

---

## Shift-Left Security Strategy

Security is not a gate at the end of the pipeline — it is embedded at every stage of the development lifecycle. This project implements a comprehensive shift-left approach from the very first commit.

### Why Shift-Left?

Cavendish's original architecture failed because security was an afterthought:

- An IAM key lived in Git for 4 months because no scanner existed
- A flat network allowed lateral movement because no one reviewed Pod communication paths
- No one validated Terraform before apply because there was no Terraform

This project inverts that model. **Every commit is validated before it reaches the remote.**

### Pre-Commit Security Layers

```text
Developer writes code
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│                    PRE-COMMIT HOOKS (Local)                     │
│                                                                │
│  Layer 1: SECRETS          Gitleaks + detect-secrets           │
│  ──────────────────────────────────────────────────────────    │
│  Layer 2: INFRASTRUCTURE   tfsec + Checkov + TFLint            │
│  ──────────────────────────────────────────────────────────    │
│  Layer 3: KUBERNETES       KubeLinter + helm lint + template   │
│  ──────────────────────────────────────────────────────────    │
│  Layer 4: CONTAINERS       Hadolint (Dockerfile)               │
│  ──────────────────────────────────────────────────────────    │
│  Layer 5: APPLICATION      Ruff + Mypy + Bandit (Python)       │
│  ──────────────────────────────────────────────────────────    │
│  Layer 6: SHELL            ShellCheck                          │
│  ──────────────────────────────────────────────────────────    │
│  Layer 7: CI WORKFLOWS     ActionLint                          │
│  ──────────────────────────────────────────────────────────    │
│  Layer 8: GIT HYGIENE      no-commit-to-branch + conventional  │
│                            commits                             │
└───────────────────────────────────────────────────────────────┘
        │
        ▼ (only clean code passes)
┌───────────────────────────────────────────────────────────────┐
│                    CI PIPELINE (GitHub Actions)                 │
│  Same checks + integration tests + ECR image scan              │
└───────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│                    RUNTIME (EKS Cluster)                        │
│  Pod Security Standards │ NetworkPolicy │ RBAC │ IRSA          │
└───────────────────────────────────────────────────────────────┘
```

### Security Coverage by Cavendish Incident

| Original Incident | Shift-Left Prevention |
| ------------------- | ---------------------- |
| IAM key committed to Git | **Gitleaks** blocks the commit. **detect-secrets** catches entropy-based patterns. |
| Console-provisioned cluster | **terraform_validate** + **tfsec** ensures all infra is code-reviewed and secure. |
| YAML drift between environments | **helm lint** + **helm template** validates all three environments render correctly. |
| No autoscaling | **KubeLinter** flags missing resource requests/limits that HPA depends on. |
| No NetworkPolicy | **KubeLinter** flags Pods without NetworkPolicy in production namespaces. |
| Running as root | **KubeLinter** + **Pod Security Standards** enforce non-root, read-only FS, dropped capabilities. |

### Tools in the Framework

| Category | Tool | Purpose |
| ---------- | ------ | --------- |
| Secrets | [Gitleaks](https://github.com/gitleaks/gitleaks) | Pattern-based secret detection (AWS keys, tokens, passwords) |
| Secrets | [detect-secrets](https://github.com/Yelp/detect-secrets) | Entropy-based detection with baseline to reduce false positives |
| Terraform | [terraform fmt/validate](https://www.terraform.io/) | Formatting consistency + syntax validation |
| Terraform | [TFLint](https://github.com/terraform-linters/tflint) | AWS-specific linting (invalid types, deprecated syntax) |
| Terraform | [tfsec](https://github.com/aquasecurity/tfsec) | Infrastructure security scanning |
| Terraform | [Checkov](https://github.com/bridgecrewio/checkov) | CIS benchmarks + SOC2 compliance checks |
| Kubernetes | [helm lint](https://helm.sh/) | Chart structure validation |
| Kubernetes | [KubeLinter](https://github.com/stackrox/kube-linter) | Security and production-readiness checks |
| Docker | [Hadolint](https://github.com/hadolint/hadolint) | Dockerfile best practices |
| Python | [Ruff](https://github.com/astral-sh/ruff) | Fast linting + formatting |
| Python | [Mypy](https://github.com/python/mypy) | Static type checking |
| Python | [Bandit](https://github.com/PyCQA/bandit) | Security-focused Python linting |
| Shell | [ShellCheck](https://github.com/koalaman/shellcheck) | Shell script bug detection |
| CI | [ActionLint](https://github.com/rhysd/actionlint) | GitHub Actions workflow validation |

---

## Technology Stack

| Layer | Technology | Purpose |
| ------- | ----------- | --------- |
| Cloud | AWS (EKS, ECR, S3, Route 53, ACM, Secrets Manager) | Managed Kubernetes + supporting services |
| IaC | Terraform + AWS Provider | Declarative infrastructure, state in S3 |
| Container Orchestration | EKS (Kubernetes 1.29+) | Production control plane |
| Packaging | Helm 3 | Templated multi-environment deployments |
| GitOps | ArgoCD + ApplicationSet | Declarative continuous delivery |
| Ingress | AWS Load Balancer Controller + ALB | L7 routing with ACM TLS |
| DNS | ExternalDNS + Route 53 | Automatic DNS record management |
| Identity | IRSA (IAM Roles for Service Accounts) | Pod-level AWS permissions via OIDC |
| Secrets | AWS Secrets Manager + CSI Driver | Secret injection without Git exposure |
| Database | PostgreSQL (StatefulSet on EBS) | Persistent analytics backend |
| Metrics | postgres-exporter sidecar | Database-level Prometheus metrics |
| Monitoring | kube-prometheus-stack | Cluster and application observability |
| Dashboards | Grafana | Four-panel operational dashboard |
| Alerting | PrometheusRule | API error rate + DB connection alerts |
| Autoscaling | HPA + Cluster Autoscaler | Pod and node-level scaling |
| Network Security | NetworkPolicy (Calico/Cilium) | Default-deny + explicit allow rules |
| Pod Security | Pod Security Standards (restricted) | Non-root, read-only FS, dropped caps |
| Backup | Velero + S3 | Kubernetes resource backup |
| DB Backup | pg_dump CronJob → S3 | Point-in-time database recovery |
| CI/CD | GitHub Actions (OIDC) | Lint → build → push → deploy, no static creds |
| Application | FastAPI (Python) | Analytics API serving client dashboards |

---

## Repository Structure

```text
eks-production-platform-cavendish/
├── app/                              # FastAPI Analytics API
├── chart/
│   ├── Chart.yaml
│   ├── values.yaml                   # Base defaults
│   ├── values.staging.yaml           # Staging overrides
│   ├── values.uat.yaml              # UAT — client acceptance testing
│   ├── values.production.yaml        # Production — HPA + monitoring enabled
│   └── templates/
│       ├── deployment.yaml           # Range loop — all services
│       ├── service.yaml
│       ├── ingress.yaml              # ALB + ACM + ExternalDNS annotations
│       ├── serviceaccount.yaml       # IRSA annotation per service
│       ├── role.yaml
│       ├── rolebinding.yaml
│       ├── hpa.yaml                  # Conditional on values.hpa.enabled
│       ├── networkpolicy.yaml        # Default-deny + allow rules
│       ├── statefulset.yaml          # PostgreSQL + postgres-exporter sidecar
│       ├── cronjob.yaml              # pg_dump → S3 every 6 hours via IRSA
│       ├── servicemonitor.yaml       # Prometheus scrape config
│       └── prometheusrule.yaml       # API error rate + DB connection alerts
├── terraform/
│   ├── main.tf                       # VPC, EKS, ECR, S3
│   ├── irsa.tf                       # 5 IRSA roles + GitHub OIDC
│   ├── variables.tf
│   └── outputs.tf
├── argocd/
│   └── applicationset.yaml           # Generates staging + UAT + production Applications
├── monitoring/
│   ├── prometheus-values.yaml        # kube-prometheus-stack overrides
│   └── grafana-dashboard.json        # Four-panel dashboard export
├── velero/
│   └── backup-schedule.yaml          # Daily 02:00 UTC
├── phase0/                           # k3s manifests + documentation (Phase 0)
├── .github/workflows/
│   ├── ci.yml                        # Lint + build + push to ECR
│   └── deploy.yml                    # helm upgrade --atomic via OIDC
├── docs/
│   ├── architecture.md
│   ├── cost-guide.md
│   ├── dr-results.md
│   ├── runbook.md
│   └── phase0-demo.txt
├── .pre-commit-config.yaml           # 20+ hooks across 10 categories
├── .tflint.hcl                       # TFLint AWS plugin config
├── .kube-linter.yaml                 # KubeLinter checks config
├── .markdownlint.yaml                # Documentation linting rules
├── .gitignore
└── README.md
```

---

## Phase 0 — Reverse Proxy Foundations

Before touching EKS, three days are spent building the reverse proxy and TLS stack manually on k3s. This is not a warm-up — it is the foundation that makes every EKS automation explainable.

| Phase 0 (Manual) | EKS Equivalent (Automated) | What You Learn |
| ------------------ | --------------------------- | ---------------- |
| Nginx Ingress Controller | AWS Load Balancer Controller + ALB | What an Ingress controller actually does |
| FreeDNS A record | ExternalDNS + Route 53 | DNS must point to your load balancer |
| cert-manager + ClusterIssuer | AWS Certificate Manager (ACM) | ACME protocol and TLS lifecycle |
| HTTP-01 challenge | ACM internal validation | Domain ownership verification |
| TLS Secret in Kubernetes | ACM cert attached to ALB | Certificate storage patterns |
| whitelist-source-range | ALB inbound-cidrs | Source IP restriction at L7 |
| Delete Ingress = 404 | ArgoCD enforces desired state | Decommission pattern |

---

## Deliverables

Seventeen verifiable deliverables — three from Phase 0, fourteen from the EKS platform:

| Ref | Deliverable | Verification |
| ----- | ------------ | -------------- |
| P0-D1 | Nginx Ingress HTTP routing | `curl` returns 200 from inside cluster |
| P0-D2 | HTTPS via cert-manager | Certificate Ready: True, no warning |
| P0-D3 | IP restriction + decommission | 403 from blocked IP, 404 on delete, 200 on restore |
| D1 | EKS cluster via Terraform | `terraform show` + `kubectl get nodes` Ready |
| D2 | Helm deploys to all three namespaces | `helm list -A` shows all releases |
| D3 | HTTPS via ALB + ACM | ACM Issued, `curl` returns 200 |
| D4 | IRSA — zero access keys | `aws sts get-caller-identity` shows IRSA role ARN |
| D5 | Secrets Manager + CSI Driver | `env \| grep DB_PASSWORD` shows Secrets Manager value |
| D6 | HPA scales under load | 2 → ≥5 replicas under k6 load test |
| D7 | NetworkPolicy enforced | Cross-namespace curl refused, allowed path succeeds |
| D8 | Prometheus + postgres-exporter | All targets UP, `pg_stat_activity_count` visible |
| D9 | Grafana 4-panel dashboard | All panels live, JSON exported |
| D10 | Alerts fire and resolve | PrometheusRule triggers, notification received |
| D11 | GitHub Actions pipeline | Push → CI passes → CD deploys new revision |
| D12 | Disaster recovery tested | Namespace deleted → restored → data verified |
| D13 | RBAC — no default SA | Every Pod has named ServiceAccount + Role |
| D14 | Pod Security Standards | Privileged Pod rejected by admission controller |

---

## Branch Protection & Contribution Strategy

### Branch Model

`main` is protected. All changes go through pull requests — no exceptions.

```text
main (protected — admin bypass only)
  │
  ├── feature/terraform-vpc         ← new functionality
  ├── fix/ingress-annotation         ← bug fix
  ├── docs/runbook-day2              ← documentation
  ├── chore/update-dependencies      ← maintenance
  └── ci/add-trivy-scan              ← pipeline changes
```

### Enforcement Layers

| Layer | What It Enforces | Bypass |
| ------- | ----------------- | -------- |
| **Branch ruleset** | No direct push to main, require PR, block force push | Admin only |
| **PR label check** (CI) | Every PR must have `type:` + `priority:` labels | None — blocks merge |
| **Pre-commit hooks** (CI) | Linting, security scanning, formatting across all stacks | None — blocks merge |
| **CODEOWNERS** | Auto-assigns reviewers, requires owner approval for sensitive files | None |
| **Signed commits** | Proves authorship — important for fintech audit trail | None |

### Pre-Commit Enforcement

Pre-commit hooks run at two levels:

```text
┌─────────────────────────────────────────────────────────────┐
│  LOCAL (developer machine)                                   │
│  pre-commit install → hooks run on every git commit          │
│  ⚡ Fast feedback — catches issues in seconds               │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               │ git push → open PR
                               ▼
┌─────────────────────────────────────────────────────────────┐
│  CI (GitHub Actions)                                         │
│  pre-commit run --all-files → same hooks run in pipeline     │
│  🔒 Enforcement gate — blocks merge if any check fails      │
└─────────────────────────────────────────────────────────────┘
```

**Can a contributor skip local hooks?** Yes — `git commit --no-verify` bypasses local hooks.
But it doesn't matter because CI runs the identical checks. If a contributor skips hooks
locally, CI will catch it and **block the merge**. There's no way around it.

This is the real-world pattern: local hooks are a *convenience* (fast feedback), CI is the *enforcement* (merge gate).

### How Contributors Onboard

```bash
# 1. Clone
git clone git@github.com:joneskwameosei/eks-production-platform-cavendish.git

# 2. Install pre-commit hooks (required — CI will reject PRs without passing checks)
pip install pre-commit
pre-commit install
pre-commit install --hook-type commit-msg

# 3. Branch, code, commit, push, PR
git checkout -b feature/my-change
# ... make changes ...
git add .
git commit -m "feat(terraform): add S3 bucket for backups"
git push -u origin feature/my-change
# Open PR → add labels → request review → merge
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full contributor guide.

---

## Getting Started

### Prerequisites

- AWS CLI v2 configured with appropriate IAM permissions
- Terraform >= 1.5
- Helm >= 3.12
- kubectl
- Python >= 3.11
- Docker
- pre-commit (`pip install pre-commit`)

### Pre-Commit Setup

```bash
# Install hooks
pre-commit install
pre-commit install --hook-type commit-msg

# Initialize secrets baseline
detect-secrets scan > .secrets.baseline

# Initialize TFLint plugins
cd terraform && tflint --init && cd ..

# Verify everything works
pre-commit run --all-files
```

### Infrastructure Deployment

```bash
# Phase 1: Terraform
cd terraform
terraform init
terraform plan -var-file=production.tfvars
terraform apply -var-file=production.tfvars

# Phase 2: Helm + ArgoCD
kubectl apply -f argocd/applicationset.yaml

# ArgoCD syncs all three environments automatically
# Promotion flow: staging → UAT → production
```

### Environment Promotion Strategy

```text
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│   STAGING    │─────▶│     UAT      │─────▶│  PRODUCTION  │
│              │      │              │      │              │
│ • Dev integ- │      │ • Client     │      │ • Live       │
│   ration     │      │   acceptance │      │   traffic    │
│ • Auto-deploy│      │ • Manual gate│      │ • Manual gate│
│   on merge   │      │ • Smoke tests│      │ • Full HPA   │
│ • Relaxed    │      │ • Prod-like  │      │ • Alerting   │
│   resources  │      │   config     │      │   active     │
└──────────────┘      └──────────────┘      └──────────────┘

Namespaces:
  cavendish-staging     cavendish-uat     cavendish-production
```

---

## Documentation

| Document | Description |
| ---------- | ------------- |
| [Architecture](docs/architecture.md) | Detailed architecture decisions and diagrams |
| [Cost Guide](docs/cost-guide.md) | AWS resource cost breakdown and optimization |
| [DR Results](docs/dr-results.md) | Disaster recovery test results and RTO |
| [Runbook](docs/runbook.md) | Operational procedures for common scenarios |
| [Pre-Commit Guide](pre-commit-guide.md) | Detailed pre-commit framework documentation |
| [Contributing](CONTRIBUTING.md) | Branch workflow, commit conventions, PR labels, review standards |

---

## License

This project is built as a portfolio demonstration of production-grade platform engineering practices.

---

<p align="center">
  <strong>Built with security-first principles. Every commit validated. Every secret caught. Every resource declared in code.</strong>
</p>
