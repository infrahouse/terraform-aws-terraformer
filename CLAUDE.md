# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Terraform module that provisions a dedicated EC2 instance ("Terraformer") for administrative Terraform 
operations in AWS. The Terraformer is designed for elevated-permission operations like fixing corrupted state, 
migrations, and cross-account operations via AssumeRole.

## Essential Commands

### Development Setup
```bash
make bootstrap  # Install all dependencies and hooks
```

### Testing
```bash
make test       # Run full test suite (tests with AWS provider v5 and v6)
make test-keep  # Run tests and keep infrastructure for debugging
make test-clean # Run tests and destroy all resources (REQUIRED before PRs)
```

Test configuration variables:
- `TEST_REGION`: AWS region (default: us-west-2)
- `TEST_ROLE`: IAM role ARN for testing (default: arn:aws:iam::303467602807:role/terraformer-tester)

### Code Quality
```bash
make format     # Format Terraform and Python code
make lint       # Check code formatting without modifications
make clean      # Remove build artifacts (.pytest_cache, .terraform)
```

### Documentation
```bash
make docs       # Generate module documentation with terraform-docs
```

## Architecture

### Module Structure

The module is organized into focused files by resource type:

- **main.tf**: Core EC2 instance and cloud-init configuration using `infrahouse/cloud-init/aws` module
- **iam.tf**: IAM instance profile with AssumeRole permissions via `infrahouse/instance-profile/aws` module
- **sg.tf**: Security group with SSH and ICMP ingress rules
- **dns.tf**: Route53 A record for the instance
- **cloudwatch.tf**: CPU utilization CloudWatch alarm
- **datasources.tf**: AMI lookup (Ubuntu Pro), VPC/subnet, Route53 zone data sources
- **locals.tf**: Local values for tags and module version
- **variables.tf**: All input variables
- **outputs.tf**: Outputs including instance role ARN/name for trust policies

### Key Design Patterns

1. **IAM Permissions Pattern**: Uses data source `aws_iam_policy_document` (not hardcoded JSON) to build 
   the instance profile permissions. The base policy grants `sts:AssumeRole` and `iam:GetRole` on all resources,
   allowing the Terraformer to assume any role whose trust policy references it. Users can extend permissions 
   via `var.extra_instance_profile_permissions`.

2. **Cloud-Init Integration**: Leverages `infrahouse/cloud-init/aws` module for user data generation. 
   Automatically configures Hashicorp APT repository for Terraform installation and supports Puppet configuration.

3. **Instance Replacement Trigger**: Uses `null_resource.terraformer` with trigger on userdata changes to force 
   instance replacement when configuration changes (main.tf:65-69).

4. **Ubuntu Pro AMI**: Defaults to latest Ubuntu Pro image via data source, but allows override with `var.ami`.

## Critical Coding Standards

**ALWAYS read `.claude/CODING_STANDARD.md` and `.claude/instructions.md` before writing Terraform code.**

Key requirements for this project:

### Validation Blocks
- Use ternary operators (not logical OR) for nullable variable validation to avoid null comparison errors
- Pattern: `condition = var.value == null ? true : var.value <= 100`

### Tagging
- Use lowercase tags except `Name`
- Multi-word tags use underscores (e.g., `created_by_module`)
- Required provenance tags: `created_by`, `created_by_module`
- `module_version` tag on the selected "main" resource (aws_instance.terraformer in this module)

### IAM Policies
- Always use `data "aws_iam_policy_document"` (never hardcoded JSON or jsonencode)
- See iam.tf:6-15 for the pattern used in this module

### Module Dependencies
- Pin all module versions exactly (no ranges)
- Use `registry.infrahouse.com` for InfraHouse modules
- Provider requirements: Only declare providers this module directly uses

## Testing Strategy

This module follows InfraHouse integration testing standards:

- Tests create real infrastructure in AWS
- Parametrized tests for AWS provider v5 and v6 (test_module.py:14-16)
- Uses `pytest-infrahouse` fixtures for Terraform operations
- Test data in `test_data/terraformer/` with dynamically generated `terraform.tf` and `terraform.tfvars`
- State cleanup before each test run to ensure fresh provider initialization (test_module.py:33-46)
- GitHub Actions runs on self-hosted runners (required for ih-registry command)

## Common Workflows

### Adding a New Variable
1. Add to variables.tf with explicit type and description
2. Add validation block if applicable (remember: ternary for nullables)
3. Use in appropriate resource file
4. Run `make format` and `make docs` to update README

### Adding IAM Permissions
- Extend `var.extra_instance_profile_permissions` in caller module
- OR modify the base policy in iam.tf:6-15 (requires module version bump)

### Modifying Cloud-Init Configuration
- Update module.userdata inputs in main.tf:1-38
- Instance will be replaced due to lifecycle trigger (main.tf:65-69)

### Before Submitting PR
1. Run `make format` to format code
2. Run `make lint` to check formatting
3. Run `make test-clean` to validate full cleanup
4. Ensure `.claude/CODING_STANDARD.md` compliance
