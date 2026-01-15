resource "aws_route53_record" "terraformer" {
  name    = "${var.dns_name}.${data.aws_route53_zone.zone.name}"
  type    = "A"
  zone_id = data.aws_route53_zone.zone.zone_id
  ttl     = 300
  records = [
    data.aws_subnet.selected.map_public_ip_on_launch ? aws_instance.terraformer.public_ip : aws_instance.terraformer.private_ip
  ]
}
