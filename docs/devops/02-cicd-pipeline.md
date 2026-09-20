# 2. GitHub Actions — CI/CD Pipeline

Exactly two workflow files, matching the two concerns that change on
different rhythms: infrastructure and application code.

```
.github/workflows/
├── terraform-deploy.yaml     # infra: Checkov + Trivy IaC scan, plan, manual apply/destroy
└── application-deploy.yaml   # all 4 services: test, Aqua Trivy image scan, build, deploy
```

## Pipeline 1: `terraform-deploy.yaml`

Triggers: any push/PR touching `terraform/**`, plus manual `workflow_dispatch`.

```
push/PR  → scan (Checkov + Trivy IaC) → plan all 3 environments (dev, nonprod, prod)
workflow_dispatch(environment, action) → scan → apply/destroy that ONE environment only
```

- **scan** — `terraform fmt -check`, then two IaC scanners against the
  whole `terraform/` tree:
  - **Checkov** (`bridgecrewio/checkov-action`) — broad misconfiguration
    coverage. Runs `soft_fail: true`: findings are uploaded to the repo's
    Security tab (SARIF) but don't fail the build — Checkov's default
    ruleset is broad enough that blocking on every finding on a personal
    project isn't practical.
  - **Trivy** (`aquasecurity/trivy-action`, `scan-type: config`) —
    misconfigurations *and* accidentally-committed secrets in `.tf`/
    `.tfvars` files. Runs with `exit-code: 1` on CRITICAL/HIGH: this one
    **does** block the pipeline.
- **plan** — runs `terraform plan` for all three environments (`dev`,
  `nonprod`, `prod` — one shared `main.tf`/`modules/`, three independent
  states) on every push/PR, purely so a reviewer can see the blast radius
  of a `terraform/modules/**` change across every environment. Never
  applies anything.
- **apply** — only runs on a manual `workflow_dispatch`, where you choose
  exactly one `environment` (`dev`/`nonprod`/`prod`) and one `action`
  (`plan`/`apply`/`destroy`). This is deliberate: on a cost-sensitive
  personal project, infrastructure changes — especially ones that spin up
  a ~$73/mo EKS control plane — should never land unattended on a merge.
  Use `destroy` here to tear an environment down when you're done with it
  (see doc 4's "Cost" section).

## Pipeline 2: `application-deploy.yaml`

Triggers: push/PR touching any of the four service folders, plus manual
`workflow_dispatch` to promote.

```
push/PR  → detect-changes → test (only changed services)
push to main → build → Aqua Trivy image scan → push to ECR → deploy to dev
workflow_dispatch(environment: nonprod|prod) → promote (redeploy, no rebuild)
```

- **detect-changes** — `dorny/paths-filter` figures out which of
  `frontend/catalogue/voting/recommendation` actually changed, so (for
  example) a `catalogue`-only PR doesn't rebuild the other three.
- **test** — a matrix over the changed services, each using its native
  toolchain: `npm test`, `python -m unittest`, `mvn test`, `go test ./...`.
  This is the required status check for merging into `main`.
- **build-scan-push-deploy** *(push to `main` only)* — for each changed
  service: build the image, **Aqua Trivy scans it straight out of the
  local Docker daemon** (`scan-type: image`, CRITICAL/HIGH,
  `exit-code: 1`) *before* anything is pushed to ECR, then push, then
  `kustomize edit set image` + `kubectl apply -k k8s/overlays/dev` and
  wait for rollout. Every push to `main` auto-deploys to **dev only** —
  see promotion below for nonprod/prod.
- **promote** *(manual `workflow_dispatch` only)* — redeploys the image
  already tagged `:<git-sha>` in ECR (built and scanned by the job above)
  into `nonprod` or `prod`. It does **not** rebuild or rescan — the same
  bytes that ran in dev get promoted, which is the point of tagging images
  by commit SHA rather than `latest`. If a commit was never built through
  the dev pipeline, promoting it will fail with `ImagePullBackOff` since
  that tag was never pushed — promote what's already been tested in dev.

Both application-pipeline jobs run their per-service matrix with
`max-parallel: 1`: every matrix entry ends by committing the updated image
tag to `k8s/overlays/<env>/kustomization.yaml` and pushing to `main` — running
services concurrently would race multiple pushes against that one file.

## Authentication: GitHub OIDC, no long-lived AWS keys

Every AWS-touching step uses `aws-actions/configure-aws-credentials` with
`role-to-assume: ${{ vars.AWS_ROLE_ARN }}` — a short-lived token minted via
GitHub's OIDC provider, not a static access key. One shared role — created
once, by the `dev` environment's apply (`module.github_oidc` in
`terraform/main.tf`, guarded by `is_primary_environment` — see doc 4) — is
used across both pipelines and all three environments; its trust policy
restricts *who* can assume it (this repo, `refs/heads/main` only) but not
*which* environment it can touch — the pipelines themselves decide that
via which cluster/overlay they target.

## Required GitHub configuration

**Repository variables** (shared across all environments/pipelines):

| Name | Value comes from |
|---|---|
| `AWS_ROLE_ARN` | `dev`'s `terraform output github_actions_role_arn` |
| `AWS_REGION` | e.g. `us-east-1` |

**GitHub Environments** — create `dev`, `nonprod` and `prod` Environments
(Settings → Environments). Each job that touches a specific environment
declares `environment: <name>`, so GitHub resolves environment-scoped
secrets/variables automatically, and Environment protection rules (e.g.
"require reviewer approval") gate `nonprod`/`prod` deploys and applies if
you turn them on. Set these **per environment**:

| Name | Type | Value comes from |
|---|---|---|
| `CATALOGUE_DB_HOST` | Variable | that environment's `terraform output catalogue_db_endpoint` |
| `CATALOGUE_DB_PASSWORD` | Secret | the `db_password` you applied that environment with |

## The bootstrap chicken-and-egg

`AWS_ROLE_ARN` is *created by* the `dev` environment's apply, but both
pipelines *use* `AWS_ROLE_ARN` to authenticate. On a brand-new setup:
apply `dev` locally with your own credentials first (doc 4), copy its
`github_actions_role_arn` output into the repo variable, and only then
rely on the pipelines for everything after — including applying `nonprod`
and `prod`.

## Rollback

Every deploy ends with a commit bumping one service's image tag in a
`k8s/overlays/<env>/kustomization.yaml`. To roll back: revert that commit
on `main` and re-run `promote` (or manually
`kustomize edit set image craftista-<service>=<previous-sha-image>` +
`kubectl apply -k k8s/overlays/<env>`) — or, for an immediate fix,
`kubectl -n craftista rollout undo deployment/<service>` directly against
the cluster, followed by the Git-level revert so the repo matches reality
again.
