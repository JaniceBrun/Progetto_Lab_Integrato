locals {
  sg_ids = {
    waf     = aws_security_group.waf.id
    bastion = aws_security_group.bastion.id
    app     = aws_security_group.app.id
    wazuh   = aws_security_group.wazuh.id
  }

  # Ingress con sorgente = altro SG
  ingress_from_sg = {
    # ===================== sg-waf =====================
    waf_ssh_from_bastion = { sg = "waf", source = "bastion", port = 22, description = "Amministrazione via bastion" }

    # ===================== sg-app =====================
    app_3000_from_waf    = { sg = "app", source = "waf", port = 3000, description = "Richieste inoltrate dal reverse proxy" }
    app_ssh_from_bastion = { sg = "app", source = "bastion", port = 22, description = "Amministrazione via bastion" }

    # ===================== sg-wazuh =====================
    wazuh_1514_from_waf    = { sg = "wazuh", source = "waf", port = 1514, description = "Ricezione log dall'agent WAF" }
    wazuh_1514_from_app    = { sg = "wazuh", source = "app", port = 1514, description = "Ricezione log dall'agent Juice Shop" }
    wazuh_1515_from_waf    = { sg = "wazuh", source = "waf", port = 1515, description = "Registrazione agent WAF" }
    wazuh_1515_from_app    = { sg = "wazuh", source = "app", port = 1515, description = "Registrazione agent Juice Shop" }
    wazuh_ssh_from_bastion = { sg = "wazuh", source = "bastion", port = 22, description = "Amministrazione via bastion" }
    wazuh_443_from_bastion = { sg = "wazuh", source = "bastion", port = 443, description = "Dashboard Wazuh tramite tunnel dal bastion" }
  }

  # Ingress da Internet
  ingress_from_internet = {
    # ===================== sg-waf =====================
    waf_80  = { sg = "waf", port = 80, description = "Traffico HTTP di utenti e Red Team" }
    waf_443 = { sg = "waf", port = 443, description = "Traffico HTTPS di utenti e Red Team" }
  }

  # Egress verso altro SG
  egress_to_sg = {
    # ===================== sg-waf =====================
    waf_3000_to_app   = { sg = "waf", destination = "app", port = 3000, description = "Inoltro richieste a Juice Shop" }
    waf_1514_to_wazuh = { sg = "waf", destination = "wazuh", port = 1514, description = "Invio eventi/log dell'agent" }
    waf_1515_to_wazuh = { sg = "waf", destination = "wazuh", port = 1515, description = "Registrazione agent sul manager" }

    # ===================== sg-bastion =====================
    bastion_22_to_waf    = { sg = "bastion", destination = "waf", port = 22, description = "SSH ProxyJump verso WAF" }
    bastion_22_to_app    = { sg = "bastion", destination = "app", port = 22, description = "SSH ProxyJump verso Juice Shop" }
    bastion_22_to_wazuh  = { sg = "bastion", destination = "wazuh", port = 22, description = "SSH ProxyJump verso Wazuh" }
    bastion_443_to_wazuh = { sg = "bastion", destination = "wazuh", port = 443, description = "Dashboard Wazuh via forward dal bastion" }

    # ===================== sg-app =====================
    app_1514_to_wazuh = { sg = "app", destination = "wazuh", port = 1514, description = "Invio eventi/log dell'agent" }
    app_1515_to_wazuh = { sg = "app", destination = "wazuh", port = 1515, description = "Registrazione agent sul manager" }

    # ===================== sg-wazuh =====================
    # (solo egress verso Internet, vedi egress_to_internet)
  }

  # Egress HTTP/HTTPS verso Internet: WAF e bastion via IGW, app e wazuh via NAT
  egress_to_internet = {
    for p in setproduct(["waf", "bastion", "app", "wazuh"], [80, 443]) :
    "${p[0]}_${p[1]}" => {
      sg          = p[0]
      port        = p[1]
      description = "Aggiornamenti, pacchetti e immagini (HTTP/HTTPS)"
    }
  }
}

# ---------------- Ingress da altri SG ----------------
resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  #checkov:skip=CKV_AWS_24: This rule set uses SG-to-SG references, not 0.0.0.0/0 SSH.
  for_each = local.ingress_from_sg

  security_group_id            = local.sg_ids[each.value.sg]
  referenced_security_group_id = local.sg_ids[each.value.source]
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = each.value.description
}

# ---------------- Ingress da Internet (solo WAF) ----------------
resource "aws_vpc_security_group_ingress_rule" "from_internet" {
  #checkov:skip=CKV_AWS_260: HTTP/80 is intentionally exposed on the public WAF entrypoint for the lab scenario.
  for_each = local.ingress_from_internet

  security_group_id = local.sg_ids[each.value.sg]
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = each.value.description
}

# ---------------- Ingress SSH dal team (solo bastion) ----------------
# ===================== sg-bastion =====================
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_from_team" {
  for_each = toset(var.team_ssh_cidrs)

  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  description       = "Accesso SSH dal team"
}

# ---------------- Egress verso altri SG ----------------
resource "aws_vpc_security_group_egress_rule" "to_sg" {
  for_each = local.egress_to_sg

  security_group_id            = local.sg_ids[each.value.sg]
  referenced_security_group_id = local.sg_ids[each.value.destination]
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = each.value.description
}

# ---------------- Egress verso Internet ----------------
resource "aws_vpc_security_group_egress_rule" "to_internet" {
  for_each = local.egress_to_internet

  security_group_id = local.sg_ids[each.value.sg]
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = each.value.description
}
