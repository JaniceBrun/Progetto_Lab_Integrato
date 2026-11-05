locals {
  sgs = ["waf", "app", "wazuh", "bastion"]

  sg_rules = {
    waf_http       = { to = "waf",   port = 80,   src = null,      cidr = "0.0.0.0/0" }
    waf_https      = { to = "waf",   port = 443,  src = null,      cidr = "0.0.0.0/0" }
    waf_ssh        = { to = "waf",   port = 22,   src = "bastion", cidr = null }
    app_3000       = { to = "app",   port = 3000, src = "waf",     cidr = null }
    app_ssh        = { to = "app",   port = 22,   src = "bastion", cidr = null }
    wazuh_ssh      = { to = "wazuh", port = 22,   src = "bastion", cidr = null }
    wazuh_ui       = { to = "wazuh", port = 443,  src = "bastion", cidr = null }
    wazuh_1514_waf = { to = "wazuh", port = 1514, src = "waf",     cidr = null }
    wazuh_1515_waf = { to = "wazuh", port = 1515, src = "waf",     cidr = null }
    wazuh_1514_app = { to = "wazuh", port = 1514, src = "app",     cidr = null }
    wazuh_1515_app = { to = "wazuh", port = 1515, src = "app",     cidr = null }
  }
}

resource "aws_security_group" "sg" {
  for_each    = toset(local.sgs)
  name        = "lab-${each.key}"
  description = "Lab ${each.key}"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "lab-${each.key}" }
}

resource "aws_vpc_security_group_ingress_rule" "r" {
  for_each                     = local.sg_rules
  security_group_id            = aws_security_group.sg[each.value.to].id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
  cidr_ipv4                    = each.value.cidr
  referenced_security_group_id = each.value.src == null ? null : aws_security_group.sg[each.value.src].id
}

# SSH al bastion solo dagli IP del team
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each          = toset(var.team_cidrs)
  security_group_id = aws_security_group.sg["bastion"].id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "all" {
  for_each          = toset(local.sgs)
  security_group_id = aws_security_group.sg[each.key].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}