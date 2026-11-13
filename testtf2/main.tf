data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  waf_userdata = <<-EOF
    #!/bin/bash
    # --- Chiavi SSH aggiuntive ---
    # Infrastruttura (janice.brun) - NON rimuovere
    # echo "ssh-ed25519 AAAA...chiave-janice" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 1 (sara.progetto)
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHYfUpoFu9qKnWWakZSRPCL7XOkrbiZZURXleIcc0yJw sara.progetto" >> /home/ubuntu/.ssh/authorized_keys
    chmod 600 /home/ubuntu/.ssh/authorized_keys
    # Utente 2 (marco_progettolab)
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANI89MdEkKMcZYadmcCQ9YJEEAPXCb8+QjChd7d4GmP marco_progettolab" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 3 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente3" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 4 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente4" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 5 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente5" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 6 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente6" >> /home/ubuntu/.ssh/authorized_keys
    apt-get update -y
    apt-get install -y ansible git
  EOF

  wazuh_userdata = <<-EOF
    #!/bin/bash
    # --- Chiavi SSH aggiuntive ---
    # Infrastruttura (janice.brun) - NON rimuovere
    # echo "ssh-ed25519 AAAA...chiave-janice" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 1 (sara.progetto)
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHYfUpoFu9qKnWWakZSRPCL7XOkrbiZZURXleIcc0yJw sara.progetto" >> /home/ubuntu/.ssh/authorized_keys
    chmod 600 /home/ubuntu/.ssh/authorized_keys
    # Utente 2 (marco_progettolab)
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANI89MdEkKMcZYadmcCQ9YJEEAPXCb8+QjChd7d4GmP marco_progettolab" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 3 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente3" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 4 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente4" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 5 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente5" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 6 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente6" >> /home/ubuntu/.ssh/authorized_keys
    apt-get update -y
    apt-get install -y ansible git
  EOF

  bastion_userdata = <<-EOF
    #!/bin/bash
    # --- Chiavi SSH aggiuntive ---
    # Infrastruttura (janice.brun) - NON rimuovere
    # echo "ssh-ed25519 AAAA...chiave-janice" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 1 (sara.progetto)
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHYfUpoFu9qKnWWakZSRPCL7XOkrbiZZURXleIcc0yJw sara.progetto" >> /home/ubuntu/.ssh/authorized_keys
    chmod 600 /home/ubuntu/.ssh/authorized_keys
    # Utente 2 (marco_progettolab)
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANI89MdEkKMcZYadmcCQ9YJEEAPXCb8+QjChd7d4GmP marco_progettolab" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 3 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente3" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 4 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente4" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 5 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente5" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 6 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente6" >> /home/ubuntu/.ssh/authorized_keys
    apt-get update -y
    apt-get install -y ansible git
  EOF

  juice_userdata = <<-EOF
    #!/bin/bash
    # --- Chiavi SSH aggiuntive ---
    # Infrastruttura (janice.brun) - NON rimuovere
    # echo "ssh-ed25519 AAAA...chiave-janice" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 1 (sara.progetto)
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHYfUpoFu9qKnWWakZSRPCL7XOkrbiZZURXleIcc0yJw sara.progetto" >> /home/ubuntu/.ssh/authorized_keys
    chmod 600 /home/ubuntu/.ssh/authorized_keys
    # Utente 2 (marco_progettolab)
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANI89MdEkKMcZYadmcCQ9YJEEAPXCb8+QjChd7d4GmP marco_progettolab" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 3 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente3" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 4 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente4" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 5 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente5" >> /home/ubuntu/.ssh/authorized_keys
    # Utente 6 (nome.cognome)
    # echo "ssh-ed25519 AAAA...chiave-utente6" >> /home/ubuntu/.ssh/authorized_keys
    apt-get update -y
    apt-get install -y ansible git
  EOF
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
  user_data           = local.wazuh_userdata
  tags                = local.tags
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
