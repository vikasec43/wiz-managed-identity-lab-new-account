resource "aws_s3_bucket" "sensitive" { bucket = var.sensitive_bucket_name }
resource "aws_s3_bucket_public_access_block" "sensitive" {
  bucket                  = aws_s3_bucket.sensitive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "sensitive" {
  bucket = aws_s3_bucket.sensitive.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "sensitive" {
  bucket = aws_s3_bucket.sensitive.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_object" "customer_records" {
  bucket                 = aws_s3_bucket.sensitive.id
  key                    = "production/customer-records.txt"
  content                = <<-EOT
CONFIDENTIAL - WIZ MANAGED IDENTITY LAB
Customer ID: CUST-1001
Name: Demo Customer
Account Type: Production
Data Classification: CONFIDENTIAL
This is synthetic demonstration data. It is not real customer information.
EOT
  server_side_encryption = "AES256"
}
data "aws_iam_policy_document" "sensitive_bucket" {
  statement {
    sid    = "AllowOnlyWorkloadRoleRead"
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
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.sensitive.arn, "${aws_s3_bucket.sensitive.arn}/*"]
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
