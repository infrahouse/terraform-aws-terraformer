output "instance_role_arn" {
  description = "ARN of the role assigned to the Terraformer instance."
  value       = module.profile.instance_role_arn
}

output "instance_role_name" {
  description = "Name of the role assigned to the Terraformer instance."
  value       = module.profile.instance_role_name
}

output "instance_id" {
  description = "Instance id of terraformer ec2."
  value       = aws_instance.terraformer.id
}

output "hostname" {
  description = "Fully qualified domain name of the Terraformer instance."
  value       = aws_route53_record.terraformer.fqdn
}

output "ssh_key_secret_arn" {
  description = "ARN of Secrets Manager secret containing auto-generated SSH private key (if applicable)"
  value       = var.ssh_key_name == null ? module.terraformer_ssh_key[0].secret_arn : null
}

output "cloudwatch_namespace" {
  description = "CloudWatch namespace for custom metrics"
  value       = var.cloudwatch_namespace
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for terraformer logs"
  value       = aws_cloudwatch_log_group.terraformer.name
}

output "sns_topic_arn" {
  description = "ARN of SNS topic for alarm notifications"
  value       = aws_sns_topic.terraformer_alarms.arn
}
