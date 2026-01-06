# Security Notes

- Secrets: no secrets in code; supply AWS creds via env/instance profile/Jenkins credentials or optional assume-role. Do not commit `backend.hcl`, tfvars, or kubeconfig. Use namespace-scoped IRSA for workloads needing AWS access.
- Least privilege: add-on roles are IRSA-scoped to specific service accounts; ExternalDNS and cert-manager are limited to the PoC hosted zone; node groups use managed policies only. Follow the same pattern for app roles.
- State: remote state bucket blocks public access, encrypts with SSE-S3, versioning enabled; DynamoDB lock has PITR. Bucket/table names are variable-driven to avoid leakage.
- Logging/Audit: EKS control-plane logs enabled with 30-day retention; ALB controller and ExternalDNS logs visible via pod logs; enable ALB access logs to a central bucket if required.
- Network: worker nodes in private subnets; public subnets only for ALBs. NAT gateways are enabled (single by default) to keep cost predictable while allowing egress.
- Supply chain: Helm charts pinned to explicit versions; Terraform providers/modules pinned. Run `terraform providers lock` if you want dependency locks in CI.
