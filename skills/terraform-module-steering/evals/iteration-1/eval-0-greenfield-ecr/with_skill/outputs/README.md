# terraform-module-aws-ecr

A secure-by-default Amazon **ECR private repository** that satisfies the mandatory CIS / AWS
Foundational Security Best Practices (FSBP) ECR controls with a minimal, two-input interface. Wraps the
proven [`terraform-aws-modules/ecr/aws`](https://registry.terraform.io/modules/terraform-aws-modules/ecr/aws)
module (pinned `v3.2.0`) and hardcodes every security setting so it cannot be weakened by a consumer.

## Features

- **Private ECR repository** with a minimal interface — you supply only `name` and `environment`.
- **Customer-managed KMS encryption at rest** (module-managed CMK, key rotation enabled) — FSBP ECR.5.
- **Scan-on-push** image vulnerability scanning — FSBP ECR.1.
- **Immutable image tags** — FSBP ECR.2.
- **A lifecycle policy is always present** (retains the most recent N images) — FSBP ECR.3.
- **TLS-only repository policy** — every ECR action over a non-TLS connection is denied (defense-in-depth).
- **Mandatory tags** (`ManagedBy`, `Module`, `Environment`) merged *over* your tags — cannot be dropped.

All security settings are **hardcoded literals, not variables** — they are non-overridable by design.

## Security controls enforced

| Control (CIS / FSBP id) | Enforcement | Overridable? |
|---|---|---|
| FSBP **ECR.1** — image scanning | `scan_on_push = true` passed to the repository | No — hardcoded |
| FSBP **ECR.2** — tag immutability | `image_tag_mutability = "IMMUTABLE"` | No — hardcoded |
| FSBP **ECR.3** — lifecycle policy present | lifecycle policy always created (keeps last N images) | No — hardcoded (count is tunable, policy always present) |
| FSBP **ECR.5** — customer-managed KMS encryption | `encryption_type = "KMS"` with a module-managed CMK (rotation on) | No — hardcoded |
| CIS general — deny non-TLS access | repository policy `Deny` when `aws:SecureTransport = false` | No — hardcoded |
| Mandatory tagging | `ManagedBy=terraform`, `Module=...`, `Environment=<env>` merged over consumer tags | No — merged over |

Out of scope (documented in [docs/DESIGN.md](docs/DESIGN.md)): FSBP ECR.4 (public repositories — this
module is private-only) and registry-wide enhanced/continuous scanning (an account/registry-level
setting, not per-repository).

## Usage

```hcl
module "ecr" {
  source = "github.com/your-org/terraform-module-aws-ecr" # or your registry path

  name        = "my-service"
  environment = "prod"
}
```

With optional inputs:

```hcl
module "ecr" {
  source = "github.com/your-org/terraform-module-aws-ecr"

  name                              = "my-service"
  environment                       = "prod"
  lifecycle_keep_last_count         = 50
  additional_read_access_arns       = ["arn:aws:iam::123456789012:role/ci-puller"]
  additional_read_write_access_arns = ["arn:aws:iam::123456789012:role/ci-pusher"]
  tags                              = { Team = "platform" }
}
```

The module does **not** configure the AWS provider — the consumer owns region and credentials.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.7 |
| aws | >= 6.28 |

Developed and tested on Terraform v1.15.6 (latest stable). The declared floor matches the wrapped
upstream module so consumers are not forced onto the latest toolchain.

## Inputs

<!-- BEGIN_TF_DOCS -->
| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Name of the ECR private repository to create. | `string` | n/a | yes |
| `environment` | Deployment environment (`dev`/`test`/`staging`/`prod`). Drives the mandatory Environment tag. | `string` | n/a | yes |
| `tags` | Additional tags. Mandatory tags are merged over these and cannot be dropped. | `map(string)` | `{}` | no |
| `force_delete` | If true, the repository (and its images) can be deleted by Terraform. | `bool` | `false` | no |
| `lifecycle_keep_last_count` | Number of most-recent images to retain under the mandatory lifecycle policy. | `number` | `30` | no |
| `additional_read_access_arns` | IAM principal ARNs granted pull (read) access via the repository policy. | `list(string)` | `[]` | no |
| `additional_read_write_access_arns` | IAM principal ARNs granted push/pull (read-write) access via the repository policy. | `list(string)` | `[]` | no |
<!-- END_TF_DOCS -->

## Outputs

<!-- BEGIN_TF_DOCS -->
| Name | Description |
|------|-------------|
| `repository_arn` | Full ARN of the ECR repository. |
| `repository_name` | Name of the ECR repository. |
| `repository_url` | URL of the ECR repository (image push/pull target). |
| `repository_registry_id` | Registry ID (account ID) where the repository was created. |
| `kms_key_arn` | ARN of the customer-managed KMS key encrypting the repository. |
| `kms_key_id` | ID of the customer-managed KMS key encrypting the repository. |
| `kms_key_alias_arn` | ARN of the alias for the customer-managed KMS key. |
<!-- END_TF_DOCS -->

## Examples

- [minimal](examples/minimal) — the smallest consumer (`name` + `environment` only).

## Verification

This module is verified with `terraform fmt`, `terraform validate`, `tflint`, `terraform test`
(native tests, `mock_provider`, no AWS credentials), and `checkov`. See
[docs/DESIGN.md](docs/DESIGN.md) for the control mapping and documented checkov suppressions.

## License

Apache-2.0 (matches the wrapped upstream module). Provide your own `LICENSE` file when publishing.
