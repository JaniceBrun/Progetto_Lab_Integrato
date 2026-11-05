variable "name" {
  description = "Nome del NAT Gateway"
  type        = string
}

variable "subnet_id" {
  description = "Subnet pubblica che ospita il NAT"
  type        = string
}

variable "allocation_id" {
  description = "Allocation ID dell'Elastic IP del NAT"
  type        = string
}
