variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project prefix"
  type        = string
  default     = "labtest"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "key_name" {
  description = "Nome del key pair AWS (senza .pem)"
  type        = string
  default     = ""
}

variable "lab_role_name" {
  description = "Nome del ruolo IAM esistente nel Learner Lab"
  type        = string
  default     = "LabRole"
}

# ---- Juice Shop ----
variable "juice_instance_type" {
  description = "Tipo istanza Juice Shop (t2.micro/t3.small consigliati nel Learner Lab)"
  type        = string
  default     = "t3.small"
}

variable "juice_volume_gb" {
  description = "Volume EBS Juice Shop in GiB"
  type        = number
  default     = 20
}

# ---- WAF ----
variable "waf_instance_type" {
  description = "Tipo istanza WAF (t3.medium = 2vCPU/4GB, minimo per nginx+ModSecurity+OWASP CRS)"
  type        = string
  default     = "t3.medium"
}

variable "waf_volume_gb" {
  description = "Volume EBS WAF in GiB"
  type        = number
  default     = 30
}

# ---- Wazuh SIEM ----
variable "wazuh_instance_type" {
  description = "Tipo istanza Wazuh all-in-one (manager+indexer+dashboard). t3.large=2vCPU/8GB, più vicino disponibile nel Learner Lab a c6i.xlarge"
  type        = string
  default     = "t3.large"
}

variable "wazuh_volume_gb" {
  description = "Volume EBS Wazuh in GiB"
  type        = number
  default     = 60
}

# ---- Bastion ----
variable "bastion_instance_type" {
  description = "Tipo istanza bastion host"
  type        = string
  default     = "t3.micro"
}

variable "bastion_volume_gb" {
  description = "Volume EBS bastion in GiB"
  type        = number
  default     = 8
}
