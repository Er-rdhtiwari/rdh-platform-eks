terraform {
  required_version = "~> 1.7"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.43" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.31" }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

# Kubernetes provider for managing aws-auth via IRSA roles
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

data "aws_availability_zones" "available" {}
