output "bucket_id" {
  description = "Nome del bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN del bucket"
  value       = aws_s3_bucket.this.arn
}
