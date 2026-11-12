output "state_bucket_name" {
  description = "Bucket S3 del tfstate"
  value       = module.state_bucket.bucket_id
}

output "state_kms_key_arn" {
  description = "ARN della chiave KMS del tfstate"
  value       = module.kms.key_arn
}

output "state_access_policy_arn" {
  description = "Policy IAM least-privilege da allegare ai ruoli del team"
  value       = module.iam_state_access.policy_arn
}

output "backend_config" {
  description = "Contenuto per backend.hcl della repo principale"
  value       = <<-EOT
    bucket       = "${module.state_bucket.bucket_id}"
    key          = "${var.state_key_prefix}/terraform.tfstate"
    region       = "${var.aws_region}"
    encrypt      = true
    kms_key_id   = "${module.kms.key_arn}"
    use_lockfile = true
  EOT
}
