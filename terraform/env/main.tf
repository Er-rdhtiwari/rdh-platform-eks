locals {
  name_prefix  = "${var.name_prefix}-${var.environment}"
  cluster_name = "${local.name_prefix}-eks"
  poc_domain   = "${var.poc_subdomain}.${var.root_domain}"
  tags = merge({
    Project     = local.name_prefix
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.additional_tags)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  public_subnets  = [for i in range(0, 3) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i in range(0, 3) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = merge(local.tags, {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  })

  private_subnet_tags = merge(local.tags, {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  })

  tags = local.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access         = true
  enable_irsa                            = true
  cluster_enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = 30

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      capacity_type  = "ON_DEMAND"
      subnet_ids     = module.vpc.private_subnets
      ami_type       = "AL2_x86_64"
      tags           = local.tags
    }
  }

  tags = local.tags
}

module "aws_auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = "20.8.5"

  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = module.eks.eks_managed_node_groups["default"].iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    }
  ]

  depends_on = [module.eks]
}

locals {
  oidc_provider        = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  poc_hosted_zone_id   = var.create_poc_hosted_zone ? aws_route53_zone.poc[0].zone_id : var.existing_poc_hosted_zone_id
  poc_hosted_zone_name = var.create_poc_hosted_zone ? aws_route53_zone.poc[0].name : local.poc_domain
}

resource "aws_route53_zone" "poc" {
  count = var.create_poc_hosted_zone ? 1 : 0
  name  = local.poc_domain
  tags  = local.tags
}

resource "aws_route53_record" "poc_ns" {
  count   = var.create_poc_hosted_zone && var.parent_hosted_zone_id != "" ? 1 : 0
  zone_id = var.parent_hosted_zone_id
  name    = local.poc_domain
  type    = "NS"
  ttl     = 300
  records = aws_route53_zone.poc[0].name_servers
}

resource "aws_ecr_repository" "shared" {
  count                = var.enable_ecr ? length(var.ecr_repository_names) : 0
  name                 = lower(var.ecr_repository_names[count.index])
  force_delete         = false
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

# IAM for AWS Load Balancer Controller
resource "aws_iam_policy" "alb_controller" {
  name        = "${local.cluster_name}-alb-controller"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = file("${path.module}/policies/alb-controller.json")
}

data "aws_iam_policy_document" "alb_irsa_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${local.cluster_name}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_irsa_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# IAM for external-dns
locals {
  external_dns_zone_arn = "arn:aws:route53:::hostedzone/${local.poc_hosted_zone_id}"
}

data "aws_iam_policy_document" "external_dns_irsa_assume" {
  count = var.enable_external_dns ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:external-dns"]
    }
  }
}

data "aws_iam_policy_document" "external_dns" {
  count = var.enable_external_dns ? 1 : 0
  statement {
    sid       = "ListZones"
    actions   = ["route53:ListHostedZones", "route53:ListHostedZonesByName"]
    resources = ["*"]
  }
  statement {
    sid       = "ListRecords"
    actions   = ["route53:ListResourceRecordSets", "route53:ListTagsForResource"]
    resources = [local.external_dns_zone_arn]
  }
  statement {
    sid       = "ChangeRecords"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [local.external_dns_zone_arn]
  }
  statement {
    sid       = "GetZone"
    actions   = ["route53:GetHostedZone"]
    resources = [local.external_dns_zone_arn]
  }
}

resource "aws_iam_role" "external_dns" {
  count              = var.enable_external_dns ? 1 : 0
  name               = "${local.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_irsa_assume[0].json
  tags               = local.tags
}

resource "aws_iam_policy" "external_dns" {
  count       = var.enable_external_dns ? 1 : 0
  name        = "${local.cluster_name}-external-dns"
  description = "Scoped Route53 permissions for external-dns"
  policy      = data.aws_iam_policy_document.external_dns[0].json
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  count      = var.enable_external_dns ? 1 : 0
  role       = aws_iam_role.external_dns[0].name
  policy_arn = aws_iam_policy.external_dns[0].arn
}

# IAM for cert-manager DNS01
locals {
  cert_manager_zone_arn = local.external_dns_zone_arn
}

data "aws_iam_policy_document" "cert_manager_irsa_assume" {
  count = var.enable_cert_manager ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:cert-manager:cert-manager"]
    }
  }
}

data "aws_iam_policy_document" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0
  statement {
    sid       = "ListZones"
    actions   = ["route53:ListHostedZonesByName", "route53:ListHostedZones"]
    resources = ["*"]
  }
  statement {
    sid       = "ChangeRecords"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [local.cert_manager_zone_arn]
  }
  statement {
    sid       = "ReadRecords"
    actions   = ["route53:ListResourceRecordSets"]
    resources = [local.cert_manager_zone_arn]
  }
  statement {
    sid       = "GetChange"
    actions   = ["route53:GetChange"]
    resources = ["*"]
  }
  statement {
    sid       = "GetZone"
    actions   = ["route53:GetHostedZone"]
    resources = [local.cert_manager_zone_arn]
  }
}

resource "aws_iam_role" "cert_manager" {
  count              = var.enable_cert_manager ? 1 : 0
  name               = "${local.cluster_name}-cert-manager"
  assume_role_policy = data.aws_iam_policy_document.cert_manager_irsa_assume[0].json
  tags               = local.tags
}

resource "aws_iam_policy" "cert_manager" {
  count       = var.enable_cert_manager ? 1 : 0
  name        = "${local.cluster_name}-cert-manager"
  description = "Route53 DNS01 permissions for cert-manager"
  policy      = data.aws_iam_policy_document.cert_manager[0].json
}

resource "aws_iam_role_policy_attachment" "cert_manager" {
  count      = var.enable_cert_manager ? 1 : 0
  role       = aws_iam_role.cert_manager[0].name
  policy_arn = aws_iam_policy.cert_manager[0].arn
}
