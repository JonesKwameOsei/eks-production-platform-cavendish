#!/usr/bin/env bash
# =============================================================================
# Create PR labels for eks-production-platform-cavendish
# =============================================================================
# Usage: ./create-labels.sh <owner/repo>
# Example: ./create-labels.sh yourname/eks-production-platform-cavendish
#
# Requires: GitHub CLI (gh) authenticated
# =============================================================================

set -euo pipefail

REPO="${1:?Usage: $0 <owner/repo>}"

echo "Creating labels for $REPO..."

# Type labels
gh label create "type: feature"   --repo "$REPO" --color "0E8A16" --description "New functionality" --force
gh label create "type: fix"       --repo "$REPO" --color "D93F0B" --description "Bug fix" --force
gh label create "type: docs"      --repo "$REPO" --color "0075CA" --description "Documentation" --force
gh label create "type: chore"     --repo "$REPO" --color "FBCA04" --description "Maintenance" --force
gh label create "type: ci"        --repo "$REPO" --color "6F42C1" --description "CI/CD changes" --force
gh label create "type: security"  --repo "$REPO" --color "B60205" --description "Security patch" --force
gh label create "type: refactor"  --repo "$REPO" --color "E4E669" --description "Code restructuring" --force

# Priority labels
gh label create "priority: critical" --repo "$REPO" --color "B60205" --description "Blocks production" --force
gh label create "priority: high"     --repo "$REPO" --color "D93F0B" --description "Needed this sprint" --force
gh label create "priority: medium"   --repo "$REPO" --color "FBCA04" --description "Planned work" --force
gh label create "priority: low"      --repo "$REPO" --color "0E8A16" --description "Nice to have" --force

# Scope labels
gh label create "scope: terraform"  --repo "$REPO" --color "5319E7" --description "Infrastructure as code" --force
gh label create "scope: helm"       --repo "$REPO" --color "006B75" --description "Helm chart changes" --force
gh label create "scope: app"        --repo "$REPO" --color "1D76DB" --description "Application code" --force
gh label create "scope: monitoring" --repo "$REPO" --color "D4C5F9" --description "Observability stack" --force
gh label create "scope: ci-cd"      --repo "$REPO" --color "6F42C1" --description "Pipeline changes" --force
gh label create "scope: argocd"     --repo "$REPO" --color "F9D0C4" --description "GitOps configuration" --force

echo "✅ All labels created successfully!"
