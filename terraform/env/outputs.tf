output "cluster_name" {
  value       = module.eks.cluster_name
  description = "EKS cluster name"
}

output "cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "EKS API endpoint"
}

output "region" {
  value       = var.aws_region
  description = "Deployment region"
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "VPC ID"
}

output "poc_domain" {
  value       = local.poc_domain
  description = "PoC domain"
}

output "poc_hosted_zone_id" {
  value       = local.poc_hosted_zone_id
  description = "Hosted zone ID used for PoC records"
}

output "poc_hosted_zone_name_servers" {
  value       = var.create_poc_hosted_zone ? aws_route53_zone.poc[0].name_servers : []
  description = "Nameservers for delegated PoC zone"
}

output "oidc_provider_arn" {
  value       = module.eks.oidc_provider_arn
  description = "OIDC provider ARN for IRSA"
}

output "alb_controller_role_arn" {
  value       = aws_iam_role.alb_controller.arn
  description = "IAM role ARN for AWS Load Balancer Controller"
}

output "external_dns_role_arn" {
  value       = var.enable_external_dns ? aws_iam_role.external_dns[0].arn : ""
  description = "IAM role ARN for external-dns"
}

output "cert_manager_role_arn" {
  value       = var.enable_cert_manager ? aws_iam_role.cert_manager[0].arn : ""
  description = "IAM role ARN for cert-manager"
}

output "ecr_repository_arns" {
  value       = [for repo in aws_ecr_repository.shared : repo.arn]
  description = "ARNs for shared ECR repositories"
}

output "enable_cert_manager" {
  value       = var.enable_cert_manager
  description = "Whether cert-manager is enabled"
}

output "enable_external_dns" {
  value       = var.enable_external_dns
  description = "Whether external-dns is enabled"
}

output "enable_metrics_server" {
  value       = var.enable_metrics_server
  description = "Whether metrics-server is enabled"
}
