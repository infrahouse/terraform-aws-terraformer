# Getting Started

This guide walks you through deploying your first Terraformer instance using the InfraHouse module.

## Prerequisites

### AWS Resources

Before deploying, you need:

1. **VPC with a private subnet** — Terraformer should be in a private subnet with NAT gateway access
2. **Route53 hosted zone** — For creating DNS record

### Puppet Setup

**No manual setup required!** The module automatically provides all Puppet components:

- **Puppet code** installed from InfraHouse public APT repository
- **Terraformer role and profile** included out of the box
- **Configuration management** via cloud-init bootstrap

The `infrahouse/cloud-init/aws` module handles the entire Puppet bootstrap process automatically. You only need to specify the `environment` variable (e.g., `production`, `development`).

For details on how the Puppet bootstrap works, see [Puppet Bootstrap](architecture.md#puppet-bootstrap) in the Architecture documentation

## Basic Deployment

### Step 1: Create the Module Configuration

```hcl
module "terraformer" {
  source  = "registry.infrahouse.com/infrahouse/terraformer/aws"
  version = "~> 2.0"

  # Required
  environment  = "production"
  zone_id      = data.aws_route53_zone.main.zone_id
  subnet       = data.aws_subnet.private.id
  alarm_emails = ["ops-team@example.com"]

  # Sizing
  instance_type    = "t3a.medium"
  root_volume_size = 50
}
```

!!! warning "Email Confirmation Required"
    After deployment, AWS SNS sends confirmation emails to each address in `alarm_emails`. Recipients **MUST** click the confirmation link to receive alarm notifications.

### Step 2: Configure IAM Trust Relationships (Optional)

If you need cross-account access, configure trust relationships in target accounts. Reference the terraformer's instance role ARN (available from `terraform output instance_role_arn` after deployment):

```hcl
# In target AWS account
resource "aws_iam_role" "cross_account_admin" {
  name = "terraformer-cross-account-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # Get this from: terraform output instance_role_arn
        AWS = "arn:aws:iam::SOURCE_ACCOUNT:role/terraformer-XXXXXXXXXXXX"
      }
      Action = "sts:AssumeRole"
    }]
  })

  # Attach policies as needed
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AdministratorAccess"
  ]
}
```

!!! tip "Automating Role ARN Lookup"
    Instead of hardcoding the ARN, you can use `terraform_remote_state`, SSM parameters, or any other method your organization prefers for sharing values across configurations.

### Step 3: Deploy

```bash
terraform init
terraform plan
terraform apply
```

After apply completes, the instance will:

1. Launch in your specified subnet
2. Register DNS record (default: `terraformer.your-domain.com`)
3. Bootstrap with Puppet
4. Create auto-recovery alarms
5. Generate and store SSH key in Secrets Manager

## Accessing the Terraformer

### Using Auto-Generated SSH Key

=== "Retrieve Private Key"

    ```bash
    # Get the secret ARN from Terraform output
    SECRET_ARN=$(terraform output -raw ssh_key_secret_arn)

    # Download private key
    aws secretsmanager get-secret-value \
      --secret-id "$SECRET_ARN" \
      --query SecretString \
      --output text > ~/.ssh/terraformer.pem

    # Set proper permissions
    chmod 600 ~/.ssh/terraformer.pem
    ```

=== "SSH to Instance"

    ```bash
    # Using DNS name
    ssh -i ~/.ssh/terraformer.pem ubuntu@terraformer.your-domain.com

    # Or using hostname output
    HOSTNAME=$(terraform output -raw hostname)
    ssh -i ~/.ssh/terraformer.pem ubuntu@"$HOSTNAME"
    ```

### Using Your Own SSH Key

If you prefer to use your own SSH key:

```hcl
module "terraformer" {
  source  = "registry.infrahouse.com/infrahouse/terraformer/aws"
  version = "~> 2.0"

  environment  = "production"
  zone_id      = data.aws_route53_zone.main.zone_id
  subnet       = data.aws_subnet.private.id
  alarm_emails = ["ops-team@example.com"]

  # Use existing SSH key
  ssh_key_name = "my-existing-key"
}
```

## Verifying the Deployment

### Check Instance Status

```bash
# Get instance ID
INSTANCE_ID=$(terraform output -raw instance_id)

# Check instance is running
aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name'
```

### Check Auto-Recovery Alarms

```bash
# List CloudWatch alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix "terraformer"
```

You should see two alarms:
- `terraformer-system-auto-recovery-*` (hardware failures)
- `terraformer-instance-status-check-*` (software failures)

### Check CloudWatch Logs

```bash
# Get log group name
LOG_GROUP=$(terraform output -raw cloudwatch_log_group_name)

# List log streams
aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --order-by LastEventTime \
  --descending
```

## First Operations

Once connected to the terraformer instance:

### Verify Terraform Installation

```bash
terraform version
```

### Configure AWS Profile for Cross-Account Access

```bash
cat >> ~/.aws/config <<EOF
[profile target-account]
role_arn = arn:aws:iam::123456789012:role/terraformer-cross-account-admin
source_profile = default
region = us-west-2
EOF
```

### Test Cross-Account Access

```bash
aws sts get-caller-identity --profile target-account
```

## Next Steps

- [Configure additional IAM permissions](security.md#iam-permissions)
- [Set up CloudWatch monitoring](cloudwatch.md)
- [Configure Puppet for custom software](configuration.md#puppet-configuration)
- [Review security best practices](security.md)