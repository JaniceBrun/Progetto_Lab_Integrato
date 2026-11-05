variable "name" {
  description = "Nome della route table"
  type        = string
}

variable "vpc_id" {
  description = "VPC della route table"
  type        = string
}

variable "subnet_id" {
  description = "Subnet da associare"
  type        = string
}

variable "gateway_id" {
  description = "Internet Gateway per la route 0.0.0.0/0 (alternativo a nat_gateway_id)"
  type        = string
  default     = null
}

variable "nat_gateway_id" {
  description = "NAT Gateway per la route 0.0.0.0/0 (alternativo a gateway_id)"
  type        = string
  default     = null
}
