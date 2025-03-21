variable "ami" {
  description = "Image for EC2 instances"
  type        = string
  default     = null
}

variable "dns_name" {
  description = "Hostname of the Terraformer in zone var.zone_id."
  type        = string
  default     = "terraformer"
}

variable "environment" {
  description = "Puppet environment."
  type        = string
  default     = "development"
}

variable "extra_files" {
  description = "Additional files to create on an instance."
  type = list(object({
    content     = string
    path        = string
    permissions = string
  }))
  default = []
}

variable "extra_repos" {
  description = "Additional APT repositories to configure on an instance."
  type = map(object({
    source = string
    key    = string
  }))
  default = {}
}

variable "instance_type" {
  description = "Terraformer EC2 instance will run on this type."
  type        = string
  default     = "t3.micro"
}

variable "packages" {
  description = "List of packages to install when the instances bootstraps."
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
  description = "Path to common puppet modules."
  type        = string
  default     = "{root_directory}/modules"
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
}

variable "smtp_credentials_secret" {
  description = "AWS secret name with SMTP credentials. The secret must contain a JSON with user and password keys."
  type        = string
  default     = null
}

variable "ssh_key_name" {
  description = "ssh key name installed in the Terraformer instance."
  type        = string
}

variable "subnet" {
  description = "Subnet id where the Terraformer instance will be created."
  type        = string
}

variable "ubuntu_codename" {
  description = "Ubuntu version to use for the Terraformer instance"
  type        = string
  default     = "jammy"
}

variable "zone_id" {
  description = "Zone where the DNS record will be created."
  type        = string
}

variable "sns_topic_alarm_arn" {
  description = "ARN of SNS topic for Cloudwatch alarms on base EC2 instance."
  type        = string
  default     = null
}
