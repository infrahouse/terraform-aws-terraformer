module "userdata" {
  source      = "registry.infrahouse.com/infrahouse/cloud-init/aws"
  version     = "~> 1.6"
  environment = var.environment
  role        = "terraformer"
  packages = [
    "make",
    "python-is-python3"
  ]
  extra_repos = {
    hashicorp : {
      source : "deb [signed-by=$KEY_FILE]  https://apt.releases.hashicorp.com ${var.ubuntu_codename} main"
      key : file("${path.module}/files/DEB-GPG-KEY-hashicorp")
    }
  }
}

resource "aws_instance" "terraformer" {
  ami              = data.aws_ami.ubuntu.id
  instance_type    = var.instance_type
  subnet_id        = var.subnet
  key_name         = var.ssh_key_name
  user_data_base64 = module.userdata.userdata
  vpc_security_group_ids = [
    aws_security_group.terraformer.id
  ]
  iam_instance_profile = module.profile.instance_profile_name
  tags = merge(
    {
      Name : "terraformer"
    },
    local.tags
  )
}
