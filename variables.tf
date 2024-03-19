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

variable "instance_type" {
  description = "Terraformer EC2 instance will run on this type."
  type        = string
  default     = "t3.micro"
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
