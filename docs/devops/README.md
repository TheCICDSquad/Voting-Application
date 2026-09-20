# Craftista DevOps Documentation

This is the deployment documentation for Craftista, the polyglot microservices
app in this repo. It covers the four pieces needed to take the four services
in this repo to production on EKS:

| # | Area | Document | What it covers |
|---|------|----------|-----------------|
| 1 | Version control | [01-git-workflow.md](01-git-workflow.md) | Branching model, commit conventions, PR/review rules, tagging & releases |
| 2 | CI/CD | [02-cicd-pipeline.md](02-cicd-pipeline.md) | The two GitHub Actions pipelines (terraform, application), IaC/image scanning, promotion flow |
| 3 | Runtime platform | [03-eks-deployment.md](03-eks-deployment.md) | Kubernetes/EKS architecture, manifests, secrets, scaling, rollbacks |
| 4 | Infrastructure | [04-terraform-infrastructure.md](04-terraform-infrastructure.md) | Hand-rolled Terraform modules, the 3-environment/3-tfvars setup, cost tuning |

## The application

Craftista is four independently deployable services (see the root
[README.md](../../README.md) for the product description):

| Service | Language / framework | Port | State |
|---|---|---|---|
| `frontend` | Node.js / Express | 3000 | Stateless |
| `catalogue` | Python / Flask | 5000 | Postgres (RDS in each environment, JSON file in local dev) |
| `voting` | Java / Spring Boot | 8080 | H2 in-memory |
| `recommendation` | Go / Gin | 8080 | Stateless |

`frontend` is the only service reachable from outside the cluster (a plain
Network Load Balancer — see doc 3); it calls the other three over their
internal Kubernetes Service DNS names (`catalogue`, `voting`,
`recommendation`).

## Three environments, not one

`dev`, `nonprod` and `prod` are three **fully separate** stacks — separate
VPC, separate EKS cluster, separate RDS instance each — selected via
`terraform/environments/{dev,nonprod,prod}.tfvars` (no Terraform
workspaces) and deployed to via `k8s/overlays/{dev,nonprod,prod}`. Because
an EKS control plane costs money for every hour it exists regardless of
load, **this project is tuned to run one environment at a time** and be
`terraform destroy`'d when you're done — see doc 4's "Cost" section before
applying anything.

## What's in the repo

```
.
├── frontend/Dockerfile, catalogue/Dockerfile, voting/Dockerfile,
│   recommendation/Dockerfile        # one image per service
├── .github/workflows/
│   ├── terraform-deploy.yaml        # Pipeline 1: Checkov + Trivy IaC scan, plan/apply/destroy
│   └── application-deploy.yaml      # Pipeline 2: test, Aqua Trivy image scan, build, deploy, promote
├── k8s/base, k8s/overlays/{dev,nonprod,prod}   # Kubernetes manifests, kustomize
├── terraform/
│   ├── main.tf                      # the ONE entry point - calls every module
│   ├── modules/{vpc,eks,rds,ecr,github-oidc}/  # hand-rolled, no registry modules
│   └── environments/*.tfvars        # dev / nonprod / prod, one file each
└── docs/devops/                     # you are here
```

## End-to-end bootstrap order

This system is chicken-and-egg on a brand-new AWS account (the pipelines
deploy to infrastructure that Terraform creates, and part of that
infrastructure is the IAM role the pipelines authenticate as). Bootstrap
once, in this order:

1. **Git**: fork/clone the repo, protect `main` — see doc 1.
2. **Terraform `dev`**: create the S3 state bucket + DynamoDB lock table by
   hand, then `terraform apply -var-file=environments/dev.tfvars` locally
   with your own AWS credentials. `dev` must go first — it's the one that
   creates the shared ECR repos + GitHub OIDC role that `nonprod`/`prod`
   look up (see doc 4).
3. **GitHub Actions config**: set the repo variables (`AWS_ROLE_ARN`,
   `AWS_REGION`) from `dev`'s outputs, and, per GitHub Environment
   (`dev`/`nonprod`/`prod`), `CATALOGUE_DB_HOST` / `CATALOGUE_DB_PASSWORD`
   — see doc 2.
4. **Terraform `nonprod`/`prod`** (optional, whenever you actually want
   them running): apply locally, or via `terraform-deploy.yaml`'s manual
   `workflow_dispatch` once step 3 is done — see doc 4.
5. From here on: every push to `main` that touches a service directory
   tests, scans, builds and auto-deploys to `dev`; promoting to
   `nonprod`/`prod` is a manual `workflow_dispatch` on
   `application-deploy.yaml`; every push touching `terraform/**` is
   scanned and planned automatically, with apply/destroy always manual.
