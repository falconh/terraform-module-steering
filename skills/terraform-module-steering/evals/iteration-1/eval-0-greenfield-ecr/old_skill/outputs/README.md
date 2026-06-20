# terraform-module-aws-ecr

A secure-by-default **private** Amazon ECR repository. Wraps the proven
[`terraform-aws-modules/ecr/aws`](https://registry.terraform.io/modules/terraform-aws-modules/ecr/aws/3.2.0)
module (pinned to `3.2.0`) and enforces the mandatory AWS Foundational Security Best Practices (FSBP)
ECR controls as **hardcoded, non-overridable** settings.

## Features

- Creates one private ECR repository with a minimal interface (`name` + `environment`).
- Provisions a **module-managed customer-managed KMS key (CMK)** with annual rotation and a scoped key
  policy, and encrypts the repository with it.
- Enforces, as hardcoded literals a consumer cannot weaken:
  - image **scan-on-push** (FSBP ECR.1),
  - **immutable** image tags (FSBP ECR.2),
  - a **lifecycle policy** (FSBP ECR.3),
  - **KMS (CMK) encryption** at rest (FSBP ECR.5).
- Mandatory tags (`Environment`, `ManagedBy`, `Module`) are merged on top of consumer tags and cannot
  be dropped.

## Security controls enforced

Benchmark: **AWS FSBP** (the AWS Security Hub standard for ECR). The CIS AWS Foundations Benchmark has
no ECR-specific controls, so FSBP is the applicable per-service standard.

| Control (FSBP id) | Enforcement | Overridable? |
|---|---|---|
| ECR.1 — image scanning configured | `repository_image_scan_on_push = true` | No — hardcoded |
| ECR.2 — tag immutability | `repository_image_tag_mutability = "IMMUTABLE"` | No — hardcoded |
| ECR.3 — at least one lifecycle policy | `create_lifecycle_policy = true` + a non-empty policy (untagged-image expiry + tagged-image cap) | No — policy always attached; only thresholds are tunable |
| ECR.5 — encrypt at rest with a CMK | `repository_encryption_type = "KMS"` + a module-managed `aws_kms_key` (ARN passed as a literal); `enable_key_rotation = true` | No — hardcoded |
| ECR.4 — public repos tagged | N/A — this module creates **private** repos only | Not applicable |

Verified with `checkov` against `examples/minimal` (external module followed): `CKV_AWS_163`
(scan-on-push) and `CKV_AWS_136` (KMS encryption) pass on the real `aws_ecr_repository`. See
`docs/DESIGN.md` for the full control mapping and the three documented suppressions.

## Usage

```hcl
module "ecr" {
  source = "github.com/your-org/terraform-module-aws-ecr" # or your registry source

  name        = "my-app"
  environment = "prod"
}
```

Push images to the repository at `module.ecr.repository_url`. The consumer owns the AWS provider
(region and credentials); this module does not configure the provider.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.7 |
| aws | >= 6.28 |

Wrapped module: `terraform-aws-modules/ecr/aws` `3.2.0`. Built and verified with Terraform v1.15.6 and
aws provider v6.50.0.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Name of the private ECR repository to create. | `string` | n/a | yes |
| `environment` | Deployment environment (`dev` / `test` / `staging` / `prod`). Drives the mandatory `Environment` tag. | `string` | n/a | yes |
| `tags` | Additional tags. Mandatory tags are merged on top and cannot be overridden. | `map(string)` | `{}` | no |
| `force_delete` | If true, the repo can be destroyed while it still holds images. | `bool` | `false` | no |
| `untagged_image_expiry_days` | Days after which untagged images expire (lifecycle threshold). | `number` | `14` | no |
| `max_tagged_image_count` | Max number of tagged images to retain (lifecycle threshold). | `number` | `100` | no |

> Security-relevant settings (tag mutability, scan-on-push, encryption type, KMS key, key rotation, the
> presence of a lifecycle policy) are **not** inputs — they are hardcoded so they cannot be weakened.

## Outputs

| Name | Description |
|------|-------------|
| `repository_name` | Name of the ECR repository. |
| `repository_arn` | Full ARN of the ECR repository. |
| `repository_url` | URL of the repository (image push/pull target). |
| `repository_registry_id` | Registry (account) ID where the repository was created. |
| `kms_key_arn` | ARN of the CMK encrypting the repository. |
| `kms_key_id` | ID of the CMK encrypting the repository. |
| `kms_alias_arn` | ARN of the KMS alias. |
| `kms_alias_name` | Name of the KMS alias (`alias/ecr/<name>`). |

## Examples

- [minimal](examples/minimal) — required inputs only; doubles as the checkov fixture.

## Verification

All commands below pass with no AWS credentials (tests use `mock_provider`):

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
tflint --init && tflint --recursive
terraform test
checkov -d examples/minimal --download-external-modules true --config-file .checkov.yaml
```

Last verified result: `fmt` clean · `validate` success · `tflint` clean · `terraform test` 10 passed,
0 failed · `checkov` 27 passed, 0 failed, 3 documented skips.

## Out of scope

Public ECR repositories (and FSBP ECR.4), account/registry-level enhanced scanning, registry
replication, pull-through cache, and custom cross-account repository policies. See `docs/DESIGN.md`.

## License

This wrapper is provided as-is. The wrapped upstream module is Apache-2.0 licensed by its maintainers.
