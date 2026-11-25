# ArgoCD's seed install, the last thing Terraform puts in the cluster.
# Everything else in the cluster is an ArgoCD Application reconciled from Git.

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  # Pinned; upgrades are a reviewed version bump.
  version = var.chart_version

  values = [yamlencode({
    global = {
      # Stable pool: reconciliation must survive spot preemption.
      nodeSelector = {
        workload = "stateful"
      }
    }

    # Single replicas; HA mode triples the footprint.
    controller     = { replicas = 1 }
    repoServer     = { replicas = 1 }
    applicationSet = { replicas = 1 }

    server = { replicas = 1 }

    # Restores the argoproj.io/Application health check (removed in Argo CD 1.8)
    # so app-of-apps sync waves wait for each wave to be Healthy. Needed here because
    # the first sync uses this install's argocd-cm; 08-argocd.yaml in the GitOps repo
    # carries the same key. Script from the Argo CD docs (operator-manual/health).
    configs = {
      cm = {
        "resource.customizations.health.argoproj.io_Application" = <<-EOT
          hs = {}
          hs.status = "Progressing"
          hs.message = ""
          if obj.status ~= nil then
            if obj.status.health ~= nil then
              hs.status = obj.status.health.status
              if obj.status.health.message ~= nil then
                hs.message = obj.status.health.message
              end
            end
          end
          return hs
        EOT
      }
    }
  })]

  # The root Application below needs ArgoCD's CRDs ready.
  wait          = true
  wait_for_jobs = true
  timeout       = 600

  # Install once, then hands off: argocd/apps/08-argocd.yaml in the GitOps repo
  # manages this chart. Without ignore_changes Terraform and Argo CD would fight
  # over the release.
  lifecycle {
    ignore_changes = all
  }
}

# Root of the app-of-apps: one Application pointing at a directory of
# Applications. Via the argocd-apps chart, not kubernetes_manifest, which
# validates CRDs at plan time and fails on an empty cluster.
resource "helm_release" "root_app" {
  depends_on = [helm_release.argocd]

  name      = "root-app"
  namespace = var.namespace

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.apps_chart_version

  values = [yamlencode({
    applications = {
      root = {
        namespace = var.namespace
        project   = "default"

        source = {
          repoURL = var.repo_url
          # Single environment, so it tracks a branch.
          targetRevision = var.target_revision
          path           = var.apps_path
          directory = {
            recurse = true
          }
        }

        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.namespace
        }

        syncPolicy = {
          automated = {
            # prune removes deleted files' resources; selfHeal reverts manual edits.
            prune    = true
            selfHeal = true
          }
          syncOptions = [
            "CreateNamespace=true",
            # Some charts ship CRDs over the client-side annotation limit.
            "ServerSideApply=true",
          ]
        }
      }
    }
  })]
}
