# 4. Terraform — Infrastructure as Code

## Design goals

Three things this project's Terraform is built around, per explicit
requirements:

1. **Hand-rolled modules, no public registry modules.** Every AWS resource
   (VPC, subnets, EKS cluster/node group, RDS, ECR, IAM/OIDC) is a plain
   `aws_*` resource written in `terraform/modules/*`, not a call to
   `terraform-aws-modules/...`.
2. **All modules live under one `terraform/modules/` folder, called from a
   single `terraform/main.tf`.** One entry point, not several.
3. **Three environments (dev / nonprod / prod), three `.tfvars` files —
   no Terraform workspaces.** Each environment is a fully separate state
   file, initialized with its own `-backend-config`.
4. **Cost-minimal.** This is a personal project, not a company account —
   every default favors the cheapest viable option. See "Cost" below for
   the actual numbers and where they come from.

## Layout

```
terraform/
├── modules/
│   ├── vpc/                     # VPC, subnets, IGW, (optional) NAT
│   ├── eks/                     # cluster, managed node group, IAM, access entries
│   ├── rds/                     # catalogue's Postgres instance
│   ├── ecr/                     # one repo per service
│   └── github-oidc/             # GitHub OIDC provider + deploy role
├── environments/
│   ├── dev.tfvars
│   ├── nonprod.tfvars
│   └── prod.tfvars
├── backend-configs/              # one -backend-config per environment's state
│   ├── dev.hcl
│   ├── nonprod.hcl
│   └── prod.hcl
├── main.tf                       # the ONE entry point - calls every module
├── providers.tf, versions.tf, variables.tf, outputs.tf
```

`terraform/main.tf` is the only place any module is called from. There's
no separate directory for "shared" resources — see the next section for
how the two account-level singletons are handled without one.

## Handling the two account-level singletons

Two of the five modules produce resources that are unique per AWS account:
an ECR repository name and the GitHub OIDC provider URL can each only
exist once — creating them from all three `.tfvars`/state files would make
the 2nd and 3rd `terraform apply` fail with "already exists". (Docker
images are also built once per commit and the *same* tag is promoted
dev → nonprod → prod — see doc 2 — so per-environment ECR repos would be
the wrong model regardless.)

Rather than a separate `global/` stack, `terraform/main.tf` resolves this
with one boolean:

```hcl
locals {
  is_primary_environment = var.environment == "dev"
}
```

- `module.ecr` and `module.github_oidc` are only **created** when
  `environment = "dev"` (`count = local.is_primary_environment ? 1 : 0`).
- Every other environment (`nonprod`, `prod`) **looks the same resources
  up** by their deterministic name instead, via `data "aws_ecr_repository"`
  and `data "aws_iam_role"`.
- `local.github_actions_role_arn` and `local.ecr_repository_urls` pick
  whichever source (module output or data source) applies, so the rest of
  `main.tf` (e.g. `module.eks`'s `github_actions_role_arn` input) never
  needs to care which environment it's running as.

**Practical implication: apply `dev` at least once before `nonprod` or
`prod`** — see "One-time bootstrap" below. If you ever need to rebuild
`dev` from scratch, do it before touching the other two, or their data
source lookups will fail to find the ECR repos/role until `dev` exists
again.

## Per-environment resources

The rest of `main.tf` — `module.vpc`, `module.eks`, `module.rds` — runs
for every environment, each into its own state:

| Module | Creates |
|---|---|
| `module.vpc` | VPC, one public + one private subnet per AZ, one Internet Gateway, at most one NAT Gateway |
| `module.eks` | EKS cluster, one managed node group, cluster/node IAM roles, the `vpc-cni`/`kube-proxy`/`coredns` addons, and an EKS **access entry** granting the shared GitHub Actions role `AmazonEKSClusterAdminPolicy` on this cluster |
| `module.rds` | Postgres 15 for the `catalogue` service only (`voting` uses in-memory H2, `frontend`/`recommendation` are stateless — see the root README's per-service descriptions and `catalogue/db.create.py`) |

`module.eks` grants cluster access via **EKS access entries**
(`authentication_mode = "API"`), not the legacy `aws-auth` ConfigMap — this
means the module needs no Kubernetes/Helm Terraform provider and no
bootstrapping-order headaches between "cluster exists" and "can configure
Kubernetes RBAC".

No AWS Load Balancer Controller / Helm release either: `frontend`'s
Kubernetes Service is a plain `type: LoadBalancer` (see
`k8s/base/frontend.yaml`), which provisions a Network Load Balancer
directly through the in-cluster AWS cloud provider — no extra IRSA role,
IAM policy, or Helm chart to maintain for a single-frontend app.

## Environments: three `.tfvars`, three state files, no workspaces

```bash
cd terraform

# dev — apply this one FIRST (creates the shared ECR repos + OIDC role)
terraform init -backend-config=backend-configs/dev.hcl
terraform plan  -var-file=environments/dev.tfvars -var db_password="$TF_VAR_db_password"
terraform apply -var-file=environments/dev.tfvars -var db_password="$TF_VAR_db_password"

# nonprod / prod: same, swapping dev -> nonprod / prod throughout
```

Switching environments means re-running `terraform init -backend-config=...`
(Terraform will prompt to migrate/reinitialize — say yes, this is expected:
each environment's state genuinely lives in a different S3 key). Workspaces
were deliberately not used — with three fully independent `.tfvars` +
backend keys, there's no risk of running `terraform apply` against the
wrong environment because you forgot which workspace was selected.

| | `dev.tfvars` | `nonprod.tfvars` | `prod.tfvars` |
|---|---|---|---|
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` | `10.2.0.0/16` |
| AZs | 2 | 2 | 3 |
| NAT gateway | **no** (nodes in public subnets) | **no** | yes |
| Node capacity | 1× `t3.small` SPOT | 1-2× `t3.small` SPOT | 2-3× `t3.small` ON_DEMAND |
| RDS | `db.t3.micro`, single-AZ | `db.t3.micro`, single-AZ | `db.t3.micro`, single-AZ |
| Creates shared ECR/OIDC? | **yes** | no (looks them up) | no (looks them up) |

## Cost

The dominant, unavoidable cost is **the EKS control plane: ~$0.10/hr
(~$73/month) per cluster, for as long as it exists** — this is an AWS
fixed fee regardless of node size or whether anything is even running on
it. Since this is 3 separate environments = 3 separate clusters if all
were left running:

> **Never run all three environments at once if you can avoid it.**
> `terraform destroy -var-file=environments/dev.tfvars ...` an environment
> when you're done with your work session, and re-`apply` it next time —
> that's what having three independent state files buys you: destroying
> one has zero effect on the others. (Don't destroy `dev` while `nonprod`
> or `prod` are still applied, though — they look up the ECR repos/OIDC
> role `dev` created and would fail to find them.)

Everything else is tuned down accordingly:

- **No NAT gateway for dev/nonprod** (`enable_nat_gateway = false` in
  `terraform/modules/vpc`) — saves ~$32-35/month each by placing worker
  nodes in the public subnets instead. This is a real security trade-off
  (nodes get public IPs) accepted deliberately for a personal/learning
  project; `prod.tfvars` keeps the NAT gateway.
- **SPOT capacity for dev/nonprod nodes** — up to ~70% cheaper than
  on-demand `t3.small`; `prod.tfvars` uses ON_DEMAND to avoid SPOT
  interruptions.
- **`db.t3.micro`, single-AZ RDS everywhere** — free-tier eligible, no
  Multi-AZ standby to pay for.
- **A single NAT gateway for the whole VPC** even in prod (not one per
  AZ) — `terraform/modules/vpc/main.tf`.
- **ECR lifecycle policy** keeps only the last 10 images per repo
  (`terraform/modules/ecr`), so storage cost doesn't grow unbounded.

## One-time manual bootstrap

State storage and the IAM role the pipeline itself needs both have to
exist before any pipeline can run. Do this once, by hand, with your own
AWS credentials:

```bash
# 1. State backend (bucket + lock table every backend-configs/*.hcl points at)
aws s3api create-bucket --bucket craftista-terraform-state --region us-east-1
aws s3api put-bucket-versioning --bucket craftista-terraform-state \
  --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name craftista-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# 2. dev - MUST be first, it creates the shared ECR repos + GitHub OIDC role
cd terraform
terraform init -backend-config=backend-configs/dev.hcl
export TF_VAR_db_password="<choose a strong password>"
terraform apply -var-file=environments/dev.tfvars

# 3. Read the outputs dev just created and wire them into GitHub (doc 2's
#    "Required repository configuration" table) BEFORE applying nonprod/prod
#    from CI - the pipeline needs AWS_ROLE_ARN to authenticate at all.
terraform output github_actions_role_arn
terraform output ecr_repository_urls
terraform output catalogue_db_endpoint

# 4. nonprod / prod, whenever you actually want them running
terraform init -backend-config=backend-configs/nonprod.hcl
terraform apply -var-file=environments/nonprod.tfvars
terraform output catalogue_db_endpoint   # each environment has its own RDS
```

From this point on, `.github/workflows/terraform-deploy.yaml` handles
`plan` automatically and `apply`/`destroy` on manual `workflow_dispatch`,
authenticated as the role `dev` created.

## Variable reference

See `terraform/variables.tf` for the full list with defaults. Notable ones:

| Variable | Notes |
|---|---|
| `environment` | `dev` \| `nonprod` \| `prod`, validated |
| `enable_nat_gateway` | drives both NAT creation and which subnets nodes land in |
| `node_capacity_type` | `SPOT` or `ON_DEMAND` |
| `db_password` | *(required, no default)* — `TF_VAR_db_password` / CI secret only, never a committed `.tfvars` value |
| `github_repository` | restricts which repo's Actions runs can assume the deploy role (used only by the `dev` apply, which is the one that creates it) |
| `services` | which ECR repos to create (`dev`) / look up (`nonprod`, `prod`) |
| `environments` | every environment name that exists — used to build each one's EKS cluster ARN for the shared role's IAM policy, regardless of which environment is currently being applied |

## Destroying an environment

```bash
cd terraform
terraform init -backend-config=backend-configs/dev.hcl
terraform destroy -var-file=environments/dev.tfvars -var db_password="$TF_VAR_db_password"
```

All three environments default `deletion_protection = false` and
`skip_final_snapshot = true` on RDS specifically so `destroy` never gets
stuck — intentional for a personal project where the whole point is being
able to tear an environment down between sessions.
