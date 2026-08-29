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

    # Single replica of each component: this is one cluster with one operator.
    # HA mode triples the footprint on a node pool sized for a trial credit.
    controller     = { replicas = 1 }
    repoServer     = { replicas = 1 }
    applicationSet = { replicas = 1 }

    server = { replicas = 1 }
  })]

  # The chart creates CRDs and controllers that take a moment to become ready;
  # the root Application below depends on this release, and a partially-ready
  # ArgoCD rejects an Application with a CRD-not-found error.
  wait          = true
  wait_for_jobs = true
  timeout       = 600

  # Install once, then never touch it again.
  #
  # Argo CD manages its own chart from Git — see argocd/apps/08-argocd.yaml in
  # the GitOps repository, which carries the real configuration: TLS, the
  # tailnet Service, placement. Terraform's job here is only to make the first
  # Argo CD exist on an empty cluster, because a GitOps controller cannot
  # install itself.
  #
  # Without ignore_changes the two fight: Argo CD reconciles its own release
  # continuously, Terraform reverts it on the next apply, and the same object
  # has two owners with different opinions.
  #
  # The reason this matters beyond tidiness: while Argo CD's Service was defined
  # here, turning it into a LoadBalancer made `terraform apply` block for ten
  # minutes waiting for an address that a mis-tagged tailnet never issued, and
  # the infrastructure pipeline failed. As an Application the same mistake is a
  # Progressing app that retries — it does not take the pipeline with it.
  lifecycle {
    ignore_changes = all
  }
}

# The root of the app-of-apps tree: one Application whose only job is to point at
# a directory of other Applications. Adding a component later becomes a file in
# Git, not a Terraform change.
#
# Delivered through the argocd-apps chart rather than a kubernetes_manifest
# resource. kubernetes_manifest validates against the live API *at plan time*, so
# it fails with "API did not recognize GroupVersionKind (CRD may not be
# installed)" on any run where ArgoCD's CRDs do not exist yet — which is every
# first apply, and every plan CI runs against an empty environment. depends_on
# does not help: plan-time validation happens before anything is applied.
#
# Helm only templates at plan time, so this orders correctly against the release
# above and still works from nothing.
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
          # Pinned to a branch because this is the only environment. A second one
          # would track its own path or revision rather than sharing this and
          # diverging through parameters.
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
            # Auto-sync on, deliberately: without prune, deleting a file leaves
            # the resource running forever; without selfHeal, a manual kubectl
            # edit silently becomes the real state and Git becomes fiction.
            prune    = true
            selfHeal = true
          }
          syncOptions = [
            "CreateNamespace=true",
            # Several charts below (Longhorn, CNPG) ship CRDs large enough to
            # exceed the client-side annotation limit.
            "ServerSideApply=true",
          ]
        }
      }
    }
  })]
}
