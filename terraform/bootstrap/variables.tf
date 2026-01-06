variable "aws_region" {
  description = "AWS region for bootstrap resources"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name (used in naming)"
  type        = string
  default     = "dev"
}

variable "name_prefix" {
  description = "Prefix for naming bootstrap resources"
  type        = string
  default     = "platform"
}

variable "remote_state_bucket_name" {
  description = "Optional explicit S3 bucket name for Terraform state"
  type        = string
  default     = ""
}

variable "dynamodb_table_name" {
  description = "Optional explicit DynamoDB table name for state locking"
  type        = string
  default     = ""
}

variable "force_destroy" {
  description = "Allow destroying the state bucket (use with care)"
  type        = bool
  default     = false
}
