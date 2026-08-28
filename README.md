# GKE MLOps Platform

A GitOps-managed platform on Google Kubernetes Engine: the 3-tier Node.js app
from [aws-3tier](https://github.com/mhassaankhokhar/aws-3tier) redeployed on GCP,
alongside an MLflow tracking server and a small LLM inference service — with
Istio service mesh, autoscaling, and Kubernetes RBAC.

```
Internet -> Istio Ingress Gateway -> VirtualService
                                       |-- web  (Node/Express)
                                       |-- api  (Node/Express) -> Cloud SQL
                                       |-- mlflow (tracking + registry) -> GCS
                                       `-- llm  (inference) -> model from GCS
```

## Why this exists

The same workload runs on AWS in `aws-3tier`. This repo is the GCP half: the
portable pieces (containers, Kubernetes manifests, GitOps) stay the same, and
everything cloud-specific lives behind a Terraform module boundary. Running one
architecture on two clouds is the point — it shows what actually transfers.

## Layout

```
terraform/
  modules/
    network/             VPC, private subnets, Cloud NAT
    gke/                 cluster + spot node pool, Workload Identity enabled
    artifact-registry/   container images
    storage/             GCS bucket for MLflow artifacts
    workload-identity/   GitHub OIDC -> GCP, and KSA -> GSA bindings
  envs/dev/              the only environment; small on purpose
k8s/
  base/{api,web,mlflow,llm}   deployments, services, HPA, RBAC
  overlays/dev/               kustomize overlay
argocd/                  app-of-apps definitions
.github/workflows/       CI (no credentials) + CD (OIDC, no stored keys)
docs/                    architecture notes and decisions
```

## Cost posture

Built to survive the free trial expiring, not to depend on it:

- **Spot node pool** — preemptible nodes are a fraction of on-demand.
- **Everything in Terraform** — `terraform destroy` when idle, re-apply to
  rebuild. Nothing here is click-configured and therefore unrecoverable.
- **Components split into separate ArgoCD apps** — the LLM service (the heaviest
  piece) can be switched off without touching the rest.

## Status

Scaffolding. Nothing is deployed yet — see `docs/` as decisions get recorded.

## License

MIT — see [LICENSE](LICENSE). Built by Mohammad Hassan Ur Rehman.

The `api/` and `web/` services are carried over from this author's
[aws-3tier](https://github.com/mhassaankhokhar/aws-3tier) project.
