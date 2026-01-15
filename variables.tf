variable "ami" {
  description = "Image for EC2 instances"
  type        = string
  default     = null
}

variable "dns_name" {
  description = "Hostname of the Terraformer in zone var.zone_id."
  type        = string
  default     = "terraformer"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.dns_name))
    error_message = "dns_name must be a valid DNS label (lowercase letters, numbers, and hyphens)"
  }
}

variable "environment" {
  description = "Puppet environment."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.environment))
    error_message = "environment must contain only lowercase letters, numbers, and underscores (no hyphens)"
  }
}

variable "extra_files" {
  description = "Additional files to create on an instance."
  type = list(
    object(
      {
        content     = string
        path        = string
        permissions = string
      }
    )
  )
  default = []
}

variable "extra_repos" {
  description = "Additional APT repositories to configure on an instance."
  type = map(
    object(
      {
        source   = string
        key      = string
        machine  = optional(string)
        authFrom = optional(string)
        priority = optional(number)
      }
    )
  )
  default = {}
}

variable "instance_type" {
  description = "Terraformer EC2 instance will run on this type."
  type        = string
  default     = "t3.micro"
}

variable "packages" {
  description = "List of packages to install when the instance bootstraps."
  type        = list(string)
  default     = []
}

variable "puppet_debug_logging" {
  description = "Enable debug logging if true."
  type        = bool
  default     = false
}

variable "puppet_environmentpath" {
  description = "A path for directory environments."
  type        = string
  default     = "{root_directory}/environments"
}

variable "puppet_hiera_config_path" {
  description = "Path to hiera configuration file."
  type        = string
  default     = "{root_directory}/environments/{environment}/hiera.yaml"
}

variable "puppet_manifest" {
  description = "Path to puppet manifest. By default ih-puppet will apply {root_directory}/environments/{environment}/manifests/site.pp."
  type        = string
  default     = null
}

variable "puppet_module_path" {
  description = "Path to puppet modules. Colon-separated list searched in order."
  type        = string
  default     = "{root_directory}/environments/{environment}/modules:{root_directory}/modules"
}

variable "puppet_root_directory" {
  description = "Path where the puppet code is hosted."
  type        = string
  default     = "/opt/puppet-code"
}

variable "root_volume_size" {
  description = "Disk size in GB mounted as the root volume"
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GB for Ubuntu"
  }
}

variable "smtp_credentials_secret" {
  description = "AWS secret name with SMTP credentials. The secret must contain a JSON with user and password keys."
  type        = string
  default     = null
}

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

variable "ssh_key_readers" {
  description = "List of IAM role/user ARNs allowed to read the auto-generated SSH private key from Secrets Manager"
  type        = list(string)
  default     = null
}

variable "subnet" {
  description = "Subnet id where the Terraformer instance will be created."
  type        = string
}

variable "extra_ssh_cidrs" {
  description = "Additional CIDR blocks to allow SSH access from (in addition to VPC CIDR). Useful for accessing from workstations or other networks. Note: Do not include CIDRs that overlap with the VPC CIDR as those are already allowed."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.extra_ssh_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All extra_ssh_cidrs must be valid IPv4 CIDR blocks (e.g., 10.0.0.0/8, 192.168.1.0/24)."
  }
}

variable "ubuntu_codename" {
  description = "Ubuntu version to use for the Terraformer instance"
  type        = string
  default     = "noble"
}

variable "zone_id" {
  description = "Zone where the DNS record will be created."
  type        = string
}

variable "alarm_emails" {
  description = "List of email addresses to receive CloudWatch alarm notifications. AWS SNS will send a confirmation email to each address - recipients MUST click the confirmation link to activate notifications."
  type        = list(string)

  validation {
    condition     = length(var.alarm_emails) >= 1
    error_message = "At least one email address is required for alarm notifications. Provided: ${length(var.alarm_emails)}"
  }

  validation {
    condition     = alltrue([for email in var.alarm_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All alarm_emails must be valid email addresses (e.g., user@example.com)."
  }
}

variable "extra_instance_profile_permissions" {
  description = "A JSON with a permissions policy document. The policy will be attached to the instance profile."
  type        = string
  default     = null
}

variable "cloudwatch_namespace" {
  description = "CloudWatch namespace for custom metrics (convention: Service/Component)"
  type        = string
  default     = "Terraformer/System"
}

variable "cloudwatch_log_retention" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 365

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
