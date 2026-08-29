# ArgoCD — the seed install, and the last thing Terraform puts inside the cluster.
#
# The handoff this module exists to make:
#
#   Terraform  →  cloud resources, and ArgoCD itself
#   ArgoCD     →  everything else inside the cluster
#
# Nothing below this point (Longhorn, CloudNativePG, cert-manager, the app) is
# managed by Terraform. They are ArgoCD Applications reconciled from Git, so the
# cluster's contents are a function of the repository rather than of whoever last
# ran an apply.
#
# This is the documented answer to ArgoCD's own chicken-and-egg: a GitOps
# controller cannot install itself, so one tool installs it and then hands over.
# Keeping that seed minimal is the whole point — the more Terraform puts in the
# cluster, the more state lives in two places at once.

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  # Pinned, not floating. A GitOps controller reconciles continuously and on its
  # own schedule, so an unpinned chart means a future reconcile can install
  # something nobody reviewed — without a commit, a PR, or anyone watching.
  # Upgrades happen as a version bump in this file, which is reviewable.
  version = var.chart_version

  values = [yamlencode({
    global = {
      # Everything lands on the stable pool. ArgoCD holds the cluster's desired
      # state; putting its controller and repo-server on preemptible nodes means
      # reconciliation stops exactly when a node is reclaimed.
      nodeSelector = {
        workload = "stateful"
      }
    }

    configs = {
      params = {
        # No TLS on the server itself — access is through `kubectl port-forward`
        # for now, and terminating TLS twice behind an ingress that does not yet
        # exist is complexity with no reader.
        "server.insecure" = true
      }
    }

    # Single replica of each component: this is one cluster with one operator.
    # HA mode triples the footprint on a node pool sized for a trial credit.
    controller     = { replicas = 1 }
    repoServer     = { replicas = 1 }
    applicationSet = { replicas = 1 }
    server         = { replicas = 1 }
  })]

  # The chart creates CRDs and controllers that take a moment to become ready;
  # the root Application below depends on this release, and a partially-ready
  # ArgoCD rejects an Application with a CRD-not-found error.
  wait          = true
  wait_for_jobs = true
  timeout       = 600
}

# The root of the app-of-apps tree: one Application whose job is to point at a
# directory of other Applications. Adding a component later becomes a file in
# Git, not a Terraform change.
#
# kubernetes_manifest rather than a second helm_release: this is a single custom
# resource, and wrapping it in a chart would add a layer with nothing in it.
resource "kubernetes_manifest" "root_app" {
  depends_on = [helm_release.argocd]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = var.namespace
    }
    spec = {
      project = "default"

      source = {
        repoURL = var.repo_url
        # Pinned to a branch here because this is the only environment. A second
        # environment would point at its own path or revision rather than
        # sharing one and diverging through parameters.
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
          # Auto-sync on, deliberately: without it a new Application committed to
          # Git sits unnoticed until someone opens the UI, which defeats the
          # point of the pattern.
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
          # Server-side apply: several of the charts below (Longhorn, CNPG) ship
          # CRDs large enough to exceed the client-side annotation limit.
          "ServerSideApply=true",
        ]
      }
    }
  }
}
