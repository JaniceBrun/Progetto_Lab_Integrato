variable "name" {
  description = "Nome del ruolo IAM"
  type        = string
}

variable "log_group_arn" {
  description = "ARN del log group in cui il ruolo può scrivere"
  type        = string
}
