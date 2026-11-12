output "bucket_id" {
  description = "Bucket a cui è applicata la policy"
  value       = aws_s3_bucket_policy.this.bucket
}
