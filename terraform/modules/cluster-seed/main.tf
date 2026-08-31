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

      # The half of Workload Identity that is easy to miss. The GCP-side binding
      # (KSA → GSA) is not enough on its own: without this annotation GKE never
      # maps the pod to the Google account, so it authenticates as the *node's*
      # service account instead — which has no access to Secret Manager. The
      # symptom is PermissionDenied on secretmanager.versions.access even though
      # every binding looks correct, because the identity being denied is not the
      # one the bindings were written for.
      annotations = {
        "iam.gke.io/gcp-service-account" = var.gcp_service_account_email
      }
    }

    # Stable pool: every other component waits on the secrets this produces.
    #
    # This key reaches the controller only. The chart gives the webhook and the
    # cert-controller their own blocks, and both were running unpinned — on the
    # stable pool by luck rather than by instruction, one preemption from spot.
    nodeSelector = {
      workload = "stateful"
    }

    # The webhook validates every ExternalSecret and SecretStore with
    # failurePolicy: Fail, so while it is unreachable none of them can be
    # written. On one replica that is a single node's decision — and it was
    # sharing a node with istiod and the CloudNativePG operator, which have the
    # same property.
    #
    # topologySpreadConstraints rather than required podAntiAffinity: with two
    # stable nodes a hard anti-affinity leaves a rolling update with nowhere to
    # put the new pod. matchLabelKeys scopes the constraint to one revision so
    # the outgoing ReplicaSet does not block the incoming one. Same arrangement
    # as cert-manager, istiod and CloudNativePG in the GitOps repo.
    webhook = {
      replicaCount = 2
      nodeSelector = {
        workload = "stateful"
      }
      topologySpreadConstraints = [{
        maxSkew           = 1
        topologyKey       = "kubernetes.io/hostname"
        whenUnsatisfiable = "DoNotSchedule"
        matchLabelKeys    = ["pod-template-hash"]
        labelSelector = {
          matchLabels = {
            "app.kubernetes.io/name"     = "external-secrets-webhook"
            "app.kubernetes.io/instance" = "external-secrets"
          }
        }
      }]
    }

    # Not replicated: it issues the webhook's certificate rather than gating
    # writes, so its absence delays a rotation instead of rejecting anything.
    # Pinned for the same reason as the rest.
    certController = {
      nodeSelector = {
        workload = "stateful"
      }
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
