output "state_bucket_name" {
  value       = aws_s3_bucket.tf_state.bucket
  description = "Terraform state S3 bucket"
}

output "lock_table_name" {
  value       = aws_dynamodb_table.tf_lock.name
  description = "Terraform state lock DynamoDB table"
}

output "region" {
  value       = var.aws_region
  description = "Region for bootstrap resources"
}
