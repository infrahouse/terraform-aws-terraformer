# InfraHouse Terraformer

This Terraform module creates a dedicated EC2 instance ("Terraformer") for administrative Terraform operations in AWS. The Terraformer is designed for elevated-permission operations like fixing corrupted state, migrations, and cross-account operations via AssumeRole.

## Why Use a Dedicated Terraformer Instance?

### Design Philosophy

| Aspect | Terraformer | CI/CD Pipelines | Local Workstations |
|--------|-------------|-----------------|---------------------|
| **Access** | Centralized, auditable | Distributed across workflows | Distributed across developers |
| **State Access** | Direct, for emergency fixes | Restricted | Restricted |
| **Permissions** | Elevated via AssumeRole | Limited to deployment scopes | Variable, hard to audit |
| **Audit Trail** | CloudWatch Logs | CI/CD logs | None |
| **Network** | VPC-internal, secure | Often requires external access | External, varies |

### Key Advantages

- **Emergency Operations**: Direct state access for fixing corrupted Terraform state
- **Cross-Account Operations**: AssumeRole capabilities for multi-account management
- **Security**: VPC-internal instance with auto-rotating SSH keys
- **Auditability**: CloudWatch Logs integration for compliance
- **Reliability**: Auto-recovery from hardware and software failures

## Features

- **EC2 Instance** with Ubuntu Pro AMI
- **Auto-Recovery** with CloudWatch alarms for hardware/software failures
- **Auto-Rotating SSH Keys** with 90-day rotation (stored in Secrets Manager)
- **CloudWatch Integration** for logs and custom metrics
- **IAM Profile** with AssumeRole permissions for cross-account operations
- **VPC Security** with restricted ICMP and SSH access
- **Puppet Integration** for instance configuration
- **DNS Record** in Route53 for easy access

## Quick Start

```hcl
module "terraformer" {
  source  = "registry.infrahouse.com/infrahouse/terraformer/aws"
  version = "1.0.1"

  # Required
  environment  = "production"
  zone_id      = "Z1234567890ABC"
  subnet       = "subnet-abc123"
  alarm_emails = ["ops-team@example.com"]

  # Optional customization
  instance_type    = "t3a.medium"
  root_volume_size = 50
  dns_name         = "terraformer"
}
```

## Documentation

- [Getting Started](getting-started.md) — Prerequisites and first deployment
- [Architecture](architecture.md) — How the module works
- [Configuration](configuration.md) — All available options
- [Security](security.md) — SSH keys, IAM permissions, and auto-recovery
- [CloudWatch](cloudwatch.md) — Logs, metrics, and alarms
- [Troubleshooting](troubleshooting.md) — Common issues and solutions

## Use Cases

### Emergency State Recovery

When Terraform state becomes corrupted or locked:

1. SSH to the terraformer instance
2. Download state backup from S3
3. Fix state issues directly
4. Upload corrected state

### Cross-Account Deployments

For deploying resources across multiple AWS accounts:

1. Configure AssumeRole trust relationships
2. SSH to terraformer with proper credentials
3. Use assumed role for cross-account operations
4. All operations logged to CloudWatch

### Migration Operations

For complex infrastructure migrations:

1. Use terraformer as staging area for state manipulation
2. Run migration scripts with elevated permissions
3. Monitor progress via CloudWatch Logs
4. Audit trail maintained automatically
