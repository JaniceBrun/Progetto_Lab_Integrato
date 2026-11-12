# Solo definizione dei security group. Le regole sono in sg-rules.tf.

resource "aws_security_group" "waf" {
  #checkov:skip=CKV2_AWS_5: Attached to EC2 instances by the compute module in the root stack.
  name        = "${var.name_prefix}-sg-waf"
  description = "VM WAF: reverse proxy + ModSecurity, unico ingresso pubblico"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-sg-waf" }
}

resource "aws_security_group" "bastion" {
  #checkov:skip=CKV2_AWS_5: Attached to EC2 instances by the compute module in the root stack.
  name        = "${var.name_prefix}-sg-bastion"
  description = "VM bastion: unico accesso amministrativo"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-sg-bastion" }
}

resource "aws_security_group" "app" {
  #checkov:skip=CKV2_AWS_5: Attached to EC2 instances by the compute module in the root stack.
  name        = "${var.name_prefix}-sg-app"
  description = "VM Juice Shop: raggiungibile solo dal WAF"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-sg-app" }
}

resource "aws_security_group" "wazuh" {
  #checkov:skip=CKV2_AWS_5: Attached to EC2 instances by the compute module in the root stack.
  name        = "${var.name_prefix}-sg-wazuh"
  description = "VM Wazuh SIEM: raccolta log centralizzata"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-sg-wazuh" }
}
