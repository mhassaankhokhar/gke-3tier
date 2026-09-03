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

## Architecture Deck

<details>
<summary><strong>11-slide walkthrough</strong> — architecture, infrastructure, the four pillars, and measured capacity. Click to expand, then use the <strong>Next →</strong> link under each slide.</summary>

> GitHub's README viewer doesn't run JavaScript, so this isn't a real slide player —
> each "Next" jumps to the next image further down this page rather than swapping one
> frame for another. It works, but it's a long scroll, not a deck. The source
> [`.pptx`](docs/deck/gke-3tier-full-deck.pptx) is in this repo if you'd rather flip
> through it in PowerPoint.

<a id="deck-1"></a>
<p align="center"><img src="docs/deck/slide-01.jpg" width="820" alt="Slide 1 — Title"></p>
<p align="center"><a href="#deck-2">Next →</a></p>

---

<a id="deck-2"></a>
<p align="center"><img src="docs/deck/slide-02.jpg" width="820" alt="Slide 2 — Key Points"></p>
<p align="center"><a href="#deck-1">← Prev</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#deck-3">Next →</a></p>

---

<a id="deck-3"></a>
<p align="center"><img src="docs/deck/slide-03.jpg" width="820" alt="Slide 3 — The Goal"></p>
<p align="center"><a href="#deck-2">← Prev</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#deck-4">Next →</a></p>

---

<a id="deck-4"></a>
<p align="center"><img src="docs/deck/slide-04.jpg" width="820" alt="Slide 4 — Architecture Diagram"></p>
<p align="center"><a href="#deck-3">← Prev</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#deck-5">Next →</a></p>

---

<a id="deck-5"></a>
<p align="center"><img src="docs/deck/slide-05.jpg" width="820" alt="Slide 5 — Infrastructure Highlights"></p>
<p align="center"><a href="#deck-4">← Prev</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#deck-6">Next →</a></p>

---

<a id="deck-6"></a>
<p align="center"><img src="docs/deck/slide-06.jpg" width="820" alt="Slide 6 — High Performance"></p>
<p align="center"><a href="#deck-5">← Prev</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#deck-7">Next →</a></p>

---

<a id="deck-7"></a>
<p align="center"><img src="docs/deck/slide-07.jpg" width="820" alt="Slide 7 — Resilience"></p>
<p align="center"><a href="#deck-6">← Prev</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#deck-8">Next →</a></p>

---

<a id="deck-8"></a>
<p align="center"><img src="docs/deck/slide-08.jpg" width="820" alt="Slide 8 — Secure"></p>
<p align="center"><a href="#deck-7">← Prev</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#deck-9">Next →</a></p>

---

<a id="deck-9"></a>
<p align="center"><img src="docs/deck/slide-09.jpg" width="820" alt="Slide 9 — Cost Optimized"></p>
<p align="center"><a href="#deck-8">← Prev</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#deck-10">Next →</a></p>

---

<a id="deck-10"></a>
<p align="center"><img src="docs/deck/slide-10.jpg" width="820" alt="Slide 10 — Measured Capacity"></p>
<p align="center"><a href="#deck-9">← Prev</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#deck-11">Next →</a></p>

---

<a id="deck-11"></a>
<p align="center"><img src="docs/deck/slide-11.jpg" width="820" alt="Slide 11 — Summary"></p>
<p align="center"><a href="#deck-10">← Prev</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#deck-1">↺ Back to start</a></p>

</details>

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

That portability has a price, and it is worth naming: Longhorn needs `iscsiadm`
and the `iscsi_tcp` module on the host, which no GKE node image provides —
Longhorn's docs recommend Ubuntu on GKE "since it contains open-iscsi already",
but on a GKE Ubuntu 24.04 node it does not. The requirement is met by Longhorn's
GKE COS node agent, a privileged DaemonSet that loads the module and runs
`iscsid` in a container. A managed RWX service would not have needed that.

## Layout

```
terraform/
  bootstrap/             identity only — applied once, by hand, own state
  envs/dev/              network, cluster, registry — applied by CI, own state
                         one directory per environment, each with its own state;
                         not CLI workspaces, which share a backend and credentials
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
- **Everything in Terraform** — `terraform destroy` in `envs/dev/` when idle,
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
