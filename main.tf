module "userdata" {
  source      = "registry.infrahouse.com/infrahouse/cloud-init/aws"
  version     = "1.12.4"
  environment = var.environment
  role        = "terraformer"
  packages = concat(
    [
      "make",
      "python-is-python3",
      "git",
    ],
    var.packages
  )
  extra_files = var.extra_files
  extra_repos = merge(
    {
      hashicorp : {
        source : "deb [signed-by=$KEY_FILE]  https://apt.releases.hashicorp.com ${var.ubuntu_codename} main"
        key : file("${path.module}/files/DEB-GPG-KEY-hashicorp")
      }
    },
    var.extra_repos
  )
  puppet_debug_logging     = var.puppet_debug_logging
  puppet_environmentpath   = var.puppet_environmentpath
  puppet_hiera_config_path = var.puppet_hiera_config_path
  puppet_manifest          = var.puppet_manifest
  puppet_module_path       = var.puppet_module_path
  puppet_root_directory    = var.puppet_root_directory
  custom_facts = var.smtp_credentials_secret != null ? {
    postfix : {
      smtp_credentials : var.smtp_credentials_secret
    }
  } : {}

}

resource "aws_instance" "terraformer" {
  ami              = var.ami == null ? data.aws_ami.ubuntu.id : var.ami
  instance_type    = var.instance_type
  subnet_id        = var.subnet
  key_name         = var.ssh_key_name
  user_data_base64 = module.userdata.userdata
  vpc_security_group_ids = [
    aws_security_group.terraformer.id
  ]
  iam_instance_profile = module.profile.instance_profile_name
  root_block_device {
    volume_size = var.root_volume_size
  }
  tags = merge(
    {
      Name : "terraformer"
    },
    local.tags
  )
  lifecycle {
    replace_triggered_by = [
      null_resource.terraformer.id
    ]
  }
}

resource "null_resource" "terraformer" {
  triggers = {
    userdata : module.userdata.userdata
  }
}
