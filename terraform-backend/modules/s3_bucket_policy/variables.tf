variable "bucket_id" {
  description = "Bucket a cui applicare la policy"
  type        = string
}

variable "policy_json" {
  description = "Policy in formato JSON"
  type        = string
}
