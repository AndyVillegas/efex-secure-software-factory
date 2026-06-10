variable "aws_region" {
  description = "AWS region used for the demo infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID used by the intentionally vulnerable security group"
  type        = string
  default     = "vpc-00000000000000000"
}