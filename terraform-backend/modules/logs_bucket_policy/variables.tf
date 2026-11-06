variable "bucket_id" {
  description = "Nome del bucket S3 per cui applicare la policy"
  type        = string
}

variable "state_bucket_arn" {
  description = "ARN del bucket tfstate da usare come SourceArn nel controllo del logging"
  type        = string
}
