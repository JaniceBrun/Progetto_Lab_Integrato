variable "aws_region" {
  description = "Regione AWS"
  type        = string
}

variable "availability_zone" {
  description = "AZ delle subnet (es. eu-south-1a)"
  type        = string
}

variable "project" {
  description = "Nome progetto"
  type        = string
}

variable "environment" {
  description = "Ambiente"
  type        = string
}

variable "tags" {
  description = "Tag aggiuntivi"
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR della VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR subnet pubblica"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR subnet privata"
  type        = string
  default     = "10.0.2.0/24"
}

variable "team_ssh_cidrs" {
  description = "IP del team (solo /32) autorizzati a SSH sul bastion"
  type        = list(string)

  validation {
    condition     = length(var.team_ssh_cidrs) > 0 && alltrue([for c in var.team_ssh_cidrs : can(cidrhost(c, 0)) && endswith(c, "/32")])
    error_message = "team_ssh_cidrs deve contenere almeno un CIDR valido di tipo /32."
  }
}

variable "bootstrap_public_key" {
  description = "Chiave SSH PUBBLICA di bootstrap"
  type        = string

  validation {
    condition     = startswith(var.bootstrap_public_key, "ssh-")
    error_message = "Fornire una chiave pubblica SSH (ssh-ed25519 / ssh-rsa ...)."
  }
}

variable "instance_sizing" {
  description = "Tipo istanza e volume root per ruolo"
  type = object({
    waf = optional(object({
      instance_type = optional(string, "t3.small")
      volume_gb     = optional(number, 30)
    }), {})
    bastion = optional(object({
      instance_type = optional(string, "t3.micro")
      volume_gb     = optional(number, 10)
    }), {})
    app = optional(object({
      instance_type = optional(string, "t3.small")
      volume_gb     = optional(number, 20)
    }), {})
    wazuh = optional(object({
      instance_type = optional(string, "t3.large")
      volume_gb     = optional(number, 60)
    }), {})
  })
  default = {}
}

variable "flow_logs_retention_days" {
  description = "Retention dei VPC Flow Logs"
  type        = number
  default     = 365
}

variable "ansible_user" {
  description = "Utente SSH usato da Ansible"
  type        = string
  default     = "ubuntu"
}
