# The seed: what must exist before ArgoCD can read the GitOps repo — ESO, the
# ClusterSecretStore and the deploy-key ExternalSecret. Everything else comes
# from Git. No secret material here; the key stays in Secret Manager.

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = var.eso_namespace
  create_namespace = true

  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  # Pinned: an unpinned controller chart can change without a commit.
  version = var.eso_chart_version

  values = [yamlencode({
    installCRDs = true

    serviceAccount = {
      create = true
      # Must match the Workload Identity binding in envs/dev.
      name = var.eso_service_account

      # Required for Workload Identity: without it the pod uses the node's account
      # and gets PermissionDenied on Secret Manager.
      annotations = {
        "iam.gke.io/gcp-service-account" = var.gcp_service_account_email
      }
    }

    # Stable pool. This key reaches the controller only; webhook and
    # certController are pinned in their own blocks.
    nodeSelector = {
      workload = "stateful"
    }

    # The webhook gates every ExternalSecret write (failurePolicy: Fail), so two
    # replicas on different nodes. Spread, not hard anti-affinity, so a rolling
    # update fits on two nodes.
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

    # Single replica: it only rotates the webhook certificate.
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

# A local chart, not kubernetes_manifest: kubernetes_manifest validates CRDs at
# plan time, which fails before ESO is installed.
resource "helm_release" "seed" {
  depends_on = [helm_release.external_secrets]

  name      = "cluster-seed"
  namespace = var.argocd_namespace
  chart     = "${path.module}/chart"

  # The seed installs into argocd's namespace before module.argocd creates it.
  create_namespace = true

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
