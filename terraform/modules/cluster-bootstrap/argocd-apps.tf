# Argo CD root objects, created once by Terraform (official argocd-apps chart),
# so a rebuild is one apply and drift shows up in `plan`.
#
#   AppProject "platform": third-party charts (monitoring, KEDA, ...) into their namespaces
#   AppProject "apps":     our charts (frontend, backend, loadgen); namespaced resources only
#   ApplicationSet "platform": one Application per  platform/<name>/config.yaml
#   ApplicationSet "apps":     one Application per  apps/<name>/config.yaml
#
# Each ApplicationSet is a matrix of (clusters labelled "env") x (folders in Git),
# so a new environment = a new labelled cluster + envs/<env>/values.yaml files.
#
# config.yaml in each folder:
#   namespace: monitoring           # where it runs
#   autoSync: true                  # false = sync by hand (loadgen)
#   serverSideApply: true           # optional (big CRDs)
#   podSecurity: restricted         # optional, namespace PSS level (default baseline)
#   chart:                          # optional: an upstream chart; omit = the folder IS the chart
#     repoURL: https://...
#     name: kube-prometheus-stack
#     version: x.y.z
# Values: <folder>/values.yaml + <folder>/envs/<env>/values.yaml (both optional).

locals {
  # Go template (Argo CD goTemplate), filled in per generated Application.
  appset_template_patch = <<-EOT
    spec:
      sources:
      {{- if .chart }}
        - repoURL: {{ .chart.repoURL | quote }}
          chart: {{ .chart.name | quote }}
          targetRevision: {{ .chart.version | quote }}
          helm:
            releaseName: {{ .path.basename | quote }}
            ignoreMissingValueFiles: true
            valueFiles:
              - $values/{{ .path.path }}/values.yaml
              - $values/{{ .path.path }}/envs/{{ index .metadata.labels "env" }}/values.yaml
        - repoURL: ${var.gitops_repo_url}
          targetRevision: ${var.gitops_revision}
          ref: values
      {{- else }}
        - repoURL: ${var.gitops_repo_url}
          targetRevision: ${var.gitops_revision}
          path: {{ .path.path | quote }}
          helm:
            releaseName: {{ .path.basename | quote }}
            ignoreMissingValueFiles: true
            valueFiles:
              - values.yaml
              - envs/{{ index .metadata.labels "env" }}/values.yaml
      {{- end }}
      syncPolicy:
        {{- if .autoSync }}
        automated:
          prune: true
          selfHeal: true
        {{- end }}
        syncOptions:
          - CreateNamespace=true
          - SkipDryRunOnMissingResource=true
          {{- if .serverSideApply }}
          - ServerSideApply=true
          {{- end }}
        managedNamespaceMetadata:
          labels:
            pod-security.kubernetes.io/enforce: {{ default "baseline" .podSecurity | quote }}
        retry:
          limit: 10
          backoff:
            duration: 15s
            factor: 2
            maxDuration: 5m
  EOT

  appsets = {
    platform = { glob = "platform/*/config.yaml", description = "third-party platform charts" }
    apps     = { glob = "apps/*/config.yaml", description = "lab application charts" }
  }

  # Any registered cluster ("*"); access is limited by namespace, and only
  # admins can register clusters.
  project_destinations = {
    platform = [for ns in var.platform_namespaces : { server = "*", namespace = ns }]
    apps     = [for ns in var.app_namespaces : { server = "*", namespace = ns }]
  }
}

resource "helm_release" "argocd_apps" {
  name        = "argocd-apps"
  namespace   = kubernetes_namespace_v1.platform["argocd"].metadata[0].name
  repository  = "https://argoproj.github.io/argo-helm"
  chart       = "argocd-apps"
  version     = var.chart_versions.argocd_apps
  wait        = true
  max_history = 5

  values = [yamlencode({
    projects = {
      platform = {
        namespace    = "argocd"
        description  = "Third-party platform charts (monitoring, KEDA, dashboards)"
        sourceRepos  = concat([var.gitops_repo_url], var.platform_chart_repos)
        destinations = local.project_destinations.platform
        # Platform charts install CRDs, ClusterRoles and webhooks.
        clusterResourceWhitelist = [{ group = "*", kind = "*" }]
      }
      apps = {
        namespace    = "argocd"
        description  = "Lab application charts (frontend, backend, loadgen)"
        sourceRepos  = [var.gitops_repo_url]
        destinations = local.project_destinations.apps
        # Apps may create their namespace and nothing else cluster-wide.
        clusterResourceWhitelist = [{ group = "", kind = "Namespace" }]
      }
    }

    applicationsets = {
      for set, cfg in local.appsets : set => {
        namespace  = "argocd"
        goTemplate = true
        generators = [{
          matrix = {
            generators = [
              { clusters = { selector = { matchExpressions = [{ key = "env", operator = "Exists" }] } } },
              { git = { repoURL = var.gitops_repo_url, revision = var.gitops_revision, files = [{ path = cfg.glob }] } },
            ]
          }
        }]
        template = {
          metadata = {
            name = "{{ index .metadata.labels \"env\" }}-{{ .path.basename }}"
            labels = {
              "app.kubernetes.io/part-of" = var.name
              "lab-commit/set"            = set
            }
          }
          spec = {
            project     = set # each set is pinned to its own AppProject
            destination = { server = "{{ .server }}", namespace = "{{ .namespace }}" }
            sources     = [] # filled by templatePatch (upstream chart vs. local chart)
          }
        }
        templatePatch = local.appset_template_patch
      }
    }
  })]

  depends_on = [helm_release.argo_cd] # needs the Argo CD CRDs
}
