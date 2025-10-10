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
