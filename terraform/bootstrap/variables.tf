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

  validation {
    condition     = length(var.remote_state_bucket_name) > 0
    error_message = "Set remote_state_bucket_name (e.g., via TF_VAR_remote_state_bucket_name)."
  }
}

variable "dynamodb_table_name" {
  description = "Optional explicit DynamoDB table name for state locking"
  type        = string
  default     = ""

  validation {
    condition     = length(var.dynamodb_table_name) > 0
    error_message = "Set dynamodb_table_name (e.g., via TF_VAR_dynamodb_table_name)."
  }
}

variable "force_destroy" {
  description = "Allow destroying the state bucket (use with care)"
  type        = bool
  default     = false
}
