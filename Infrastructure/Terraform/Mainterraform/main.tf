locals {
  name_prefix = "${var.project}-${var.environment}"

  vms = {
    waf     = { subnet = "public", public_ip = true, sizing = var.instance_sizing.waf }
    bastion = { subnet = "public", public_ip = true, sizing = var.instance_sizing.bastion }
    app     = { subnet = "private", public_ip = false, sizing = var.instance_sizing.app }
    wazuh   = { subnet = "private", public_ip = false, sizing = var.instance_sizing.wazuh }
  }

  subnet_ids = {
    public  = module.subnet_public.subnet_id
    private = module.subnet_private.subnet_id
  }

  public_vms = { for k, v in local.vms : k => v if v.public_ip }
}

# ------------------------- Cifratura -------------------------
module "kms" {
  source = "./modules/kms"

  name                    = "${local.name_prefix}-lab"
  description             = "CMK per EBS e CloudWatch Logs di ${local.name_prefix}"
  allow_cloudwatch_logs   = true
  deletion_window_in_days = 30
}

# ------------------------- Networking -------------------------
module "vpc" {
  source = "./modules/vpc"

  name_prefix = local.name_prefix
  cidr_block  = var.vpc_cidr
}

module "internet_gateway" {
  source = "./modules/internet_gateway"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
}

module "subnet_public" {
  source = "./modules/subnet"

  name              = "${local.name_prefix}-public"
  tier              = "public"
  vpc_id            = module.vpc.vpc_id
  cidr_block        = var.public_subnet_cidr
  availability_zone = var.availability_zone
}

module "subnet_private" {
  source = "./modules/subnet"

  name              = "${local.name_prefix}-private"
  tier              = "private"
  vpc_id            = module.vpc.vpc_id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone
}

module "nat_eip" {
  source = "./modules/elastic_ip"

  name = "${local.name_prefix}-nat-eip"

  depends_on = [module.internet_gateway]
}

module "nat_gateway" {
  source = "./modules/nat_gateway"

  name          = "${local.name_prefix}-nat"
  subnet_id     = module.subnet_public.subnet_id
  allocation_id = module.nat_eip.allocation_id

  depends_on = [module.internet_gateway]
}

module "route_table_public" {
  source = "./modules/route_table"

  name       = "${local.name_prefix}-rt-public"
  vpc_id     = module.vpc.vpc_id
  subnet_id  = module.subnet_public.subnet_id
  gateway_id = module.internet_gateway.internet_gateway_id
}

module "route_table_private" {
  source = "./modules/route_table"

  name           = "${local.name_prefix}-rt-private"
  vpc_id         = module.vpc.vpc_id
  subnet_id      = module.subnet_private.subnet_id
  nat_gateway_id = module.nat_gateway.nat_gateway_id
}

# ------------------------- VPC Flow Logs -------------------------
module "flow_log_group" {
  source = "./modules/cloudwatch_log_group"

  name              = "/aws/vpc/${local.name_prefix}-flow-logs"
  retention_in_days = var.flow_logs_retention_days
  kms_key_arn       = module.kms.key_arn
}

module "flow_log_role" {
  source = "./modules/iam_flow_logs_role"

  name          = "${local.name_prefix}-flow-logs"
  log_group_arn = module.flow_log_group.log_group_arn
}

module "vpc_flow_log" {
  source = "./modules/vpc_flow_log"

  name          = "${local.name_prefix}-flow-log"
  vpc_id        = module.vpc.vpc_id
  iam_role_arn  = module.flow_log_role.role_arn
  log_group_arn = module.flow_log_group.log_group_arn
}

# ------------------------- Security group -------------------------
module "security_groups" {
  source = "./modules/security_groups"

  name_prefix    = local.name_prefix
  vpc_id         = module.vpc.vpc_id
  team_ssh_cidrs = var.team_ssh_cidrs
}

# ------------------------- Compute -------------------------
module "ubuntu_ami" {
  source = "./modules/ubuntu_ami"
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name   = "${local.name_prefix}-bootstrap"
  public_key = var.bootstrap_public_key
}

module "compute" {
  source   = "./modules/compute"
  for_each = local.vms

  name               = "${local.name_prefix}-${each.key}"
  role               = each.key
  ami_id             = module.ubuntu_ami.ami_id
  instance_type      = each.value.sizing.instance_type
  volume_gb          = each.value.sizing.volume_gb
  subnet_id          = local.subnet_ids[each.value.subnet]
  security_group_ids = [module.security_groups.security_group_ids[each.key]]
  key_name           = module.key_pair.key_name
  kms_key_arn        = module.kms.key_arn

  depends_on = [module.route_table_private]
}

module "vm_eips" {
  source   = "./modules/elastic_ip"
  for_each = local.public_vms

  name        = "${local.name_prefix}-${each.key}-eip"
  instance_id = module.compute[each.key].instance_id

  depends_on = [module.internet_gateway]
}
