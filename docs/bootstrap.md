# Bootstrap — the one manual step

Everything in this project deploys through the pipeline, with one unavoidable
exception: the pipeline's own credentials.

## The chicken-and-egg

GitHub Actions authenticates to GCP through Workload Identity Federation. That
federation is Terraform-managed — so the resource that lets CI run Terraform is
itself created by Terraform. Something has to break the loop, and it can only be
a human at a workstation.

So: **apply the bootstrap once locally, then never again.** After that, the
pipeline owns every apply.

## What the bootstrap covers

Only the identity plumbing:

- `modules/iam` — the CI service account
- `modules/workload-identity` — the pool, the provider, and the binding that
  lets one GitHub repository impersonate that account

The cluster, network, registry and workloads are deliberately **not** part of
this step. They are what the pipeline is for.

## Steps

**1. Local credentials.** Terraform reads Application Default Credentials, which
are separate from what `gcloud` itself uses — `gcloud config set project` does
not configure them:

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project <PROJECT_ID>
```

**2. Enable the APIs** the modules need, before any apply:

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com
```

Three of these fail in ways that do not look like a missing API:

- `iamcredentials` and `sts` — federation fails at token exchange, which reads as
  a permissions problem.
- `cloudresourcemanager` — Terraform cannot read the project IAM policy, so every
  `google_project_iam_member` in state errors with 403 IAM_PERMISSION_DENIED even
  though the permissions are correct.

**3. Apply the bootstrap configuration:**

```bash
cd terraform/bootstrap
terraform init -backend-config=backend.hcl
terraform apply
```

No `-target`. `bootstrap/` contains only the identity, in its own state — that
separation is what makes a later `terraform destroy` in an environment unable to reach
it. An earlier version of this repo kept everything in one state and used
`-target` to apply "just the bootstrap"; a plain destroy then took the service
accounts and the Workload Identity pool with the cluster, and the pool stayed
soft-deleted for 30 days with its id reserved.

**4. CI permissions — no longer a manual step.** The bootstrap apply grants them:
the five project roles the pipeline needs, `storage.objectAdmin` on the state
bucket, and `serviceAccountAdmin` on the backup account only.

Withheld on purpose: `iam.serviceAccountAdmin` and
`resourcemanager.projectIamAdmin` at the project level. The pipeline can build
the whole stack but cannot create service accounts or grant itself project roles,
so a compromised workflow cannot widen its own access. The backup-account grant
is scoped to that one resource for the same reason.

**5. Configure GitHub.** Take the outputs and set them as repository *variables*
(Settings → Secrets and variables → Actions → Variables):

| Variable | Value |
|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `workload_identity.provider_name` output |
| `GCP_SERVICE_ACCOUNT` | `iam.ci_service_account_email` output |

Variables, not secrets: neither value is a credential. The provider name only
names a trust relationship, and it is useless without an OIDC token from the one
repository the binding permits.

**6. State layout.** Both configurations use the same bucket, different prefixes:

| Config | Prefix | Applied by |
|---|---|---|
| `terraform/bootstrap` | `gke-3tier/bootstrap` | a human, once |
| `terraform/envs/dev` | `gke-3tier/envs/dev` | CI, every merge |

Each environment reads the identity from bootstrap's state through
`terraform_remote_state` — it consumes those accounts and never manages them.

## Destroying

```bash
cd terraform/envs/dev && terraform destroy
```

Removes the cluster, network and registry. It cannot touch the service accounts,
the OIDC provider or the state bucket: those are not in this state, and the CI
account and pool additionally carry `prevent_destroy`. Rebuilding is one pipeline
run — no second bootstrap.

## Why no service account key

The old approach is `gcloud iam service-accounts keys create`, then paste the
JSON into a GitHub secret. That key is long-lived, silently copyable, and valid
until someone remembers to rotate it. Federation issues a token per workflow run
instead, scoped to one repository.

`.gitignore` blocks `*-key.json` and `sa-*.json` for that reason: if a key ever
gets created by accident, it should not be one `git add -A` away from being
published.

## Two layers of restriction

- The **provider** trusts only tokens whose `repository_owner` matches
  (`attribute_condition`). Without this, GCP would trust every GitHub Actions
  token in existence — which is why it now refuses to create such a provider.
- The **binding** narrows further to a single `owner/repo`, so another repository
  in the same account cannot deploy this project.
