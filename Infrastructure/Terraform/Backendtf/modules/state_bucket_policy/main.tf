data "aws_iam_policy_document" "this" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.bucket_id}",
      "arn:aws:s3:::${var.bucket_id}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "DenyBucketDeletion"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:DeleteBucket"]
    resources = [
      "arn:aws:s3:::${var.bucket_id}",
    ]
  }

  statement {
    sid    = "DenyUnlistedPrincipals"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.bucket_id}",
      "arn:aws:s3:::${var.bucket_id}/*",
    ]

    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values   = var.allowed_principal_arns
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = var.bucket_id
  policy = data.aws_iam_policy_document.this.json
}
