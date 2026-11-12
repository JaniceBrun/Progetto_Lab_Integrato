variable "name" {
  description = "Nome della chiave (alias: alias/<name>)"
  type        = string
}

variable "description" {
  description = "Descrizione della chiave"
  type        = string
}

variable "deletion_window_in_days" {
  description = "Finestra di cancellazione (7-30 giorni)"
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "La finestra deve essere tra 7 e 30 giorni."
  }
}

variable "allow_cloudwatch_logs" {
  description = "Se true, consente a CloudWatch Logs di usare la chiave"
  type        = bool
  default     = false
}
