# Terraform Module Review: terraform-aws-terraformer

**Review Date:** 2026-01-13
**Changes Reviewed:** .gitignore updates to exclude .claude/reviews/ and .claude/settings.local.json
**Standards Reviewed:** .claude/CODING_STANDARD.md, .claude/instructions.md
**Reference Module:** terraform-aws-pmm-ecs (for EC2 recovery patterns)

## Summary

**Status:** CHANGES_REQUESTED

The module is generally well-structured and follows most InfraHouse coding standards. However, there are several 
critical issues that need to be addressed:

1. **CRITICAL: Missing EC2 Auto-Recovery** - The module lacks EC2 instance auto-recovery configuration, which is essential for high availability
2. **CRITICAL: ICMP Security Rule Violation** - The ICMP rule allows all types from 0.0.0.0/0, violating security standards
3. **CRITICAL: Default Environment Value** - The `environment` variable has a default value, which violates the standard
4. **Missing Validation Blocks** - Several variables lack validation that would catch invalid inputs
5. **CloudWatch Alarm Improvements** - The CPU alarm could be enhanced with better defaults

The .gitignore changes are appropriate and align with standard practices for excluding generated review files and local settings.

**EC2 Recovery Status:** NOT CONFIGURED - Auto-recovery is completely missing from this module.

## Detailed Findings

### Security

#### CRITICAL: ICMP Security Group Rule Violation (sg.tf:28-41)

**Issue:** The ICMP ingress rule allows ALL ICMP types from 0.0.0.0/0, which violates the security standard.

**Current Code:**
```hcl
resource "aws_vpc_security_group_ingress_rule" "icmp" {
  description       = "Allow all ICMP traffic"
  security_group_id = aws_security_group.terraformer.id
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge(
    {
      Name = "ICMP traffic"
    },
    local.tags
  )
}
```

**Standard Requirement (CODING_STANDARD.md:347-350):**
> From internet (0.0.0.0/0): Allow only types 3 (Destination Unreachable), 8 (Echo Request), 0 (Echo Reply), 
> 11 (Time Exceeded). Block all other types

**Required Fix:** Replace with multiple rules allowing only specific ICMP types:
- Type 0 (Echo Reply)
- Type 3 (Destination Unreachable)
- Type 8 (Echo Request)
- Type 11 (Time Exceeded)

For ICMP within VPC (from VPC CIDR), all ICMP types can be allowed.

**Recommendation:** Create separate rules for VPC-internal ICMP (all types) and internet ICMP (specific types only).

#### IAM Policy Implementation - COMPLIANT

The module correctly uses `data "aws_iam_policy_document"` (iam.tf:6-15) instead of hardcoded JSON or jsonencode. 
This follows the standard requirement.

**Compliant Code:**
```hcl
data "aws_iam_policy_document" "permissions" {
  source_policy_documents = var.extra_instance_profile_permissions != null ? [var.extra_instance_profile_permissions] : []
  statement {
    actions = [
      "sts:AssumeRole",
      "iam:GetRole"
    ]
    resources = ["*"]
  }
}
```

### Functionality

#### CRITICAL: Missing EC2 Auto-Recovery Configuration

**Issue:** The module has NO auto-recovery mechanism for EC2 instance failures. This is a critical gap for 
a mission-critical administrative instance.

**Comparison with terraform-aws-pmm-ecs:**
The pmm-ecs module implements comprehensive auto-recovery with:

1. **System Status Check Auto-Recovery** (auto_recovery.tf:5-32)
   - Monitors: `StatusCheckFailed_System` metric
   - Action: `arn:aws:automate:${region}:ec2:recover`
   - Evaluation: 2 periods of 60 seconds
   - Purpose: Recovers from hardware failures

2. **Instance Status Check Auto-Reboot** (auto_recovery.tf:36-66)
   - Monitors: `StatusCheckFailed_Instance` metric
   - Action: `arn:aws:automate:${region}:ec2:reboot`
   - Evaluation: 3 periods of 60 seconds
   - Purpose: Recovers from software failures (OOM, kernel panic)

3. **Combined Status Check Alarm** (auto_recovery.tf:69-93)
   - Monitors: `StatusCheckFailed` metric
   - Action: Notifications only
   - Purpose: General health monitoring

4. **Reboot Loop Detection** (auto_recovery.tf:97-126)
   - Monitors frequent reboots (>2 per hour)
   - Purpose: Detect persistent issues requiring manual intervention

**Current Module Status:**
- The module only has a CPU utilization alarm (cloudwatch.tf:1-16)
- NO auto-recovery actions configured
- NO system or instance status check monitoring

**Impact:**
- **Hardware failures** will NOT trigger automatic recovery
- **Software failures** (OOM, kernel panic) will NOT trigger automatic reboot
- **Extended downtime** for a critical administrative instance
- Manual intervention required for all failure scenarios

**Recommended Implementation:**

Add an `auto_recovery.tf` file with at minimum:

```hcl
# System status check - auto-recover on hardware failure
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

  # Auto-recovery action
  alarm_actions = ["arn:aws:automate:${data.aws_region.current.name}:ec2:recover"]

  tags = merge(
    {
      Name = "terraformer-system-recovery"
      Type = "auto-recovery"
    },
    local.tags
  )
}

# Instance status check - auto-reboot on software failure
resource "aws_cloudwatch_metric_alarm" "terraformer_instance_check" {
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

  # Auto-reboot + notifications
  alarm_actions = concat(
    ["arn:aws:automate:${data.aws_region.current.name}:ec2:reboot"],
    var.sns_topic_alarm_arn != null ? [var.sns_topic_alarm_arn] : []
  )

  tags = merge(
    {
      Name = "terraformer-instance-check"
      Type = "auto-recovery"
    },
    local.tags
  )
}
```

Add variable in `variables.tf`:
```hcl
variable "enable_auto_recovery" {
  description = "Enable EC2 auto-recovery for hardware failures and auto-reboot for software failures"
  type        = bool
  default     = true
}
```

#### CloudWatch Alarm Configuration

**Current Implementation (cloudwatch.tf:1-16):**
- Only monitors CPU utilization
- Only creates alarm if `var.sns_topic_alarm_arn` is provided
- Threshold: 90% CPU
- Evaluation: 1 period of 60 seconds

**Issues:**
1. CPU alarm creation tied to SNS topic availability (count condition)
2. Very short evaluation period (1x60s) - may trigger false positives
3. No monitoring for memory, disk, or instance health

**Recommendations:**
1. Decouple alarm creation from SNS topic (always create, conditionally add actions)
2. Increase evaluation periods to reduce false positives (2x60s minimum)
3. Add instance status check alarms (as mentioned in auto-recovery section)

#### Instance Replacement Trigger - COMPLIANT

The module correctly uses `null_resource.terraformer` with a lifecycle trigger to force instance replacement 
when userdata changes (main.tf:65-76). This is a good pattern.

### Best Practices

#### File Organization - EXCELLENT

The module is well-organized into logical files:
- `main.tf`: Core EC2 and userdata configuration
- `iam.tf`: IAM policies and profiles
- `sg.tf`: Security group rules
- `dns.tf`: Route53 DNS record
- `cloudwatch.tf`: CloudWatch alarms
- `datasources.tf`: Data sources
- `locals.tf`: Local values
- `variables.tf`: Input variables
- `outputs.tf`: Output values

This follows the standard requirement (CODING_STANDARD.md:318-324).

#### Module Version Pinning - COMPLIANT

All modules use exact version pinning:
- `infrahouse/cloud-init/aws` version `2.2.2`
- `infrahouse/instance-profile/aws` version `1.9.0`
- Uses `registry.infrahouse.com` for InfraHouse modules

This follows the standard requirement (CODING_STANDARD.md:160-187).

#### Provider Requirements - COMPLIANT

The module declares only the providers it directly uses:
- `aws` (for EC2, security groups, CloudWatch, Route53)
- `null` (for null_resource trigger)
- `random` (for random_string in IAM profile)

This follows the standard requirement (CODING_STANDARD.md:156-159).

#### Resource Naming - COMPLIANT

Resources follow snake_case naming:
- `aws_instance.terraformer`
- `aws_security_group.terraformer`
- `aws_route53_record.terraformer`
- `null_resource.terraformer`

For single resources of a type, the module uses descriptive names or "this" pattern appropriately.

#### Metadata Options - COMPLIANT (main.tf:61-64)

The instance correctly requires IMDSv2:
```hcl
metadata_options {
  http_tokens   = "required"
  http_endpoint = "enabled"
}
```

This is a security best practice.

### Code Standards Compliance

#### CRITICAL: Environment Variable Default Value (variables.tf:13-17)

**Issue:** The `environment` variable has a default value of `"development"`, which violates the coding standard.

**Current Code:**
```hcl
variable "environment" {
  description = "Puppet environment."
  type        = string
  default     = "development"
}
```

**Standard Requirement (CODING_STANDARD.md:508-510):**
> Require environment tag from user - Do not provide defaults
> - Prevents nonsense like `environment=dev` in production AWS accounts
> - Forces explicit environment declaration, bringing order and preventing deployment mistakes

**Required Fix:** Remove the default value:
```hcl
variable "environment" {
  description = "Puppet environment."
  type        = string
}
```

Also add validation:
```hcl
variable "environment" {
  description = "Puppet environment."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.environment))
    error_message = "environment must contain only lowercase letters, numbers, and underscores (no hyphens). Got: ${var.environment}"
  }
}
```

#### Missing Validation Blocks

Several variables lack validation that would catch invalid inputs:

1. **root_volume_size (variables.tf:97-101)** - Should validate >= 8 (minimum for Ubuntu)
2. **instance_type (variables.tf:49-53)** - Consider validating it's not empty
3. **dns_name (variables.tf:7-11)** - Should validate DNS naming rules
4. **ubuntu_codename (variables.tf:119-123)** - Could validate against known Ubuntu releases

**Recommended additions:**

```hcl
variable "root_volume_size" {
  description = "Disk size in GB mounted as the root volume"
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GB for Ubuntu. Got: ${var.root_volume_size}"
  }
}

variable "dns_name" {
  description = "Hostname of the Terraformer in zone var.zone_id."
  type        = string
  default     = "terraformer"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.dns_name))
    error_message = "dns_name must be a valid DNS label (lowercase letters, numbers, and hyphens). Got: ${var.dns_name}"
  }
}
```

#### Tagging - COMPLIANT

The module follows tagging standards:

**locals.tf (lines 4-9):**
```hcl
tags = {
  environment : var.environment
  service : "terraformer"
  account : data.aws_caller_identity.current.account_id
  created_by_module : "infrahouse/terraformer/aws"
}
```

**Compliance:**
- Uses lowercase tags (except `Name`)
- Uses underscores for multi-word tags (`created_by_module`)
- Includes `created_by_module` provenance tag
- `module_version` tag on main resource (aws_instance.terraformer)
- `environment` required from user (though currently has default - needs fix)

**Note:** The `created_by` tag is typically set at the provider level in the root module's provider configuration, which is correct.

#### Line Length - COMPLIANT

All files appear to follow the 120-character maximum line length requirement.

#### Documentation - COMPLIANT

The README.md includes:
- Terraform-docs auto-generated sections
- Module description
- Usage examples
- Proper formatting

However, missing badges as mentioned in standard (CODING_STANDARD.md:294-301):
- Should include: Terraform Registry URL, License, CD status badges

### EC2 Recovery

#### Current Status: NOT IMPLEMENTED

The module has NO auto-recovery configured. This is a critical gap.

#### Comparison with terraform-aws-pmm-ecs

The pmm-ecs module implements a comprehensive 4-tier recovery strategy:

1. **Hardware Failure Recovery** - Automatic EC2 recovery
2. **Software Failure Recovery** - Automatic instance reboot
3. **Health Monitoring** - Combined status check alerting
4. **Reboot Loop Detection** - Prevents infinite reboot cycles

**Key Differences:**

| Feature | pmm-ecs | terraformer | Impact |
|---------|---------|-------------|--------|
| System status check auto-recovery | ✅ Yes | ❌ No | Critical - hardware failures require manual intervention |
| Instance status check auto-reboot | ✅ Yes | ❌ No | Critical - software failures require manual intervention |
| Configurable recovery (enable_auto_recovery) | ✅ Yes | ❌ No | No way to enable/disable |
| Reboot loop detection | ✅ Yes | ❌ No | No protection against infinite reboot cycles |
| Detailed monitoring option | ✅ Yes | ❌ No | No memory/disk monitoring available |
| CloudWatch dashboard | ✅ Yes | ❌ No | No centralized monitoring view |

**PMM-ECS Pattern Analysis:**

The pmm-ecs module uses:
- `count = var.enable_auto_recovery ? 1 : 0` for conditional creation
- Separate alarms for system and instance checks
- Different evaluation periods (2 for system, 3 for instance)
- Auto-recovery ARN: `arn:aws:automate:${region}:ec2:recover`
- Auto-reboot ARN: `arn:aws:automate:${region}:ec2:reboot`
- Comprehensive tagging with Type field
- Combined alarm actions (reboot + SNS notifications)

**Critical Gap:**

The Terraformer is described as a "dedicated EC2 instance for administrative Terraform operations" used 
for "fixing corrupted state" and "cross-account operations". This is a **critical infrastructure component** 
that should have auto-recovery enabled.

Without auto-recovery:
- Hardware failures result in extended downtime
- Software failures (OOM during large Terraform operations) require manual intervention
- No automated response to instance health issues
- Potential disruption to critical administrative operations

#### Recommendations for Implementation

**High Priority:**
1. Add `auto_recovery.tf` with system and instance status check alarms
2. Add `enable_auto_recovery` variable (default: true)
3. Implement auto-recovery action for hardware failures
4. Implement auto-reboot action for software failures

**Medium Priority:**
5. Add combined status check alarm for general monitoring
6. Add reboot loop detection

**Optional Enhancements:**
7. Add detailed monitoring (memory, disk) if needed
8. Add CloudWatch dashboard for centralized monitoring

### .gitignore Changes - APPROVED

The changes to .gitignore are appropriate:

```diff
+.claude/reviews/
+.claude/settings.local.json
```

**Rationale:**
- `.claude/reviews/` - Contains generated review files that shouldn't be committed
- `.claude/settings.local.json` - Local settings that may contain user-specific configuration

These exclusions align with standard practices for excluding generated and local configuration files.

## Recommendations

### Critical (Must Fix Before Release)

1. **Remove default value from `environment` variable**
   - File: `variables.tf:13-17`
   - Action: Remove `default = "development"`
   - Add validation for environment name format

2. **Fix ICMP security group rule**
   - File: `sg.tf:28-41`
   - Action: Replace with separate rules for VPC ICMP (all types) and internet ICMP (types 0, 3, 8, 11 only)

3. **Implement EC2 auto-recovery**
   - Create new file: `auto_recovery.tf`
   - Add `enable_auto_recovery` variable
   - Implement system status check alarm with auto-recovery action
   - Implement instance status check alarm with auto-reboot action

### High Priority (Should Fix)

4. **Add variable validations**
   - `root_volume_size`: minimum 8 GB
   - `dns_name`: valid DNS label format
   - Consider others as appropriate

5. **Improve CPU alarm configuration**
   - File: `cloudwatch.tf:1-16`
   - Decouple alarm creation from SNS topic availability
   - Increase evaluation periods to 2 (reduce false positives)

6. **Add README badges**
   - Terraform Registry URL
   - License
   - CD status
   - Relevant AWS service badges

### Medium Priority (Nice to Have)

7. **Add reboot loop detection alarm**
   - Following pmm-ecs pattern
   - Detect frequent instance failures

8. **Consider detailed monitoring option**
   - Add `enable_detailed_monitoring` variable
   - Optional memory and disk usage alarms

9. **Add inline comments**
   - Explain why ICMP is allowed from 0.0.0.0/0 (with specific types)
   - Document the instance replacement trigger pattern

### Low Priority (Future Enhancements)

10. **CloudWatch dashboard**
    - Optional centralized monitoring view
    - Following pmm-ecs pattern

11. **Additional outputs**
    - Consider outputting security group ID
    - Private IP address (already in DNS, but might be useful)

## Conclusion

The terraform-aws-terraformer module is well-structured and follows most InfraHouse coding standards. 
The code organization, module version pinning, IAM policy implementation, and resource naming are all compliant.

However, there are **three critical issues** that must be addressed:

1. **Missing EC2 auto-recovery** - This is the most significant gap. For a critical administrative instance, auto-recovery is essential.
2. **ICMP security rule violation** - Violates security standard by allowing all ICMP types from internet.
3. **Environment variable default** - Violates standard and can lead to deployment mistakes.

The .gitignore changes are appropriate and approved.

**Recommendation:** Address all critical issues before merging or releasing a new version. The high-priority items 
should also be addressed to improve the module's robustness and compliance with standards.
