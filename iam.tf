resource "random_string" "profile-suffix" {
  length  = 12
  special = false
}

data "aws_iam_policy_document" "permissions" {
  source_policy_documents = var.extra_instance_profile_permissions != null ? [var.extra_instance_profile_permissions] : []
  statement {
    actions = [
      "sts:AssumeRole",
      "iam:GetRole"
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "${aws_cloudwatch_log_group.terraformer.arn}:*"
    ]
  }
  statement {
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.cloudwatch_namespace]
    }
  }
  statement {
    actions   = ["ec2:DescribeTags"]
    resources = ["*"]
  }
  # Allows Puppet (profile::boot_security_upgrade) to remove the
  # InspectorEc2Exclusion tag from this instance once security updates are applied.
  statement {
    actions   = ["ec2:DeleteTags"]
    resources = ["arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*"]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["InspectorEc2Exclusion"]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/created_by_module"
      values   = [local.tags.created_by_module]
    }
  }
}

module "profile" {
  source       = "registry.infrahouse.com/infrahouse/instance-profile/aws"
  version      = "2.0.0"
  permissions  = data.aws_iam_policy_document.permissions.json
  profile_name = "terraformer-${random_string.profile-suffix.result}"
}

