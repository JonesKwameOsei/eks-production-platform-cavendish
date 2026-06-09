# =============================================================================
# TFLint Configuration — EKS Platform Terraform
# =============================================================================

config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Naming conventions
rule "terraform_naming_convention" {
  enabled = true

  variable {
    format = "snake_case"
  }

  locals {
    format = "snake_case"
  }

  output {
    format = "snake_case"
  }

  resource {
    format = "snake_case"
  }

  module {
    format = "snake_case"
  }

  data {
    format = "snake_case"
  }
}

# Documentation
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

# Standard file structure
rule "terraform_standard_module_structure" {
  enabled = true
}

# No deprecated syntax
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Unused declarations
rule "terraform_unused_declarations" {
  enabled = true
}
