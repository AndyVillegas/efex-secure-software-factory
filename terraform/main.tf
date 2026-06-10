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

  access_key                  = "dummy"
  secret_key                  = "dummy"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

resource "aws_s3_bucket" "efex_sensitive_data" {
  bucket = "efex-sensitive-data-demo"

  tags = {
    Environment = "Production"
    Owner       = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "efex_sensitive_data_public_access" {
  bucket = aws_s3_bucket.efex_sensitive_data.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "efex_sensitive_data_public_policy" {
  bucket = aws_s3_bucket.efex_sensitive_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadAccess"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.efex_sensitive_data.arn}/*"
      }
    ]
  })
}

resource "aws_iam_policy" "efex_overprivileged_policy" {
  name = "efex-overprivileged-red-demo"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowEverything"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_security_group" "efex_open_sg" {
  name        = "efex-open-sg-demo"
  description = "Intentionally open security group for policy-as-code demo"
  vpc_id      = var.vpc_id

  ingress {
    description = "Open SSH for demo"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Open API for demo"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = "Production"
    Owner       = "terraform"
  }
}