output "key_arn" {
  description = "ARN della chiave KMS"
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "ID della chiave KMS"
  value       = aws_kms_key.this.key_id
}
