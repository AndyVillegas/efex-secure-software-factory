output "bucket_name" {
  description = "Name of the intentionally vulnerable S3 bucket"
  value       = aws_s3_bucket.efex_sensitive_data.bucket
}

output "security_group_id" {
  description = "ID of the intentionally open security group"
  value       = aws_security_group.efex_open_sg.id
}