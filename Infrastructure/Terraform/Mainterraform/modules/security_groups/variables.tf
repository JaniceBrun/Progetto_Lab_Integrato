variable "name_prefix" {
  description = "Prefisso di naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC in cui creare i security group"
  type        = string
}

variable "team_ssh_cidrs" {
  description = "CIDR /32 del team autorizzati a SSH sul bastion"
  type        = list(string)
}
