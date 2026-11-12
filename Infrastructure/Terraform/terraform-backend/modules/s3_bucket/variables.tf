variable "bucket_name" {
  description = "Nome del bucket"
  type        = string
}

variable "kms_key_arn" {
  description = "CMK per SSE-KMS; se null usa SSE-S3 (AES256)"
  type        = string
  default     = null
}

variable "logging_target_bucket" {
  description = "Bucket di destinazione dei log di accesso; se null il logging è disattivato"
  type        = string
  default     = null
}

variable "logging_target_prefix" {
  description = "Prefisso dei log di accesso"
  type        = string
  default     = ""
}

variable "noncurrent_version_retention_days" {
  description = "Giorni di conservazione delle versioni non correnti"
  type        = number
  default     = 90
}

variable "expiration_days" {
  description = "Scadenza degli oggetti correnti; se null non scadono"
  type        = number
  default     = null
}
