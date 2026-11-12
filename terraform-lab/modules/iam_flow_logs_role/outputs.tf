output "role_arn" {
  description = "ARN del ruolo IAM"
  value       = aws_iam_role.this.arn
}
