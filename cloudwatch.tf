resource "aws_cloudwatch_metric_alarm" "cpu_utilization_alarm" {
  count               = var.sns_topic_alarm_arn != null ? 1 : 0
  alarm_name          = format("CPU Alarm on EC2 %s", aws_instance.terraformer.id)
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  evaluation_periods  = 1
  period              = 60
  threshold           = 90
  namespace           = "AWS/EC2"
  alarm_actions       = [var.sns_topic_alarm_arn]
  alarm_description   = format("%s alarm - CPU exceeds 90 percent", aws_instance.terraformer.id)
  dimensions = {
    InstanceId = aws_instance.terraformer.id
  }
}
