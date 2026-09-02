resource "aws_s3_bucket" "sensitive" {
  bucket = var.sensitive_bucket_name

  tags = {
    Name      = "Wiz Sensitive Lab Data"
    DataClass = "CONFIDENTIAL"
  }
}

resource "aws_s3_bucket_public_access_block" "sensitive" {
  bucket = aws_s3_bucket.sensitive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "sensitive" {
  bucket = aws_s3_bucket.sensitive.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sensitive" {
  bucket = aws_s3_bucket.sensitive.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "sensitive_data" {
  bucket = aws_s3_bucket.sensitive.id
  key    = "production/customer-records.txt"

  content = <<EOF
DATA_CLASSIFICATION=CONFIDENTIAL
ENVIRONMENT=PRODUCTION-LAB

CUSTOMER_ID=LAB-001
CUSTOMER_NAME=Demo Customer
ACCOUNT_NUMBER=DEMO-123456
EMAIL=demo@example.invalid
PHONE=0000000000
EOF

  content_type           = "text/plain"
  server_side_encryption = "AES256"

  depends_on = [
    aws_s3_bucket_public_access_block.sensitive
  ]
}

# Only the workload role is granted the intended object read at the bucket layer.
data "aws_iam_policy_document" "sensitive_bucket" {
  statement {
    sid    = "AllowWorkloadRoleRead"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.workload.arn]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.sensitive.arn}/production/customer-records.txt"]
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.sensitive.arn,
      "${aws_s3_bucket.sensitive.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "sensitive" {
  bucket = aws_s3_bucket.sensitive.id
  policy = data.aws_iam_policy_document.sensitive_bucket.json
}

# Matches the previous lab design: the workload can retrieve the bucket name from SSM.
resource "aws_ssm_parameter" "sensitive_bucket" {
  name  = "/wiz-lab/sensitive-bucket"
  type  = "String"
  value = aws_s3_bucket.sensitive.bucket
}
