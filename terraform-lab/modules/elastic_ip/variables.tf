variable "name" {
  description = "Nome dell'Elastic IP"
  type        = string
}

variable "instance_id" {
  description = "Istanza a cui associare l'EIP; null per un EIP non associato (es. NAT)"
  type        = string
  default     = null
}
