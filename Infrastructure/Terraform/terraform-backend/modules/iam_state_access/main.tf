data "aws_iam_policy_document" "this" {
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.bucket_arn]
  }

  statement {
    sid       = "ReadWriteStateObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.bucket_arn}/${var.state_key_prefix}/*"]
  }

  statement {
    sid       = "UseStateKmsKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.policy_name
  description = "Accesso minimo al tfstate (prefisso ${var.state_key_prefix}) e alla relativa CMK"
  policy      = data.aws_iam_policy_document.this.json
}
