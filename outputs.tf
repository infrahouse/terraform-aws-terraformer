output "instance_role_arn" {
  description = "ARN of the role assigned to the Terraformer instance."
  value       = module.profile.instance_role_arn
}

output "instance_role_name" {
  description = "Name of the role assigned to the Terraformer instance."
  value       = module.profile.instance_role_name
}
