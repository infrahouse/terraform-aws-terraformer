module "terraformer" {
  source           = "../../"
  zone_id          = var.test_zone_id
  subnet           = var.subnet_private_ids[0]
  root_volume_size = 30
  environment      = "development"
  alarm_emails     = ["test@example.com"]
}
