# Runbook

Purpose: step-by-step flow with checkpoints so you can stand up the platform cluster and recover from surprises.

## 1) Preflight
- Why: fail fast on missing tools/creds.
- How:
  ```bash
  ./scripts/require_tools.sh
  aws sts get-caller-identity
  ```
  Check AWS_REGION/PROFILE/ROLE env vars are set as intended.

## 2) Bootstrap remote state (once per account)
- Why: durable, locked state before touching infra.
- How:
  ```bash
  terraform -chdir=terraform/bootstrap init
  terraform -chdir=terraform/bootstrap apply -auto-approve
  ```
  Checkpoint: note `state_bucket_name` and `lock_table_name` outputs.

## 3) Prepare environment config
- Why: backend needs explicit config; Terraform backend cannot read variables.
- How:
  ```bash
  cp terraform/env/backend.hcl.example terraform/env/backend.hcl
  # fill bucket/table/key/region from bootstrap output
  cp terraform/env/terraform.tfvars.example terraform/env/dev.tfvars
  # set root_domain, parent_hosted_zone_id (if delegating), node sizes, toggles
  ```
  Checkpoint: `terraform/env/backend.hcl` and `<env>.tfvars` exist and contain the right bucket/table/key.

## 4) Init + validate
- Why: ensure backend + syntax before plans.
- How:
  ```bash
  make tf-init ENV=dev AWS_REGION=ap-south-1
  make fmt validate ENV=dev
  ```
  If init fails, re-check backend.hcl values and IAM perms to the bucket/table.

## 5) Plan and apply
- Why: review drift and expected changes.
- How:
  ```bash
  make plan ENV=dev
  make apply ENV=dev  # add AUTO_APPROVE=true to skip prompt
  ```
  Checkpoint: `terraform -chdir=terraform/env output` shows cluster_name, endpoint, hosted zone ID/NS, IRSA role ARNs.

## 6) Kubeconfig
- Why: needed before Helm/kubectl operations.
- How:
  ```bash
  ./scripts/update_kubeconfig.sh
  kubectl get nodes
  ```

## 7) Install/upgrade add-ons
- Why: ingress, DNS, certs, metrics for workloads.
- How:
  ```bash
  ./scripts/manage_addons.sh plan     # dry-run
  ./scripts/manage_addons.sh upgrade  # install/upgrade
  ```
  Checkpoint: `kubectl get deployments -n kube-system` shows ALB controller, external-dns, metrics-server; `kubectl get deployments -n cert-manager` shows cert-manager if enabled.

## 8) Verify
- Why: catch readiness/IRSA issues early.
- How:
  ```bash
  ./scripts/verify_cluster.sh
  ```
  Look for Ready nodes, running pods, and IRSA role annotations printed for add-on service accounts.

## 9) Safe destroy
- Why: avoid orphaning DNS/ALBs.
- How:
  ```bash
  ./scripts/manage_addons.sh uninstall || true
  make destroy ENV=dev  # confirm manually
  ```
  Optional: delete bootstrap state bucket/table only when no other envs rely on them.
