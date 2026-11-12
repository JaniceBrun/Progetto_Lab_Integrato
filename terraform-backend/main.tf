locals {
  logs_bucket_name = "${var.state_bucket_name}-logs"
  state_bucket_arn = "arn:aws:s3:::${var.state_bucket_name}"
  logs_bucket_arn  = "arn:aws:s3:::${local.logs_bucket_name}"
}

module "kms" {
  source = "./modules/kms"

  name                    = "${var.project}-${var.environment}-tfstate"
  description             = "CMK per la cifratura del tfstate di ${var.project}-${var.environment}"
  deletion_window_in_days = var.kms_deletion_window_days
}

module "logs_bucket" {
  source = "./modules/s3_bucket"

  bucket_name                       = local.logs_bucket_name
  noncurrent_version_retention_days = 30
  expiration_days                   = var.log_retention_days
}

module "logs_bucket_policy" {
  source = "./modules/logs_bucket_policy"

  bucket_id        = module.logs_bucket.bucket_id
  state_bucket_arn = local.state_bucket_arn

  depends_on = [module.logs_bucket]
}

module "state_bucket" {
  source = "./modules/s3_bucket"

  bucket_name                       = var.state_bucket_name
  kms_key_arn                       = module.kms.key_arn
  logging_target_bucket             = module.logs_bucket.bucket_id
  logging_target_prefix             = "state-access/"
  noncurrent_version_retention_days = var.noncurrent_version_retention_days

  depends_on = [module.logs_bucket_policy]
}

# Applicata per ultima: evita il lock-out durante l'apply
module "state_bucket_policy" {
  source = "./modules/state_bucket_policy"

  bucket_id              = module.state_bucket.bucket_id
  allowed_principal_arns = var.allowed_principal_arns

  depends_on = [module.state_bucket]
}

module "iam_state_access" {
  source = "./modules/iam_state_access"

  policy_name      = "${var.project}-${var.environment}-tfstate-access"
  bucket_arn       = module.state_bucket.bucket_arn
  kms_key_arn      = module.kms.key_arn
  state_key_prefix = var.state_key_prefix
}
