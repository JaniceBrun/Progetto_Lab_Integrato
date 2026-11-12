resource "aws_security_group" "juice" {
  name        = "${var.name_prefix}-sg-juice"
  description = "Juice Shop"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-sg-juice" })
}

resource "aws_security_group" "waf" {
  name        = "${var.name_prefix}-sg-waf"
  description = "WAF"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-sg-waf" })
}

resource "aws_security_group" "wazuh" {
  name        = "${var.name_prefix}-sg-wazuh"
  description = "Wazuh SIEM"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-sg-wazuh" })
}

resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-sg-bastion"
  description = "Bastion host per accesso SSH a Wazuh"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-sg-bastion" })
}

locals {
  ingress_internet = {
    juice_22   = { sg = aws_security_group.juice.id,   port = 22,   desc = "SSH" }
    juice_80   = { sg = aws_security_group.juice.id,   port = 80,   desc = "HTTP" }
    juice_443  = { sg = aws_security_group.juice.id,   port = 443,  desc = "HTTPS" }
    juice_3000 = { sg = aws_security_group.juice.id,   port = 3000, desc = "Juice Shop UI" }
    waf_22     = { sg = aws_security_group.waf.id,     port = 22,   desc = "SSH" }
    waf_80     = { sg = aws_security_group.waf.id,     port = 80,   desc = "HTTP" }
    waf_443    = { sg = aws_security_group.waf.id,     port = 443,  desc = "HTTPS" }
    wazuh_80   = { sg = aws_security_group.wazuh.id,   port = 80,   desc = "HTTP" }
    wazuh_443  = { sg = aws_security_group.wazuh.id,   port = 443,  desc = "Wazuh dashboard" }
    wazuh_1514 = { sg = aws_security_group.wazuh.id,   port = 1514, desc = "Wazuh agent" }
    wazuh_1515 = { sg = aws_security_group.wazuh.id,   port = 1515, desc = "Wazuh cluster" }
    bastion_22 = { sg = aws_security_group.bastion.id, port = 22,   desc = "SSH da internet" }
  }

  egress_all = {
    juice   = aws_security_group.juice.id
    waf     = aws_security_group.waf.id
    wazuh   = aws_security_group.wazuh.id
    bastion = aws_security_group.bastion.id
  }
}

resource "aws_vpc_security_group_ingress_rule" "internet" {
  for_each          = local.ingress_internet
  security_group_id = each.value.sg
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = each.value.desc
}

# SSH su wazuh solo dal security group del bastion
resource "aws_vpc_security_group_ingress_rule" "wazuh_ssh_from_bastion" {
  security_group_id            = aws_security_group.wazuh.id
  referenced_security_group_id = aws_security_group.bastion.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  description                  = "SSH dal bastion"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  for_each          = local.egress_all
  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound internet"
}
