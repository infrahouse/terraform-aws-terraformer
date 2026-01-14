# Configuration

This document describes all configuration options available in the Terraformer module.

## Required Variables

### `environment`

**Type:** `string`

**Description:** Puppet environment (e.g., `production`, `development`, `staging`).

**Validation:** Must contain only lowercase letters, numbers, and underscores (no hyphens).

```hcl
environment = "production"
```

!!! warning "No Default Value"
    This variable has no default and must be explicitly set. This prevents deployment mistakes like deploying `development` configuration to production accounts.

### `zone_id`

**Type:** `string`

**Description:** Route53 hosted zone ID where the DNS record will be created.

```hcl
zone_id = "Z1234567890ABC"
```

### `subnet`

**Type:** `string`

**Description:** Subnet ID where the terraformer instance will be launched. Should be a private subnet with NAT gateway access.

```hcl
subnet = "subnet-abc123def456"
```

### `alarm_emails`

**Type:** `list(string)`

**Description:** List of email addresses to receive CloudWatch alarm notifications.

```hcl
alarm_emails = [
  "ops-team@example.com",
  "oncall@example.com"
]
```

!!! warning "Email Confirmation Required"
    AWS SNS will send a confirmation email to each address. Recipients **MUST** click the confirmation link to activate notifications. Unconfirmed subscriptions will not receive alerts.

## Instance Configuration

### `instance_type`

**Type:** `string`
**Default:** `"t3a.medium"`

**Description:** EC2 instance type.

```hcl
instance_type = "t3a.large"  # For heavier workloads
```

### `ami`

**Type:** `string`
**Default:** `null` (uses latest Ubuntu Pro LTS)

**Description:** AMI ID to use. If not provided, the latest Ubuntu Pro AMI will be used.

```hcl
ami = "ami-0123456789abcdef"
```

### `root_volume_size`

**Type:** `number`
**Default:** `8`

**Description:** Root EBS volume size in GB.

**Validation:** Must be at least 8 GB.

```hcl
root_volume_size = 50
```

### `ubuntu_codename`

**Type:** `string`
**Default:** `"noble"` (Ubuntu 24.04 LTS)

**Description:** Ubuntu release codename.

```hcl
ubuntu_codename = "jammy"  # Ubuntu 22.04 LTS
```

## Network Configuration

### `dns_name`

**Type:** `string`
**Default:** `"terraformer"`

**Description:** Hostname in the Route53 zone.

**Validation:** Must be a valid DNS label (lowercase letters, numbers, and hyphens).

```hcl
dns_name = "tf-admin"
```

## SSH Key Configuration

### `ssh_key_name`

**Type:** `string`
**Default:** `null` (auto-generate key)

**Description:** SSH key pair name. If not provided, a key will be auto-generated with rotation.

```hcl
# Use existing key
ssh_key_name = "my-existing-key"

# Or omit for auto-generation
# ssh_key_name = null
```

### `ssh_key_rotation_days`

**Type:** `number`
**Default:** `90`

**Description:** Number of days before auto-generated SSH key rotation.

**Validation:** Must be greater than 0.

**Note:** Only applies when `ssh_key_name` is `null`.

```hcl
ssh_key_rotation_days = 30  # Rotate monthly
```

### `ssh_key_readers`

**Type:** `list(string)`
**Default:** `null`

**Description:** List of IAM role/user ARNs allowed to read the auto-generated SSH private key from Secrets Manager.

**Note:** Only applies when `ssh_key_name` is `null`.

```hcl
ssh_key_readers = [
  "arn:aws:iam::123456789012:role/DevOpsTeam",
  "arn:aws:iam::123456789012:user/admin"
]
```

## IAM Configuration

### `extra_instance_profile_permissions`

**Type:** `string` (JSON policy document)
**Default:** `null`

**Description:** Additional IAM permissions for the instance profile. Merged with base permissions.

```hcl
extra_instance_profile_permissions = jsonencode({
  Version = "2012-10-17"
  Statement = [
    {
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject"
      ]
      Resource = "arn:aws:s3:::my-terraform-states/*"
    }
  ]
})
```

!!! tip "Use Data Sources"
    Instead of `jsonencode`, use `data "aws_iam_policy_document"` for better maintainability:
    ```hcl
    data "aws_iam_policy_document" "extra_permissions" {
      statement {
        actions = ["s3:GetObject", "s3:PutObject"]
        resources = ["arn:aws:s3:::my-terraform-states/*"]
      }
    }

    module "terraformer" {
      # ...
      extra_instance_profile_permissions = data.aws_iam_policy_document.extra_permissions.json
    }
    ```

## CloudWatch Configuration

### `cloudwatch_namespace`

**Type:** `string`
**Default:** `"Terraformer/System"`

**Description:** CloudWatch namespace for custom metrics. Convention: `Service/Component`.

```hcl
cloudwatch_namespace = "Terraformer/System"  # Default
```

### `cloudwatch_log_retention`

**Type:** `number`
**Default:** `365`

**Description:** CloudWatch log group retention in days.

**Validation:** Must be a valid CloudWatch Logs retention period (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653).

```hcl
cloudwatch_log_retention = 90  # 3 months
```

## Puppet Configuration

### `puppet_debug_logging`

**Type:** `bool`
**Default:** `false`

**Description:** Enable Puppet debug logging.

```hcl
puppet_debug_logging = true
```

### `puppet_custom_facts`

**Type:** `map(any)`
**Default:** `{}`

**Description:** Custom facts for Puppet. Merged with terraformer-specific facts (CloudWatch configuration).

```hcl
puppet_custom_facts = {
  datacenter = "us-west-2a"
  tier       = "admin"
}
```

### `puppet_environmentpath`

**Type:** `string`
**Default:** `"{root_directory}/environments"`

**Description:** Puppet environmentpath configuration.

### `puppet_hiera_config_path`

**Type:** `string`
**Default:** `"{root_directory}/environments/{environment}/hiera.yaml"`

**Description:** Path to Puppet Hiera configuration file.

### `puppet_manifest`

**Type:** `string`
**Default:** `"/opt/puppet-code/environments/{environment}/manifests/site.pp"`

**Description:** Path to Puppet manifest file.

### `puppet_module_path`

**Type:** `string`
**Default:** `"{root_directory}/modules"`

**Description:** Puppet module path configuration.

### `puppet_root_directory`

**Type:** `string`
**Default:** `"/opt/puppet-code"`

**Description:** Puppet root directory.

## Advanced Configuration

### `packages`

**Type:** `list(string)`
**Default:** `[]`

**Description:** Additional APT packages to install.

```hcl
packages = [
  "jq",
  "tmux",
  "vim"
]
```

### `extra_files`

**Type:** `map(object)`
**Default:** `{}`

**Description:** Additional files to create on the instance.

```hcl
extra_files = {
  "/etc/custom-config.json" = {
    content     = jsonencode({ setting = "value" })
    permissions = "0644"
  }
}
```

### `extra_repos`

**Type:** `map(object)`
**Default:** `{}`

**Description:** Additional APT repositories to configure.

```hcl
extra_repos = {
  docker = {
    source = "deb [signed-by=$KEY_FILE] https://download.docker.com/linux/ubuntu ${var.ubuntu_codename} stable"
    key    = file("${path.module}/docker-gpg-key")
  }
}
```

### `smtp_credentials_secret`

**Type:** `string`
**Default:** `null`

**Description:** AWS Secrets Manager secret name containing SMTP credentials for Postfix.

```hcl
smtp_credentials_secret = "smtp-credentials"
```

## Complete Example

```hcl
module "terraformer" {
  source  = "registry.infrahouse.com/infrahouse/terraformer/aws"
  version = "~> 2.0"

  # Required
  environment  = "production"
  zone_id      = "Z1234567890ABC"
  subnet       = "subnet-abc123def456"
  alarm_emails = ["ops-team@example.com"]

  # Instance
  instance_type    = "t3a.large"
  root_volume_size = 100

  # Network
  dns_name = "tf-admin"

  # SSH Key (auto-generated with custom rotation)
  ssh_key_rotation_days = 30
  ssh_key_readers = [
    "arn:aws:iam::123456789012:role/DevOpsTeam"
  ]

  # CloudWatch
  cloudwatch_log_retention = 365

  # Puppet
  puppet_custom_facts = {
    datacenter = "us-west-2a"
    tier       = "admin"
  }

  # Additional packages
  packages = ["jq", "tmux", "vim"]

  # Extra IAM permissions
  extra_instance_profile_permissions = data.aws_iam_policy_document.extra.json
}
```