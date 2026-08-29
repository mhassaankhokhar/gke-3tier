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
        # TLS on. argocd-server reads tls.crt and tls.key from a Secret named
        # argocd-server-tls in its own namespace and picks up renewals without a
        # restart, so cert-manager owns the certificate and nothing terminates
        # TLS twice. There is no ingress controller and no gateway in the path:
        # the Service below is exposed directly on the tailnet.
        "server.insecure" = false
      }
    }

    # Single replica of each component: this is one cluster with one operator.
    # HA mode triples the footprint on a node pool sized for a trial credit.
    controller     = { replicas = 1 }
    repoServer     = { replicas = 1 }
    applicationSet = { replicas = 1 }

    server = {
      replicas = 1

      # Reachable over the tailnet and nowhere else.
      #
      # loadBalancerClass hands the Service to the Tailscale operator instead of
      # GCP's load balancer controller, so the address it gets is a tailnet
      # address in CGNAT space — unroutable from the internet, reachable by
      # anyone on the tailnet. No public ingress, no Funnel, no firewall rule to
      # get wrong later.
      service = {
        type              = "LoadBalancer"
        loadBalancerClass = "tailscale"

        annotations = {
          # Pins the proxy pod to the stable pool. Without it the operator
          # applies no node selector at all, and a preempted proxy is a dropped
          # admin session at the moment you most need one.
          "tailscale.com/proxy-class" = var.proxy_class

          # The machine name inside the tailnet. Distinct from the DNS name
          # below: this one is what MagicDNS and the device list show.
          "tailscale.com/hostname" = var.tailnet_hostname

          # external-dns already watches Services, so this is the whole of the
          # DNS setup. The record points at a CGNAT address; Cloudflare accepts
          # those and forces them DNS-only, since there is nothing to proxy to.
          #
          # The address being public knowledge is the accepted trade: it is not
          # routable from outside the tailnet, so what leaks is a name, not a
          # way in. Keeping even that private would mean running an internal
          # resolver and Tailscale split DNS, which is a component to operate
          # for no change in who can reach the UI.
          "external-dns.alpha.kubernetes.io/hostname" = var.server_hostname
        }
      }
    }
  })]

  # The chart creates CRDs and controllers that take a moment to become ready;
  # the root Application below depends on this release, and a partially-ready
  # ArgoCD rejects an Application with a CRD-not-found error.
  wait          = true
  wait_for_jobs = true
  timeout       = 600
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
