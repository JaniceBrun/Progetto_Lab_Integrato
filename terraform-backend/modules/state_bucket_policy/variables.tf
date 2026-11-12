variable "bucket_id" {
  description = "Nome del bucket S3 per cui applicare la policy"
  type        = string
}

variable "allowed_principal_arns" {
  description = "ARN dei principal autorizzati ad accedere al bucket del tfstate"
  type        = list(string)

  validation {
    condition     = length(var.allowed_principal_arns) > 0
    error_message = "Indicare almeno un principal autorizzato."
  }
}
