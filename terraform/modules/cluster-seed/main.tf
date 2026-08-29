# The seed: the smallest set of things that must exist before GitOps can take
# over, because each one is required to read the repository the rest lives in.
#
# The loop this breaks:
#
#   ArgoCD needs a deploy key to read the GitOps repo
#     → the key comes from an ExternalSecret
#       → which needs External Secrets Operator installed
#         → which is defined in the GitOps repo
#           → which ArgoCD cannot read yet
#
# So ESO, the ClusterSecretStore and the repo credential are installed by
# Terraform. Everything after that — cert-manager, external-dns, Longhorn,
# CloudNativePG, the application — comes from Git.
#
# Nothing here contains secret material. The ExternalSecret is a pointer; the key
# stays in Secret Manager and is fetched over Workload Identity, so it appears in
# neither Terraform state nor any repository.

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = var.eso_namespace
  create_namespace = true

  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  # Pinned for the same reason as everything else: a controller that reconciles
  # continuously must not be free to install whatever upstream published last.
  version = var.eso_chart_version

  values = [yamlencode({
    installCRDs = true

    serviceAccount = {
      create = true
      # Must match the Workload Identity binding in envs/dev — a mismatch fails
      # when a secret is first synced, not at install time, which makes it look
      # like a Secret Manager permissions problem.
      name = var.eso_service_account
    }

    # Stable pool: every other component waits on the secrets this produces.
    nodeSelector = {
      workload = "stateful"
    }
  })]

  wait          = true
  wait_for_jobs = true
  timeout       = 600
}

# A local chart rather than kubernetes_manifest resources.
#
# kubernetes_manifest validates against the live API at plan time, so it fails
# with "CRD may not be installed" whenever ESO is not yet installed — which is
# every first apply and every CI plan against an empty environment. depends_on
# does not help: that validation runs before anything is applied. Helm only
# templates at plan time.
resource "helm_release" "seed" {
  depends_on = [helm_release.external_secrets]

  name      = "cluster-seed"
  namespace = var.argocd_namespace
  chart     = "${path.module}/chart"

  values = [yamlencode({
    projectId         = var.project_id
    clusterName       = var.cluster_name
    clusterLocation   = var.cluster_location
    secretStoreName   = var.secret_store_name
    esoNamespace      = var.eso_namespace
    esoServiceAccount = var.eso_service_account
    argocdNamespace   = var.argocd_namespace
    repoUrl           = var.repo_url
    sshKeySecretName  = var.ssh_key_secret_name
  })]
}
