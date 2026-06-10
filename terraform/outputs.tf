output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.efex_sensitive_data.bucket
}

output "security_group_id" {
  description = "ID of the app security group"
  value       = aws_security_group.efex_app_sg.id
}