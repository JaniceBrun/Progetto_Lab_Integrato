variable "policy_name" {
  description = "Nome della policy IAM"
  type        = string
}

variable "bucket_arn" {
  description = "ARN del bucket tfstate"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN della CMK del tfstate"
  type        = string
}

variable "state_key_prefix" {
  description = "Prefisso delle chiavi di state accessibili"
  type        = string
}
