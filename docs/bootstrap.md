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
  sts.googleapis.com
```

`iamcredentials` and `sts` are the ones people forget; federation fails at token
exchange without them, which reads as a permissions problem rather than a missing
API.

**3. Apply just the identity targets:**

```bash
cd terraform/envs/dev
terraform init
terraform apply -target=module.iam -target=module.workload_identity
```

`-target` is normally a smell. It is correct here: the rest of the stack should
be created by the pipeline, and applying it now would defeat the point.

**4. Configure GitHub.** Take the outputs and set them as repository *variables*
(Settings → Secrets and variables → Actions → Variables):

| Variable | Value |
|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `workload_identity.provider_name` output |
| `GCP_SERVICE_ACCOUNT` | `iam.ci_service_account_email` output |

Variables, not secrets: neither value is a credential. The provider name only
names a trust relationship, and it is useless without an OIDC token from the one
repository the binding permits.

**5. Hand state to the pipeline.** State lives in a GCS bucket (see
`envs/dev/versions.tf`) so the local bootstrap and every later CI run share it.
A local-only state file would leave the pipeline unable to see what exists.

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
