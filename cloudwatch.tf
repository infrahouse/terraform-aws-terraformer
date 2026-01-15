# SNS topic for alarm notifications
# Uses environment-based naming to survive instance replacements without requiring subscription reconfirmation
resource "aws_sns_topic" "terraformer_alarms" {
  name              = "terraformer-alarms-${var.environment}"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(
    {
      Name = "terraformer-alarms"
    },
    local.tags
  )
}

# SNS subscriptions for alarm emails
resource "aws_sns_topic_subscription" "alarm_email" {
  for_each = toset(var.alarm_emails)

  topic_arn = aws_sns_topic.terraformer_alarms.arn
  protocol  = "email"
  endpoint  = each.value
}

# CPU utilization alarm
resource "aws_cloudwatch_metric_alarm" "cpu_utilization_alarm" {
  alarm_name          = "terraformer-cpu-utilization-${aws_instance.terraformer.id}"
  alarm_description   = "Alert when Terraformer CPU exceeds 90 percent"
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  evaluation_periods  = 2
  period              = 60
  threshold           = 90
  namespace           = "AWS/EC2"
  alarm_actions       = [aws_sns_topic.terraformer_alarms.arn]
  dimensions = {
    InstanceId = aws_instance.terraformer.id
  }

  tags = merge(
    {
      Name = "terraformer-cpu-alarm"
    },
    local.tags
  )
}
