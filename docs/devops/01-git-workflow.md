# 1. Git — Version Control Workflow

## Repository layout

Craftista is a **monorepo**: `frontend/`, `catalogue/`, `voting/` and
`recommendation/` each own their own Dockerfile and tests, and share one
Git history plus one CI/CD workflow (`application-deploy.yaml`) that only
tests/builds/deploys whichever services actually changed. This keeps
cross-service changes (e.g. a new API field that both `frontend` and
`catalogue` need) in a single reviewable PR — see
[02-cicd-pipeline.md](02-cicd-pipeline.md).

## Branching model

Trunk-based development with short-lived feature branches:

- `main` is always deployable. It is protected: no direct pushes, PRs
  require at least one approval and a passing CI run before merge.
- Work happens on branches named `<type>/<short-description>`, e.g.
  `feat/catalogue-search`, `fix/voting-null-pointer`,
  `chore/bump-node-version`. Branch from and merge back into `main`.
- Merge via **squash merge** so `main`'s history is one commit per
  reviewed change, and that commit is what CI/CD tags images with
  (`${{ github.sha }}` in the build workflow — see doc 2).
- Delete branches after merge (GitHub setting: "Automatically delete head
  branches").

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/):
`<type>(<scope>): <summary>`, where `<scope>` is the service name when the
change is scoped to one, e.g.:

```
feat(catalogue): add pagination to /api/products
fix(voting): handle missing origami id in vote request
chore(terraform): bump EKS module to 20.x
```

`type` is one of `feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `ci`.
This is what a future changelog or release-notes generator would key off
of — it isn't enforced by tooling here, but keep it consistent by convention
and PR review.

## Pull requests

- One PR per logical change; keep it scoped to a single service where
  possible so only that service's job in the `application-deploy.yaml`
  test matrix runs.
- PR description states *why*, not just *what* — link the issue/ticket if
  there is one.
- Required checks before merge (configured as GitHub branch protection
  rules on `main`): the `test` job(s) in `application-deploy.yaml` for any
  changed service, and/or the `scan`/`plan` jobs in `terraform-deploy.yaml`
  for `terraform/**` changes. See doc 2 for what each checks.
- Terraform changes (`terraform/**`) always get their own PR — never
  bundle infra changes into an application PR.

## Tags & releases

Each service's Docker image is tagged with the Git commit SHA that built
it (see `k8s/overlays/<env>/kustomization.yaml`, which pins the deployed
tag per service per environment), so the exact commit running in any
environment is always traceable via
`kubectl get deployment -n craftista -o wide` or the `image:` field in
that overlay.

For human-facing release points (e.g. "this is what shipped for the
2024-06 milestone"), tag `main` directly:

```
git tag -a v1.3.0 -m "Add search to catalogue, fix voting race condition"
git push origin v1.3.0
```

This is independent of and lighter-weight than the deploy pipeline — it's
for release notes and rollback reference, not a build trigger.

## Secrets hygiene

`terraform/environments/*.tfvars` and `terraform/backend-configs/*.hcl`
*are* committed — they hold no secrets, only sizing/naming per
environment. What must never be committed is a real `db_password` value
(only ever passed as `TF_VAR_db_password` or a CI secret — see
`terraform/variables.tf`), `k8s/**/*.yaml` with real credentials filled
in, or any `.env` file — see the root [.gitignore](../../.gitignore). Real
secret values (DB password, AWS role ARN) live in GitHub Actions
repo/Environment secrets and are injected at CI/CD time, never in the
working tree. `k8s/base/catalogue.yaml` ships with a placeholder
`REPLACE_WITH_RDS_PASSWORD` for exactly this reason.
