resource "aws_vpc" "this" {
  #checkov:skip=CKV2_AWS_11: Flow logs are configured by the dedicated vpc_flow_log module in the root stack.
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# Il default SG viene svuotato: nessun traffico consentito
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-default-sg-locked" }
}
