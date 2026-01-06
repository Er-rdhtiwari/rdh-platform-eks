# rdh-platform-eks

Assumptions up front (change as needed): you control a root domain, supply AWS credentials via env/instance profile/assume-role, and run Terraform 1.7+ with helm/kubectl available from either Jenkins on EC2 or your workstation. Scripts auto-source `.env` from the repo root if present.

## Why
A single, production-minded EKS "platform" cluster lowers PoC friction while keeping guardrails: least-privilege IRSA for add-ons, auditable Terraform state, controllable costs (NAT/node sizing), and repeatable Jenkins automation.

## How (high level)
- Terraform bootstrap creates a hardened S3 bucket + DynamoDB lock for remote state.
- Terraform env stack builds VPC, subnets (public for ALB, private for nodes), NAT, EKS with IRSA + control-plane logging, optional ECR repos, and a `poc.<ROOT_DOMAIN>` hosted zone (with optional delegation into the parent zone).
- IAM roles scoped for add-ons: ALB controller, ExternalDNS (zone-scoped), cert-manager (DNS01, zone-scoped).
- Helm installs add-ons (aws-load-balancer-controller, external-dns, cert-manager, metrics-server) via scripts that can dry-run, install/upgrade, or uninstall.
- Jenkinsfiles orchestrate plan/apply/destroy with approval gates and optional add-on rollout.

## Defaults and variables
- Region: `ap-south-1` (override `aws_region`)
- Environment: `dev`
- Name prefix: `platform`
- Domain: `poc.<root_domain>` (root domain required input)
- Node type/size: from tfvars or `.env` (`NODE_INSTANCE_TYPES`, `NODE_MIN_SIZE`, `NODE_DESIRED_SIZE`, `NODE_MAX_SIZE` default to `t3.large` 2/2/4; list supports multiple instance types)
- Feature toggles: `enable_cert_manager`, `enable_external_dns`, `enable_metrics_server`, `enable_ecr`, `create_poc_hosted_zone`
- Other: optional `parent_hosted_zone_id` for delegation, optional `existing_poc_hosted_zone_id` when not creating, `node_instance_types`, `vpc_cidr`, `single_nat_gateway`

## Repo layout (what lives where)
- `terraform/bootstrap`: creates remote state bucket + lock table.
- `terraform/env`: VPC, EKS, IRSA, Route53, optional ECR, backend stub, tfvars/backend examples, policies for ALB.
- `scripts/`: tooling checks, kubeconfig update, add-on lifecycle, cluster verification.
- `docs/`: runbook, troubleshooting, security notes.
- `Jenkinsfile.platform`, `Jenkinsfile.addons`: pipelines for infra and add-ons.
- `Makefile`: common targets (bootstrap/init/plan/apply/destroy, kubeconfig, add-ons, status).

## Prerequisites
- AWS credentials: environment/Jenkins credentials binding or EC2 instance profile; optional `AWS_ROLE_ARN` to assume a role.
- Tools: `aws`, `terraform` (1.7+), `kubectl`, `helm`, `jq`, `envsubst`. Run `./scripts/require_tools.sh`.
- Domain: supply `root_domain` (e.g., `rdhcloudlab.com`), optional `parent_hosted_zone_id` for delegation.
- Bash: mark scripts executable (`chmod +x scripts/*.sh`).

## Execution flow (do this order)
1) **Bootstrap remote state** (local or Jenkins):
   ```bash
   terraform -chdir=terraform/bootstrap init
   terraform -chdir=terraform/bootstrap apply -auto-approve
   ```
   Bootstrap names are globally unique (random suffix); capture outputs `state_bucket_name` and `lock_table_name`.
2) **Prepare env config**:
   - Copy `terraform/env/backend.hcl.example` to `terraform/env/backend.hcl` and fill with the bucket/table/key/region (key pattern `env/<env>/terraform.tfstate`).
   - Copy `terraform/env/terraform.tfvars.example` to `terraform/env/<env>.tfvars` and set `root_domain`, `parent_hosted_zone_id` (if delegating), node sizes, toggles, etc.
3) **Initialize + validate**:
   ```bash
   make tf-init ENV=dev AWS_REGION=ap-south-1
   make fmt validate ENV=dev
   ```
4) **Plan/apply** (backend config is required):
   ```bash
   make plan ENV=dev
   make apply ENV=dev  # add AUTO_APPROVE=true to skip prompt
   ```
   Check outputs: cluster name, endpoint, hosted zone ID/NS, IRSA role ARNs.
5) **Kubeconfig**:
   ```bash
   ./scripts/update_kubeconfig.sh  # uses terraform output by default
   ```
6) **Add-ons (Helm)**:
   ```bash
   ./scripts/manage_addons.sh plan      # dry-run
   ./scripts/manage_addons.sh upgrade   # install/upgrade
   ./scripts/manage_addons.sh uninstall # remove
   ```
7) **Verify**:
   ```bash
   ./scripts/verify_cluster.sh
   ```

## Jenkins pipelines (summary)
- `Jenkinsfile.platform`: parameters `ACTION=plan|apply|destroy`, `ENV`, `AUTO_APPROVE`, `INSTALL_ADDONS`. Generates backend.hcl from `TF_STATE_BUCKET`/`TF_LOCK_TABLE`, runs fmt/validate/plan, manual gate for apply/destroy, applies `terraform.plan`, then (optionally) runs add-ons.
- `Jenkinsfile.addons`: same params; `ACTION=plan` -> Helm dry-run, `apply` -> upgrade/install, `destroy` -> uninstall. Manual gate on apply/destroy. Both support optional `AWS_ROLE_ARN` assume-role; never echo secrets.

## How PoC repos deploy here
- Use kubeconfig from this cluster (pull from Jenkins workspace or run `aws eks update-kubeconfig` on EC2/Jenkins agent).
- Build images into the shared ECR repos (enable via `enable_ecr`); tag by app/version.
- Deploy via Helm from each PoC repo, pointing ingress hosts to `app.poc.<root_domain>`; ExternalDNS writes records into the dedicated hosted zone; ALB controller provisions ALBs on public subnets with required tags.
- For app-specific IAM to AWS APIs, create namespace-scoped service accounts with IRSA roles following the same OIDC issuer as defined here.

## Cost and safety notes
- NAT gateways and ALBs drive most cost; `single_nat_gateway=true` limits spend, and idle ALBs should be destroyed.
- Node counts are conservative by default; tune `node_min/max/desired` per environment.
- CloudWatch control-plane logs are enabled with 30-day retention for audit; adjust if you need longer.
- Destroy carefully: `make destroy ENV=dev` tears down the cluster, VPC, and hosted zone (removes NS delegation). State bucket/table persist unless you manually delete bootstrap resources.

## Debug/next steps
- See `docs/runbook.md` for step-by-step checkpoints and commands.
- See `docs/troubleshooting.md` for IRSA/ALB/ExternalDNS/cert-manager fixes.
- See `docs/security.md` for least-privilege and secrets handling.
