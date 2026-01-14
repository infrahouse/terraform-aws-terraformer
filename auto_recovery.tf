# System status check - auto-recover on hardware failure
resource "aws_cloudwatch_metric_alarm" "terraformer_system_auto_recovery" {
  alarm_name          = "terraformer-system-auto-recovery-${aws_instance.terraformer.id}"
  alarm_description   = "Auto recover Terraformer instance when underlying hardware fails"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0.5
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    InstanceId = aws_instance.terraformer.id
  }

  alarm_actions = [
    "arn:aws:automate:${data.aws_region.current.name}:ec2:recover",
    aws_sns_topic.terraformer_alarms.arn
  ]

  tags = merge(
    {
      Name = "terraformer-system-recovery"
    },
    local.tags
  )
}

# Instance status check - auto-reboot on software failure
resource "aws_cloudwatch_metric_alarm" "terraformer_instance_check" {
  alarm_name          = "terraformer-instance-status-check-${aws_instance.terraformer.id}"
  alarm_description   = "Auto-reboot Terraformer instance on status check failures"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0.5
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    InstanceId = aws_instance.terraformer.id
  }

  alarm_actions = [
    "arn:aws:automate:${data.aws_region.current.name}:ec2:reboot",
    aws_sns_topic.terraformer_alarms.arn
  ]

  tags = merge(
    {
      Name = "terraformer-instance-check"
    },
    local.tags
  )
}