# Troubleshooting

## AWS auth / kubeconfig
- Symptom: `ExpiredToken` or `could not get token`.
- Fix: re-auth with `aws sts get-caller-identity`; if assuming a role, export AWS_ROLE_ARN and rerun `./scripts/update_kubeconfig.sh`. Ensure backend S3/DynamoDB is reachable in the same region.

## Terraform backend errors
- Symptom: init fails with `AccessDenied` or missing bucket/table.
- Fix: confirm `terraform/env/backend.hcl` values match bootstrap outputs; verify IAM permissions include `s3:ListBucket/GetObject/PutObject` on the bucket and `dynamodb:*` on the lock table.

## Nodes not Ready
- Symptom: nodes NotReady or no nodes.
- Fix: check `kubectl get nodes -o wide` and `kubectl -n kube-system get pods`; ensure private subnets have NAT (if single NAT, ensure route tables created). Verify node group IAM role present in aws-auth by setting `manage_aws_auth_configmap=true` (already set). Scale node group via tfvars if undersized.

## ALB controller issues
- Symptom: webhook errors or events `AccessDenied`.
- Fix: `kubectl -n kube-system describe deployment aws-load-balancer-controller` and `kubectl logs -n kube-system deploy/aws-load-balancer-controller`. Confirm service account annotation matches Terraform output `alb_controller_role_arn`. Verify public subnets tagged with `kubernetes.io/role/elb` and cluster tag; rerun Terraform if missing.

## ExternalDNS not creating records
- Symptom: no Route53 changes; logs show `AccessDenied` or `No hosted zones found`.
- Fix: ensure `poc_hosted_zone_id` output is correct; external-dns values use `zoneIdFilters`. Check logs `kubectl logs -n kube-system deploy/external-dns`. Verify role annotation equals `external_dns_role_arn` and IAM policy references the correct hosted zone.

## cert-manager DNS01 failures
- Symptom: orders stuck in `Pending` with `DNS01 challenge failed`.
- Fix: ensure `enable_cert_manager=true`, role annotation matches `cert_manager_role_arn`, and hosted zone delegation is in place (if using parent zone). Check `kubectl describe challenge -n cert-manager` and `kubectl logs -n cert-manager deploy/cert-manager`.

## IRSA access denied in workloads
- Symptom: pods using custom IRSA get `AccessDenied`.
- Fix: verify service account annotation matches desired IAM role, and trust policy uses `sub` with correct namespace/name. Compare with patterns in `terraform/env/main.tf` (see add-on roles) and ensure OIDC issuer `terraform output oidc_provider_arn` matches.

## Helm failures
- Symptom: add-on install fails due to missing namespace or CRDs.
- Fix: rerun `./scripts/manage_addons.sh plan` to validate values; for cert-manager ensure `installCRDs=true` is set (script does). If kubeconfig expired, rerun `./scripts/update_kubeconfig.sh`.
