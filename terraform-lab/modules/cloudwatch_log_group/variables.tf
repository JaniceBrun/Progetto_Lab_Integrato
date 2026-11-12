variable "name" {
  description = "Nome del log group"
  type        = string
}

variable "retention_in_days" {
  description = "Retention in giorni"
  type        = number
}

variable "kms_key_arn" {
  description = "CMK per cifrare il log group"
  type        = string
}
