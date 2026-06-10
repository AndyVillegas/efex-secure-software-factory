terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

resource "aws_kms_key" "efex_s3_key" {
  description             = "KMS key for efex S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_s3_bucket" "efex_logs" {
  #checkov:skip=CKV_AWS_18:Logging bucket does not log itself
  #checkov:skip=CKV_AWS_144:Cross-region replication not required for demo logs bucket
  #checkov:skip=CKV2_AWS_61:No lifecycle policy needed for demo logs bucket
  #checkov:skip=CKV2_AWS_62:Event notifications not required for logs bucket
  bucket = "efex-sensitive-data-logs-demo"

  tags = {
    Environment = "Production"
    Owner       = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "efex_logs_public_access" {
  bucket = aws_s3_bucket.efex_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "efex_logs_encryption" {
  bucket = aws_s3_bucket.efex_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.efex_s3_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "efex_logs_versioning" {
  bucket = aws_s3_bucket.efex_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "efex_sensitive_data" {
  #checkov:skip=CKV_AWS_144:Cross-region replication not required for this demo
  #checkov:skip=CKV2_AWS_62:Event notifications not required for this demo
  bucket = "efex-sensitive-data-demo"

  tags = {
    Environment = "Production"
    Owner       = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "efex_sensitive_data_public_access" {
  bucket = aws_s3_bucket.efex_sensitive_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "efex_sensitive_data_encryption" {
  bucket = aws_s3_bucket.efex_sensitive_data.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.efex_s3_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "efex_sensitive_data_versioning" {
  bucket = aws_s3_bucket.efex_sensitive_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "efex_sensitive_data_logging" {
  bucket = aws_s3_bucket.efex_sensitive_data.id

  target_bucket = aws_s3_bucket.efex_logs.id
  target_prefix = "efex-sensitive-data/"
}

resource "aws_s3_bucket_lifecycle_configuration" "efex_sensitive_data_lifecycle" {
  bucket = aws_s3_bucket.efex_sensitive_data.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_iam_policy" "efex_payment_policy" {
  name = "efex-payment-policy-demo"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPaymentsBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.efex_sensitive_data.arn}/*"
      }
    ]
  })
}

resource "aws_security_group" "efex_app_sg" {
  #checkov:skip=CKV2_AWS_5:Demo resource, not attached to an instance
  name        = "efex-app-sg-demo"
  description = "Restricted security group for efex app"
  vpc_id      = var.vpc_id

  ingress {
    description = "API from VPC only"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description = "HTTPS outbound only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = "Production"
    Owner       = "terraform"
  }
}
