variable "owner_id" {
  description = "Owner ID pubblico dell'AMI (Canonical)"
  type        = string
  default     = "099720109477"
}

variable "name_pattern" {
  description = "Pattern del nome AMI Ubuntu"
  type        = string
  default     = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
}
