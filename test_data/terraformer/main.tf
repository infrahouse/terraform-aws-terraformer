module "terraformer" {
  source           = "../../"
  ssh_key_name     = aws_key_pair.test.key_name
  zone_id          = data.aws_route53_zone.test_zone.zone_id
  subnet           = var.subnet_private_ids[0]
  root_volume_size = 30
}
