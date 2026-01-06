resource "random_id" "suffix" {
  byte_length = 2
}

locals {
  default_bucket_name = lower(replace("${var.name_prefix}-${var.environment}-tfstate-${random_id.suffix.hex}", "_", "-"))
  default_table_name  = lower(replace("${var.name_prefix}-${var.environment}-tf-lock-${random_id.suffix.hex}", "_", "-"))

  bucket_name = var.remote_state_bucket_name != "" ? var.remote_state_bucket_name : local.default_bucket_name
  table_name  = var.dynamodb_table_name != "" ? var.dynamodb_table_name : local.default_table_name
}

resource "aws_s3_bucket" "tf_state" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = {
    Name        = local.bucket_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    id     = "abort-incomplete-mpu"
    status = "Enabled"
    filter {
      prefix = ""
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = local.table_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
