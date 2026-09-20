# Deploying Craftista

This is a linear, copy-paste runbook for taking a fresh clone of this repo to a
running deployment on Amazon EKS. It consolidates the deeper reference docs in
[docs/devops/](docs/devops/) into one sequence — read those for the *why*
behind any step here; this file is the *how*, in order.

**Time to first deploy:** roughly 30-40 minutes, most of it waiting on
`terraform apply` to provision the EKS cluster.

**Cost:** the EKS control plane alone is ~$0.10/hr (~$73/month) for as long
as it exists. This repo is built to run one environment at a time — see
[docs/devops/04-terraform-infrastructure.md](docs/devops/04-terraform-infrastructure.md#cost)
before you leave anything running.

---

## 0. Prerequisites

| Tool | Used for | Check |
|---|---|---|
| [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), with credentials for an account you can create resources in | everything | `aws sts get-caller-identity` |
| [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.6 | infrastructure | `terraform version` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | talking to the cluster | `kubectl version --client` |
| [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) | applying the k8s manifests | `kustomize version` |
| [Docker](https://docs.docker.com/get-docker/) | building images locally, if not relying on CI | `docker version` |
| A GitHub account with push access to your fork/copy of this repo | CI/CD | — |

You do **not** need Node, Python, Java or Go installed locally to deploy —
each service builds inside its own Docker image. You'd only need those
toolchains to run a service outside a container.

---

## 1. Clone and check the layout

```bash
git clone <your-fork-url> craftista
cd craftista
```

```
frontend/  catalogue/  voting/  recommendation/   # the 4 services + their Dockerfiles
k8s/base/, k8s/overlays/{dev,nonprod,prod}/        # Kubernetes manifests (kustomize)
terraform/                                         # infrastructure as code
.github/workflows/                                 # the 2 CI/CD pipelines
docs/devops/                                        # architecture & design docs
```

---

## 2. One-time AWS bootstrap

Terraform's own state has to exist before `terraform init` will work. Pick a
region (examples below use `us-east-1`) and, with your own AWS credentials:

```bash
aws s3api create-bucket --bucket craftista-terraform-state --region us-east-1
aws s3api put-bucket-versioning --bucket craftista-terraform-state \
  --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name craftista-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

If you use a bucket name other than `craftista-terraform-state`, update it in
every file under `terraform/backend-configs/*.hcl`.

---

## 3. Apply the `dev` environment (must be first)

`dev` is special: it's the environment that creates the two account-level
singletons — the ECR repositories and the GitHub OIDC deploy role — that
`nonprod` and `prod` look up rather than recreate. See
[docs/devops/04-terraform-infrastructure.md](docs/devops/04-terraform-infrastructure.md)
for why.

```bash
cd terraform
terraform init -backend-config=backend-configs/dev.hcl

export TF_VAR_db_password="choose-a-strong-password"   # never commit this

terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

This creates: a VPC, an EKS cluster (`craftista-dev-eks`) with one SPOT
node, an RDS Postgres instance for the `catalogue` service, 4 ECR
repositories, and the GitHub Actions OIDC role.

When it finishes, capture the outputs you'll need next:

```bash
terraform output github_actions_role_arn
terraform output ecr_repository_urls
terraform output catalogue_db_endpoint
terraform output configure_kubectl
```

---

## 4. Point kubectl at the cluster

```bash
$(terraform output -raw configure_kubectl)
kubectl get nodes          # should show 1 node
```

---

## 5. Deploy the app manually (first deploy, before CI/CD is wired up)

Build and push each service's image to the ECR repos `dev` just created,
then apply the manifests. Replace `<account-id>`/`<region>` with your own
(from `terraform output ecr_repository_urls`):

```bash
cd ..   # back to repo root
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

for svc in frontend catalogue voting recommendation; do
  docker build -t <account-id>.dkr.ecr.us-east-1.amazonaws.com/craftista-$svc:v1 ./$svc
  docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/craftista-$svc:v1
done
```

Point the `dev` overlay at those images and apply:

```bash
cd k8s/overlays/dev
for svc in frontend catalogue voting recommendation; do
  kustomize edit set image craftista-$svc=<account-id>.dkr.ecr.us-east-1.amazonaws.com/craftista-$svc:v1
done
kubectl apply -k .
cd ../../..
```

Now put the **real** catalogue database credentials in place (the committed
manifest ships with placeholder values on purpose — see
[docs/devops/01-git-workflow.md](docs/devops/01-git-workflow.md#secrets-hygiene)):

```bash
DB_HOST=$(terraform -chdir=terraform output -raw catalogue_db_endpoint)
kubectl -n craftista create secret generic catalogue-config \
  --from-literal=config.json="$(jq -n --arg host "$DB_HOST" --arg pass "$TF_VAR_db_password" \
    '{app_version:"1.0.0",data_source:"db",db_host:$host,db_name:"catalogue",db_user:"devops",db_password:$pass}')" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n craftista rollout restart deployment/catalogue
```

Check everything came up, then find the URL:

```bash
kubectl -n craftista get pods
kubectl -n craftista get svc frontend   # EXTERNAL-IP is the app's URL (takes ~1-2 min to provision)
```

---

## 6. Wire up CI/CD (so you never have to do step 5 by hand again)

In your GitHub repo, **Settings → Secrets and variables → Actions**:

**Repository variables** (Variables tab):

| Name | Value |
|---|---|
| `AWS_ROLE_ARN` | the `github_actions_role_arn` output from step 3 |
| `AWS_REGION` | e.g. `us-east-1` |

**Environments** (Settings → Environments) — create `dev`, `nonprod`,
`prod`. On each one, add:

| Name | Type | Value |
|---|---|---|
| `CATALOGUE_DB_HOST` | Variable | that environment's `catalogue_db_endpoint` output |
| `CATALOGUE_DB_PASSWORD` | Secret | the `db_password` you applied that environment with |

From here on:
- Push to `main` touching a service folder → tests, an Aqua Trivy image
  scan, then an automatic deploy to **dev**.
- Push/PR touching `terraform/**` → Checkov + Trivy IaC scan, then a plan
  for all three environments.
- Promoting to `nonprod`/`prod`, and every `terraform apply`/`destroy`, is
  a manual `workflow_dispatch` run on the relevant workflow (see
  [docs/devops/02-cicd-pipeline.md](docs/devops/02-cicd-pipeline.md)).

---

## 7. (Optional) Bring up `nonprod` / `prod`

Same shape as step 3, once `dev` exists:

```bash
cd terraform
terraform init -backend-config=backend-configs/nonprod.hcl
terraform apply -var-file=environments/nonprod.tfvars -var db_password="$TF_VAR_db_password"
```

Then add that environment's `CATALOGUE_DB_HOST`/`CATALOGUE_DB_PASSWORD` to
its GitHub Environment (step 6) and either deploy manually (step 5, against
`k8s/overlays/nonprod`) or promote via
`application-deploy.yaml`'s `workflow_dispatch`.

---

## 8. Tearing an environment down

```bash
cd terraform
terraform init -backend-config=backend-configs/dev.hcl
terraform destroy -var-file=environments/dev.tfvars -var db_password="$TF_VAR_db_password"
```

Don't destroy `dev` while `nonprod`/`prod` are still up — they depend on
the ECR repos and OIDC role it created.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `terraform apply` on nonprod/prod fails looking up an ECR repo or IAM role | `dev` hasn't been applied yet in this account — it must go first |
| Pods stuck `ImagePullBackOff` | image tag doesn't exist in ECR yet, or `aws-auth`/node IAM role can't pull — check `terraform output ecr_repository_urls` matches the overlay's `kustomization.yaml` |
| `catalogue` pod crash-looping | `catalogue-config` Secret still has the placeholder `REPLACE_WITH_RDS_*` values — redo the `kubectl create secret` step above |
| GitHub Actions can't assume the AWS role | `AWS_ROLE_ARN` repo variable is wrong/missing, or the workflow isn't running on `refs/heads/main` (the trust policy is scoped to that ref) |
| `frontend` Service has no `EXTERNAL-IP` | still provisioning (wait ~2 min), or the account/region has no default VPC ELB permissions — check `kubectl -n craftista describe svc frontend` |

For anything deeper, see the full docs: [docs/devops/README.md](docs/devops/README.md).
