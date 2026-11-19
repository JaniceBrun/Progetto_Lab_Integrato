data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  waf_userdata = templatefile("${path.module}/user_data/bootstrap.sh.tpl", {
    repo_url         = "https://github.com/JaniceBrun/Progetto_Lab_Integrato.git"
    repo_branch      = "janice-synctest"
    playbook         = "waf.yml"
    wazuh_manager_ip = module.wazuh.private_ip
    juiceshop_ip     = module.juice.private_ip
  })

  wazuh_userdata = templatefile("${path.module}/user_data/bootstrap.sh.tpl", {
    repo_url         = "https://github.com/JaniceBrun/Progetto_Lab_Integrato.git"
    repo_branch      = "janice-synctest"
    playbook         = "wazuh.yml"
    wazuh_manager_ip = ""
    juiceshop_ip     = ""
  })

  bastion_userdata = <<-EOF
    #!/bin/bash
    set -Eeuo pipefail

    export DEBIAN_FRONTEND=noninteractive

    mkdir -p /home/ubuntu/.ssh
    chmod 700 /home/ubuntu/.ssh
    chown ubuntu:ubuntu /home/ubuntu/.ssh
    touch /home/ubuntu/.ssh/authorized_keys
    chmod 600 /home/ubuntu/.ssh/authorized_keys
    chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys

    grep -qxF 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHYfUpoFu9qKnWWakZSRPCL7XOkrbiZZURXleIcc0yJw sara.progetto' /home/ubuntu/.ssh/authorized_keys || \\
      echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHYfUpoFu9qKnWWakZSRPCL7XOkrbiZZURXleIcc0yJw sara.progetto' >> /home/ubuntu/.ssh/authorized_keys

    grep -qxF 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANI89MdEkKMcZYadmcCQ9YJEEAPXCb8+QjChd7d4GmP marco_progettolab' /home/ubuntu/.ssh/authorized_keys || \\
      echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANI89MdEkKMcZYadmcCQ9YJEEAPXCb8+QjChd7d4GmP marco_progettolab' >> /home/ubuntu/.ssh/authorized_keys

    apt-get update -y
    apt-get install -y ansible git
  EOF

  juice_userdata = templatefile("${path.module}/user_data/bootstrap.sh.tpl", {
    repo_url         = "https://github.com/JaniceBrun/Progetto_Lab_Integrato.git"
    repo_branch      = "janice-synctest"
    playbook         = "juiceshop.yml"
    wazuh_manager_ip = module.wazuh.private_ip
    juiceshop_ip     = ""
  })
}

module "network" {
  source = "./modules/network"

  name_prefix         = local.name_prefix
  aws_region          = var.aws_region
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  tags                = local.tags
}

module "security_groups" {
  source = "./modules/security_groups"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id
  tags        = local.tags
}

module "juice" {
  source = "./modules/compute"

  name                = "${local.name_prefix}-juice"
  role                = "juice"
  instance_type       = var.juice_instance_type
  volume_gb           = var.juice_volume_gb
  subnet_id           = module.network.public_subnet_id
  security_group_ids  = [module.security_groups.juice_sg_id]
  key_name            = var.key_name
  lab_role_name       = var.lab_role_name
  associate_public_ip = true
  user_data           = local.juice_userdata
  tags                = local.tags

  depends_on = [module.network, module.security_groups]
}

module "waf" {
  source = "./modules/compute"

  name                = "${local.name_prefix}-waf"
  role                = "waf"
  instance_type       = var.waf_instance_type
  volume_gb           = var.waf_volume_gb
  subnet_id           = module.network.public_subnet_id
  security_group_ids  = [module.security_groups.waf_sg_id]
  key_name            = var.key_name
  lab_role_name       = var.lab_role_name
  associate_public_ip = true
  user_data           = local.waf_userdata
  tags                = local.tags

  depends_on = [module.network, module.security_groups]
}

module "wazuh" {
  source = "./modules/compute"

  name                = "${local.name_prefix}-wazuh"
  role                = "wazuh"
  instance_type       = var.wazuh_instance_type
  volume_gb           = var.wazuh_volume_gb
  subnet_id           = module.network.private_subnet_id
  security_group_ids  = [module.security_groups.wazuh_sg_id]
  key_name            = var.key_name
  lab_role_name       = var.lab_role_name
  associate_public_ip = false
  private_ip          = null
  user_data           = local.wazuh_userdata
  tags                = local.tags

  depends_on = [module.network, module.security_groups]
}

module "bastion" {
  source = "./modules/compute"

  name                = "${local.name_prefix}-bastion"
  role                = "bastion"
  instance_type       = var.bastion_instance_type
  volume_gb           = var.bastion_volume_gb
  subnet_id           = module.network.public_subnet_id
  security_group_ids  = [module.security_groups.bastion_sg_id]
  key_name            = var.key_name
  lab_role_name       = var.lab_role_name
  associate_public_ip = true
  user_data           = local.bastion_userdata
  tags                = local.tags

  depends_on = [module.network, module.security_groups]
}

resource "aws_eip" "juice" {
  instance   = module.juice.instance_id
  domain     = "vpc"
  depends_on = [module.network]
  tags       = merge(local.tags, { Name = "${local.name_prefix}-juice-eip" })
}

resource "aws_eip" "waf" {
  instance   = module.waf.instance_id
  domain     = "vpc"
  depends_on = [module.network]
  tags       = merge(local.tags, { Name = "${local.name_prefix}-waf-eip" })
}

resource "aws_eip" "bastion" {
  instance   = module.bastion.instance_id
  domain     = "vpc"
  depends_on = [module.network]
  tags       = merge(local.tags, { Name = "${local.name_prefix}-bastion-eip" })
}
