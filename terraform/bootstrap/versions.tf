terraform {
  required_version = "~> 1.7"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.43" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.aws_region
}
