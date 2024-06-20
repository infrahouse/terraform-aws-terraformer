resource "random_string" "profile-suffix" {
  length  = 12
  special = false
}

data "aws_iam_policy_document" "permissions" {
  statement {
    actions = [
      "sts:AssumeRole",
      "iam:GetRole"
    ]
    resources = ["*"]
  }
}

module "profile" {
  source       = "registry.infrahouse.com/infrahouse/instance-profile/aws"
  version      = "~> 1.3"
  permissions  = data.aws_iam_policy_document.permissions.json
  profile_name = "terraformer-${random_string.profile-suffix.result}"
}

