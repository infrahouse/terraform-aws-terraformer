# Implementation Plan: terraform-aws-terraformer Critical Fixes

**Plan Date:** 2026-01-13
**Based On:** `.claude/reviews/terraform-module-review.md`

## Overview

This plan addresses the 3 critical issues and high-priority improvements identified in the module review.

## Critical Issues

### 1. ICMP Security Rule - Restrict to VPC CIDR Only ✅ DONE

**File:** `sg.tf:28-41`

**Issue:** Terraformer is an internal service and should not be exposed to public networks.

**Implementation:**
- Change `cidr_ipv4` from `"0.0.0.0/0"` to `data.aws_vpc.selected.cidr_block`
- Update description from `"Allow all ICMP traffic"` to `"Allow ICMP traffic from VPC"`
- Keep all ICMP types (`from_port = -1, to_port = -1`) - acceptable for VPC-internal traffic
- Pattern matches existing SSH rule (sg.tf:19)

**Note:** The review document suggests splitting into VPC rules (all types) and internet rules (specific types only), 
but since terraformer is internal, we only need VPC access.

### 2. Environment Variable Default Value ✅ DONE

**File:** `variables.tf:13-17`

**Issue:** Has default value `"development"` which violates coding standard and can cause deployment mistakes.

**Implementation:**
```hcl
variable "environment" {
  description = "Puppet environment."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.environment))
    error_message = "environment must contain only lowercase letters, numbers, and underscores (no hyphens)"
  }
}
```

### 3. Missing EC2 Auto-Recovery Configuration ✅ DONE

**New File:** `auto_recovery.tf`

**Issue:** No auto-recovery mechanism for hardware or software failures on this critical administrative instance.

**Implementation:**

#### New Variable (variables.tf)
```hcl
variable "enable_auto_recovery" {
  description = "Enable EC2 auto-recovery for hardware failures and auto-reboot for software failures"
  type        = bool
  default     = true
}
```

#### System Status Check Alarm (auto_recovery.tf)
```hcl
resource "aws_cloudwatch_metric_alarm" "terraformer_system_auto_recovery" {
  count               = var.enable_auto_recovery ? 1 : 0
  alarm_name          = "terraformer-system-auto-recovery-${aws_instance.terraformer.id}"
  alarm_description   = "Auto recover Terraformer instance when underlying hardware fails"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0.5
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    InstanceId = aws_instance.terraformer.id
  }

  alarm_actions = ["arn:aws:automate:${data.aws_region.current.name}:ec2:recover"]

  tags = merge(
    {
      Name = "terraformer-system-recovery"
    },
    local.tags
  )
}
```

**Note:** Removed `Type = "auto-recovery"` tag - violates lowercase standard and is redundant.

#### Instance Status Check Alarm (auto_recovery.tf)
```hcl
resource "aws_cloudwatch_metric_alarm" "terraformer_instance_check" {
  count               = var.enable_auto_recovery ? 1 : 0
  alarm_name          = "terraformer-instance-status-check-${aws_instance.terraformer.id}"
  alarm_description   = "Auto-reboot Terraformer instance on status check failures"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0.5
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    InstanceId = aws_instance.terraformer.id
  }

  alarm_actions = concat(
    ["arn:aws:automate:${data.aws_region.current.name}:ec2:reboot"],
    var.sns_topic_alarm_arn != null ? [var.sns_topic_alarm_arn] : []
  )

  tags = merge(
    {
      Name = "terraformer-instance-check"
    },
    local.tags
  )
}
```

## High Priority Improvements

### 4. Add Variable Validations ✅ DONE

**File:** `variables.tf`

#### root_volume_size validation
```hcl
variable "root_volume_size" {
  description = "Disk size in GB mounted as the root volume"
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GB for Ubuntu"
  }
}
```

#### dns_name validation
```hcl
variable "dns_name" {
  description = "Hostname of the Terraformer in zone var.zone_id."
  type        = string
  default     = "terraformer"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.dns_name))
    error_message = "dns_name must be a valid DNS label (lowercase letters, numbers, and hyphens)"
  }
}
```

### 5. Auto-Generate SSH Key with Rotation ✅ DONE

**Pattern:** Follow bookstack module SMTP key rotation pattern for emergency/bootstrap SSH access.

**Rationale:**
- Puppet provisions user accounts - this key is for emergency/bootstrap access only
- Auto-rotation is more secure than distributing static shared keys to all Terraform admins
- State is treated as secret with appropriate access controls and encryption

#### Make ssh_key_name optional (variables.tf)

```hcl
variable "ssh_key_name" {
  description = "SSH key name installed in the Terraformer instance. If not provided, a key pair will be auto-generated and rotated."
  type        = string
  default     = null
}

variable "ssh_key_rotation_days" {
  description = "Number of days before SSH key rotation when auto-generated"
  type        = number
  default     = 90

  validation {
    condition     = var.ssh_key_rotation_days > 0
    error_message = "ssh_key_rotation_days must be greater than 0"
  }
}
```

#### Create SSH key generation file (ssh_key.tf)

```hcl
# Time-based rotation trigger
resource "time_rotating" "ssh_key_rotation" {
  count         = var.ssh_key_name == null ? 1 : 0
  rotation_days = var.ssh_key_rotation_days
}

# Static time resource to properly trigger replacement
# Workaround for https://github.com/hashicorp/terraform-provider-time/issues/118
resource "time_static" "ssh_key_rotation" {
  count   = var.ssh_key_name == null ? 1 : 0
  rfc3339 = time_rotating.ssh_key_rotation[0].rfc3339
}

# Generate SSH key pair
resource "tls_private_key" "terraformer" {
  count     = var.ssh_key_name == null ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096

  lifecycle {
    replace_triggered_by = [
      time_static.ssh_key_rotation[0]
    ]
    create_before_destroy = true
  }
}

# Upload public key to AWS
resource "aws_key_pair" "terraformer" {
  count      = var.ssh_key_name == null ? 1 : 0
  key_name   = "terraformer-${data.aws_caller_identity.current.account_id}"
  public_key = tls_private_key.terraformer[0].public_key_openssh

  tags = merge(
    {
      Name = "terraformer-auto-generated"
    },
    local.tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Store private key in Secrets Manager for emergency access
resource "aws_secretsmanager_secret" "terraformer_ssh_key" {
  count       = var.ssh_key_name == null ? 1 : 0
  name        = "terraformer-ssh-private-key-${data.aws_caller_identity.current.account_id}"
  description = "Auto-generated SSH private key for Terraformer emergency access"

  tags = merge(
    {
      Name = "terraformer-ssh-key"
    },
    local.tags
  )
}

resource "aws_secretsmanager_secret_version" "terraformer_ssh_key" {
  count         = var.ssh_key_name == null ? 1 : 0
  secret_id     = aws_secretsmanager_secret.terraformer_ssh_key[0].id
  secret_string = tls_private_key.terraformer[0].private_key_openssh
}
```

#### Update main.tf to use conditional key

```hcl
key_name = var.ssh_key_name != null ? var.ssh_key_name : aws_key_pair.terraformer[0].key_name
```

#### Add output for key retrieval instructions (outputs.tf)

```hcl
output "ssh_key_secret_arn" {
  description = "ARN of Secrets Manager secret containing auto-generated SSH private key (if applicable)"
  value       = var.ssh_key_name == null ? aws_secretsmanager_secret.terraformer_ssh_key[0].arn : null
}
```

**Benefits:**
- Emergency access available without distributing keys to all admins
- Automatic rotation improves security posture
- Private key retrievable via Secrets Manager with IAM controls
- Backwards compatible - users can still provide their own key

### 6. Add CloudWatch Log Group and Puppet Custom Facts ✅ DONE

**Pattern:** Follow jumphost module pattern for CloudWatch integration with Puppet.

#### Create CloudWatch Log Group

**New File:** `cloudwatch_logs.tf`

```hcl
resource "aws_cloudwatch_log_group" "terraformer" {
  name              = "/aws/ec2/terraformer/${aws_instance.terraformer.id}"
  retention_in_days = var.cloudwatch_log_retention

  tags = merge(
    {
      Name = "terraformer-logs"
    },
    local.tags
  )
}
```

#### Add Variables (variables.tf)

```hcl
variable "cloudwatch_namespace" {
  description = "CloudWatch namespace for custom metrics"
  type        = string
  default     = "terraformer"
}

variable "cloudwatch_log_retention" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention)
    error_message = "cloudwatch_log_retention must be a valid CloudWatch Logs retention period"
  }
}

variable "puppet_custom_facts" {
  description = "Custom facts for Puppet (will be merged with terraformer-specific facts)"
  type        = map(any)
  default     = {}
}
```

#### Update main.tf custom_facts

**Current (main.tf:32-36):**
```hcl
custom_facts = var.smtp_credentials_secret != null ? {
  postfix : {
    smtp_credentials : var.smtp_credentials_secret
  }
} : {}
```

**New Implementation:**
```hcl
custom_facts = merge(
  var.puppet_custom_facts,
  {
    terraformer = merge(
      {
        cloudwatch_log_group = aws_cloudwatch_log_group.terraformer.name
        cloudwatch_namespace = var.cloudwatch_namespace
      },
      lookup(var.puppet_custom_facts, "terraformer", {})
    )
  },
  var.smtp_credentials_secret != null ? {
    postfix = {
      smtp_credentials = var.smtp_credentials_secret
    }
  } : {}
)
```

**Benefits:**
- Puppet can configure CloudWatch Logs agent automatically
- Custom metrics can use the namespace
- Preserves any existing "terraformer" facts from caller
- Maintains backward compatibility with smtp_credentials

## Testing Plan

1. **Format and Lint**
   ```bash
   make format
   make lint
   ```

2. **Integration Tests**
   ```bash
   make test
   ```
   - Verify instance creation
   - Verify auto-recovery alarms created (when enabled)
   - Verify ICMP rule uses VPC CIDR
   - Test with both AWS provider v5 and v6

3. **Manual Verification**
   - Check CloudWatch console for alarms
   - Verify security group rules in AWS console
   - Confirm no default environment value

## Implementation Order

1. ✅ Update `sg.tf` - ICMP rule restriction
2. ✅ Update `variables.tf` - Remove environment default, add validations, add new variables
3. ✅ Create `auto_recovery.tf` - Add auto-recovery alarms (always enabled)
4. ✅ Create `ssh_key.tf` - Add auto-generated SSH key with rotation
5. ✅ Update `main.tf` - Use conditional key_name
6. ✅ Create `cloudwatch_logs.tf` - Add CloudWatch log group
7. ✅ Update `main.tf` - Update custom_facts with CloudWatch integration
8. ✅ Update `outputs.tf` - Add SSH key secret ARN output
9. Run `make format`
10. Run `make lint`
11. Run `make test`
12. Update `README.md` if needed (via `make docs`)

## Expected Outcomes

- ICMP traffic restricted to VPC CIDR only
- Environment variable requires explicit declaration
- Auto-recovery enabled by default for both hardware and software failures
- Variable validations prevent common configuration errors
- SSH key auto-generated with 90-day rotation if not provided by user
- Private key stored in Secrets Manager for emergency access
- CloudWatch log group created for instance logs
- Puppet custom facts include CloudWatch configuration
- All tests pass with both AWS provider versions
