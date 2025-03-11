locals {
  tags = {
    environment : var.environment
    service : "terraformer"
    account : data.aws_caller_identity.current.account_id
    created_by_module : "infrahouse/terraformer/aws"
  }
  ami_name_pattern = contains(
    ["focal", "jammy"], var.ubuntu_codename
  ) ? "ubuntu/images/hvm-ssd/ubuntu-${var.ubuntu_codename}-*" : "ubuntu/images/hvm-ssd-gp3/ubuntu-${var.ubuntu_codename}-*"

}
