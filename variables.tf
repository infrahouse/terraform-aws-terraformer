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
