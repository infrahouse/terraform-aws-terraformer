locals {
  tags = {
    environment : var.environment
    service : "terraformer"
    account : data.aws_caller_identity.current.account_id
    created_by_module : "infrahouse/terraformer/aws"
  }
  ubuntu_versions = {
    "jammy" : "22.04"
  }
}
