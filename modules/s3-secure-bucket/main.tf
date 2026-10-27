data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  create_kms_key = var.kms_key_arn == null
  kms_key_arn    = local.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn

  # Built from the name instead of aws_s3_bucket.this.arn so the policy is
  # fully known at plan time and can be checked by policy-as-code.
  bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${var.bucket_name}"

  mandatory_statements = [
    {
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    },
    {
      Sid       = "DenyOutdatedTLS"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
      Condition = { NumericLessThan = { "s3:TlsVersion" = "1.2" } }
    },
    {
      Sid       = "DenyNonKmsEncryptionHeader"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:PutObject"
      Resource  = "${local.bucket_arn}/*"
      Condition = {
        StringNotEquals = { "s3:x-amz-server-side-encryption" = "aws:kms" }
        Null            = { "s3:x-amz-server-side-encryption" = "false" }
      }
    },
  ]

  log_delivery_statements = var.accept_access_logs ? [{
    Sid       = "AllowS3ServerAccessLogDelivery"
    Effect    = "Allow"
    Principal = { Service = "logging.s3.amazonaws.com" }
    Action    = "s3:PutObject"
    Resource  = "${local.bucket_arn}/*"
    Condition = {
      StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
    }
  }] : []

  tags = merge(var.tags, { "platform:module" = "s3-secure-bucket" })
}

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "SSE-KMS key for s3://${var.bucket_name}"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_key_deletion_window_days

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AccountAdministration"
      Effect    = "Allow"
      Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })

  tags = merge(local.tags, { Name = var.bucket_name })
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/s3/${var.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.tags, { Name = var.bucket_name })
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disables ACLs entirely; access is governed by IAM and the bucket policy only.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_logging" "this" {
  count = var.access_log_bucket == null ? 0 : 1

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_log_bucket
  target_prefix = coalesce(var.access_log_prefix, "s3/${var.bucket_name}/")
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat(local.mandatory_statements, local.log_delivery_statements, var.additional_policy_statements)
  })

  # The public access block must exist first, otherwise a broad statement in
  # additional_policy_statements could briefly make the bucket public.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
