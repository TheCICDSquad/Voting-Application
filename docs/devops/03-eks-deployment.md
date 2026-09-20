# 3. EKS — Kubernetes Deployment

## Manifest layout

```
k8s/
├── base/
│   ├── namespace.yaml          # craftista namespace
│   ├── frontend.yaml           # ConfigMap + Deployment + Service (type: LoadBalancer)
│   ├── catalogue.yaml          # Secret (DB config) + Deployment + Service
│   ├── voting.yaml             # Deployment + Service
│   ├── recommendation.yaml     # ConfigMap + Deployment + Service
│   └── kustomization.yaml
└── overlays/
    ├── dev/kustomization.yaml       # 1 replica/service, pins images per deploy
    ├── nonprod/kustomization.yaml   # 1 replica/service, pins images per deploy
    └── prod/kustomization.yaml      # base's 2 replicas/service, pins images per deploy
```

`base` is the environment-agnostic definition of the app. Each of the
three environments in `terraform/environments/*.tfvars` (doc 4) gets its
own EKS cluster, so it also gets its own overlay — `application-deploy.yaml`
(doc 2) applies `k8s/overlays/<env>` against that environment's cluster and
pins each service's image tag there via `kustomize edit set image`.

## Why each app's config is delivered as a mounted file, not env vars

None of the four services were written to read Kubernetes-style env vars
for their settings — they each load a `config.json`
(`frontend/config.json`, `catalogue/config.json`,
`recommendation/config.json`) or `application.properties` (`voting`) from
disk at startup. Rather than patch application code, the manifests mount a
ConfigMap or Secret over that exact file path:

```yaml
volumeMounts:
  - name: config
    mountPath: /app/config.json
    subPath: config.json
```

This overrides the copy baked into the image at build time with the
cluster's version, so environment-specific values (service DNS names, DB
credentials) never need to be hardcoded into a Docker image.

## Service-to-service networking

Kubernetes Services provide stable DNS names inside the cluster — no
service mesh or discovery system needed at this scale:

| Caller | Calls | Via |
|---|---|---|
| `frontend` | catalogue, voting, recommendation | `http://catalogue:5000`, `http://voting:8080`, `http://recommendation:8080` (baked into `frontend-config` ConfigMap) |
| `voting` | catalogue | `http://catalogue:5000/api/products` (default in `application.properties`, matches the `catalogue` Service name — no override needed) |

Only `frontend` is exposed outside the cluster — `catalogue`, `voting` and
`recommendation` are `ClusterIP` only.

## External access: a plain NLB, not an Ingress controller

`frontend`'s Service is `type: LoadBalancer` with the
`service.beta.kubernetes.io/aws-load-balancer-type: nlb` annotation (see
`k8s/base/frontend.yaml`). On `kubectl apply`, EKS's built-in AWS cloud
provider integration provisions a Network Load Balancer directly — no
Ingress resource, no AWS Load Balancer Controller, no Helm release, no
extra IRSA role/IAM policy. For a single public-facing service, that
machinery would be pure overhead; add an Ingress + the LB Controller later
only if a second externally-routable service or host-based routing
actually shows up.

```bash
kubectl -n craftista get svc frontend
# EXTERNAL-IP column is the NLB's DNS name once provisioned (takes ~1-2 min)
```

## Secrets

`catalogue-config` (in `k8s/base/catalogue.yaml`) holds the Postgres
connection details including the DB password. The committed version has
placeholder values (`REPLACE_WITH_RDS_ENDPOINT` /
`REPLACE_WITH_RDS_PASSWORD`) — the real, per-environment values are
injected by the deploy pipeline from that environment's GitHub Environment
variables/secrets on every catalogue deploy (see doc 2). This is a plain
Kubernetes `Secret` (base64-encoded, not encrypted at rest by default);
for a stricter setup later, swap it for [External Secrets
Operator](https://external-secrets.io/) pulling from AWS Secrets Manager,
or [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets).

## Cluster access

`terraform/modules/eks` grants access via **EKS access entries**
(`authentication_mode = "API"`) rather than the legacy `aws-auth`
ConfigMap: the Terraform applier gets cluster-admin automatically
(`bootstrap_cluster_creator_admin_permissions = true`), and the shared
GitHub Actions role gets an explicit access entry with
`AmazonEKSClusterAdminPolicy`. To grant yourself (or a teammate) access to
a cluster you didn't personally apply:

```bash
aws eks create-access-entry --cluster-name craftista-dev-eks --principal-arn <your-iam-arn>
aws eks associate-access-policy --cluster-name craftista-dev-eks \
  --principal-arn <your-iam-arn> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

## Resource requests/limits & probes

Every Deployment sets CPU/memory `requests` and `limits` sized to what
each service actually needs (`voting`'s JVM gets the most headroom;
`recommendation`'s Go binary the least), plus `readinessProbe` /
`livenessProbe` against each service's home route (or
`/api/recommendation-status` for `recommendation`). These are conservative
starting points sized to fit comfortably on a single `t3.small` node
(dev/nonprod's default) — see doc 4's "Cost" section for why dev/nonprod
run only 1-2 such nodes.

## Operating the cluster

```bash
# Point kubectl at one environment's cluster (also printed as a Terraform output)
aws eks update-kubeconfig --region <region> --name craftista-<dev|nonprod|prod>-eks

# See everything
kubectl -n craftista get pods,deploy,svc

# Follow logs for one service
kubectl -n craftista logs -f deployment/catalogue

# Manually roll back a bad deploy (see doc 2 for the Git-level follow-up)
kubectl -n craftista rollout undo deployment/catalogue

# Scale a service manually (dev/nonprod only really have room for 1 pod each
# per service given the node sizing above)
kubectl -n craftista scale deployment/frontend --replicas=2
```

## Local sanity check before pushing to EKS

`kustomize build` renders the exact manifests CI/CD would apply — run it
locally to catch YAML/kustomize errors before they hit a pipeline run:

```bash
kustomize build k8s/overlays/dev | kubectl apply --dry-run=client -f -
```
