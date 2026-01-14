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
module "terraformer_ssh_key" {
  count              = var.ssh_key_name == null ? 1 : 0
  source             = "registry.infrahouse.com/infrahouse/secret/aws"
  version            = "1.1.1"
  environment        = var.environment
  secret_name        = "terraformer_ssh_private_key_${data.aws_caller_identity.current.account_id}"
  secret_description = "Auto-generated SSH private key for Terraformer emergency access"
  secret_value       = tls_private_key.terraformer[0].private_key_openssh
  readers            = var.ssh_key_readers
}
