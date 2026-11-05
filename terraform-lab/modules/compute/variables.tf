variable "name" {
  description = "Nome completo dell'istanza"
  type        = string
}

variable "role" {
  description = "Ruolo della VM (waf, bastion, app, wazuh)"
  type        = string
}

variable "ami_id" {
  description = "AMI da usare"
  type        = string
}

variable "instance_type" {
  description = "Tipo di istanza"
  type        = string
}

variable "volume_gb" {
  description = "Dimensione del volume root in GB"
  type        = number
}

variable "subnet_id" {
  description = "Subnet dell'istanza"
  type        = string
}

variable "security_group_ids" {
  description = "Security group associati"
  type        = list(string)
}

variable "key_name" {
  description = "Key pair di bootstrap"
  type        = string
}

variable "kms_key_arn" {
  description = "CMK per cifrare il volume root"
  type        = string
}
