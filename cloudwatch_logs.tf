resource "aws_cloudwatch_log_group" "terraformer" {
  name              = "/aws/ec2/terraformer"
  retention_in_days = var.cloudwatch_log_retention

  tags = merge(
    {
      Name = "terraformer-logs"
    },
    local.tags
  )
}