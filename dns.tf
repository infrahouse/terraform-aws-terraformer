resource "aws_route53_record" "terraformer" {
  name    = "${var.dns_name}.${data.aws_route53_zone.zone.name}"
  type    = "A"
  zone_id = data.aws_route53_zone.zone.zone_id
  ttl     = 300
  records = [
    aws_instance.terraformer.private_ip
  ]
}

resource "aws_route53_record" "caa_record" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "${var.dns_name}.${data.aws_route53_zone.zone.name}"
  type    = "CAA"
  ttl     = 300
  records = [
    "0 issue \"amazon.com\"",
    "0 issue \"amazontrust.com\"",
    "0 issue \"awstrust.com\"",
    "0 issue \"amazonaws.com\""
  ]
}
