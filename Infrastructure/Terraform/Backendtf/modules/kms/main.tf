data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  base_statements = [
    {
      Sid       = "EnableIAMPolicies"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }
  ]

  logs_statements = [
    for i in range(var.allow_cloudwatch_logs ? 1 : 0) : {
      Sid       = "AllowCloudWatchLogs"
      Effect    = "Allow"
      Principal = { Service = "logs.${data.aws_region.current.name}.amazonaws.com" }
      Action = [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ]
      Resource = "*"
      Condition = {
        ArnLike = {
          "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"
        }
      }
    }
  ]
}

resource "aws_kms_key" "this" {
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat(local.base_statements, local.logs_statements)
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}
