variable "aws_region" {
  description = "Regione AWS del backend"
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

variable "state_bucket_name" {
  description = "Nome globalmente univoco del bucket tfstate"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "Nome bucket S3 non valido."
  }
}

variable "state_key_prefix" {
  description = "Prefisso delle chiavi di state nel bucket (es. lab)"
  type        = string
  default     = "lab"
}

variable "allowed_principal_arns" {
  description = "ARN (anche con wildcard) dei principal autorizzati al bucket. Deve includere chi esegue l'apply."
  type        = list(string)

  validation {
    condition     = length(var.allowed_principal_arns) > 0
    error_message = "Indicare almeno un principal autorizzato."
  }
}

variable "kms_deletion_window_days" {
  description = "Finestra di cancellazione della CMK (7-30)"
  type        = number
  default     = 30
}

variable "noncurrent_version_retention_days" {
  description = "Giorni di conservazione delle versioni non correnti dello state"
  type        = number
  default     = 90
}

variable "log_retention_days" {
  description = "Giorni di conservazione dei log di accesso S3"
  type        = number
  default     = 365
}
