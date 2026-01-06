variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name (dev/stage/prod)"
  type        = string
  default     = "dev"
}

variable "name_prefix" {
  description = "Prefix for shared platform resources"
  type        = string
  default     = "platform"
}

variable "root_domain" {
  description = "Root domain managed outside this stack (e.g., rdhcloudlab.com)"
  type        = string
}

variable "poc_subdomain" {
  description = "Subdomain prefix for PoC hosted zone"
  type        = string
  default     = "poc"
}

variable "create_poc_hosted_zone" {
  description = "Whether to create a hosted zone for poc.<root_domain>"
  type        = bool
  default     = true
}

variable "existing_poc_hosted_zone_id" {
  description = "Existing hosted zone ID to reuse when create_poc_hosted_zone is false"
  type        = string
  default     = ""

  validation {
    condition     = var.create_poc_hosted_zone || var.existing_poc_hosted_zone_id != ""
    error_message = "Provide existing_poc_hosted_zone_id when create_poc_hosted_zone is false."
  }
}

variable "parent_hosted_zone_id" {
  description = "Optional parent hosted zone ID for NS delegation"
  type        = string
  default     = ""
}

variable "cluster_version" {
  description = "EKS cluster Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "Instance types for managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired node count"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum node count"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum node count"
  type        = number
  default     = 4
}

variable "enable_cert_manager" {
  description = "Deploy cert-manager add-on"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Deploy external-dns add-on"
  type        = bool
  default     = true
}

variable "enable_metrics_server" {
  description = "Deploy metrics-server add-on"
  type        = bool
  default     = true
}

variable "enable_ecr" {
  description = "Create shared ECR repositories"
  type        = bool
  default     = false
}

variable "ecr_repository_names" {
  description = "Names of shared ECR repositories to create when enabled"
  type        = list(string)
  default     = ["shared-app"]
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway to control cost"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
