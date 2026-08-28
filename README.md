# GKE 3-Tier Platform

The 3-tier Node.js app from [aws-3tier](https://github.com/mhassaankhokhar/aws-3tier)
rebuilt on Google Kubernetes Engine — same application, a Kubernetes-native data
and storage layer instead of managed AWS services.

```
Internet -> Ingress -> web (Node/Express)
                    -> api (Node/Express) -> PostgreSQL (CloudNativePG)
                          |
                          `-> shared uploads (Longhorn RWX)
```

## Why this exists

`aws-3tier` runs this application on ECS Fargate with RDS. This repo runs the
same application on Kubernetes with the database and shared storage inside the
cluster. Running one architecture two ways is the point — it shows which parts
are portable and which were really cloud-vendor features.

| | aws-3tier | gke-3tier |
|---|---|---|
| Compute | ECS Fargate | GKE (spot node pool) |
| Database | RDS PostgreSQL (managed) | CloudNativePG (in-cluster) |
| Shared storage | — | Longhorn (RWX) |
| Registry | ECR | Artifact Registry |
| CI/CD auth | GitHub OIDC → IAM role | GitHub OIDC → Workload Identity Federation |

## Storage, and why it is split

GKE's default `pd-balanced` StorageClass is **ReadWriteOnce** — a volume attaches
to one node at a time. Two replicas scheduled onto different nodes leave the
second stuck in `FailedAttachVolume`. A multi-node cluster needs a plan for this,
and the plan is not one-size-fits-all:

- **PostgreSQL — ReadWriteOnce, one volume per instance.** CloudNativePG
  replicates at the database layer. Postgres on shared NFS-backed storage invites
  locking and fsync problems; it is the wrong tool for the job.
- **Shared user content — ReadWriteMany, via Longhorn.** Uploads have to be
  visible to every web/api replica, and that is what RWX actually exists for.

Longhorn rather than Filestore (GCP's managed NFS), on purpose: it runs on any
cluster, so these manifests still work on a local k3d cluster once the trial
credit is gone.

## Layout

```
terraform/
  bootstrap/             identity only — applied once, by hand, own state
  infra/                 network, cluster, registry — applied by CI, own state
  modules/
    network/             VPC, private subnets, Cloud NAT
    gke/                 cluster + spot node pool, Workload Identity enabled
    artifact-registry/   container images
    iam/                 scoped service accounts
    workload-identity/   GitHub OIDC → GCP
k8s/
  base/
    web/  api/           the application
    postgres/            CloudNativePG cluster
    longhorn/            RWX StorageClass
  overlays/dev/
argocd/                  app-of-apps definitions
.github/workflows/       CI (no credentials) + CD (OIDC, no stored keys)
docs/                    decisions worth writing down
```

## Cost posture

Built to outlive the trial credit rather than depend on it:

- **Spot node pool** — preemptible nodes cost a fraction of on-demand.
- **Everything in Terraform** — `terraform destroy` in `infra/` when idle,
  re-apply to rebuild. Nothing is click-configured and therefore unrecoverable.
  The pipeline's own identity lives in `bootstrap/` with a separate state, so
  that destroy cannot take the credentials needed to rebuild.
- **No managed data services** — database and storage are portable, so the whole
  stack can move to k3d or any other Kubernetes when the credit ends.

## Status

Scaffolding. Nothing is provisioned yet.

## License

MIT — see [LICENSE](LICENSE). Built by Mohammad Hassan Ur Rehman.

The `api/` and `web/` services are carried over from this author's
[aws-3tier](https://github.com/mhassaankhokhar/aws-3tier) project.
