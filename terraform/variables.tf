variable "aws_region" {
  description = "AWS region used for the demo infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID used by the app security group"
  type        = string
  default     = "vpc-00000000000000000"
}

variable "account_id" {
  description = "AWS account ID for KMS key policy"
  type        = string
  default     = "123456789012"
}