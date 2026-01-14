output "instance_role_arn" {
  description = "ARN of the role assigned to the Terraformer instance."
  value       = module.terraformer.instance_role_arn
}

output "instance_role_name" {
  description = "Name of the role assigned to the Terraformer instance."
  value       = module.terraformer.instance_role_name
}

output "instance_id" {
  description = "Instance id of terraformer ec2."
  value       = module.terraformer.instance_id
}

output "hostname" {
  description = "Fully qualified domain name of the Terraformer instance."
  value       = module.terraformer.hostname
}

output "cloudwatch_namespace" {
  description = "CloudWatch namespace for custom metrics"
  value       = module.terraformer.cloudwatch_namespace
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for terraformer logs"
  value       = module.terraformer.cloudwatch_log_group_name
}
