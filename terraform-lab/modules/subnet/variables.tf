variable "name" {
  description = "Nome completo della subnet"
  type        = string
}

variable "tier" {
  description = "Livello della subnet (public/private)"
  type        = string

  validation {
    condition     = contains(["public", "private"], var.tier)
    error_message = "tier deve essere public o private."
  }
}

variable "vpc_id" {
  description = "VPC della subnet"
  type        = string
}

variable "cidr_block" {
  description = "CIDR della subnet"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone"
  type        = string
}
