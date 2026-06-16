# Argo CD install + bootstrap (app-of-apps). Kept at the environment level so the
# talos-cluster module stays GitOps-agnostic. Argo CD then reconciles everything
# else (incl. the Ceph CSI / storage classes) from the keller.io GitOps repo.
#
# SOPS-encrypted manifests in the repo are decrypted in-cluster via the KSOPS
# kustomize plugin: the repo-server gets the KSOPS+kustomize binaries (init
# container) and the age key (mounted from the secret below).

resource "kubernetes_namespace_v1" "argocd" {
  depends_on = [module.cluster]

  metadata {
    name = "argocd"
  }
}

# Credentials for the (private) Forgejo GitOps repo, consumed by Argo CD.
# The argocd.argoproj.io/secret-type=repository label lets Argo CD pick it up.
resource "kubernetes_secret_v1" "argocd_repo" {
  metadata {
    name      = "keller-io-repo"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = var.argocd_repo_url
    username = var.git_username
    password = local.git_token
  }

  type = "Opaque"
}

# Age key for KSOPS, mounted into the repo-server (see helm values below).
resource "kubernetes_secret_v1" "argocd_sops_age" {
  metadata {
    name      = "argocd-sops-age"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  }

  data = {
    "keys.txt" = local.sops_age_private_key
  }

  type = "Opaque"
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  values = [yamlencode({
    # Let Argo CD's kustomize run the KSOPS exec plugin.
    configs = {
      cm = {
        "kustomize.buildOptions" = "--enable-alpha-plugins --enable-exec"
      }
    }

    repoServer = {
      env = [
        {
          name  = "SOPS_AGE_KEY_FILE"
          value = "/home/argocd/.config/sops/age/keys.txt"
        }
      ]
      # Install KSOPS + a matching kustomize into a shared volume.
      initContainers = [
        {
          name    = "install-ksops"
          image   = var.ksops_image
          command = ["/bin/sh", "-c"]
          args    = ["echo 'Installing KSOPS...'; mv ksops /custom-tools/; mv $GOPATH/bin/kustomize /custom-tools/; echo 'Done.'"]
          volumeMounts = [
            { mountPath = "/custom-tools", name = "custom-tools" }
          ]
        }
      ]
      volumes = [
        { name = "custom-tools", emptyDir = {} },
        {
          name = "sops-age"
          secret = {
            secretName = kubernetes_secret_v1.argocd_sops_age.metadata[0].name
          }
        }
      ]
      volumeMounts = [
        { mountPath = "/usr/local/bin/kustomize", name = "custom-tools", subPath = "kustomize" },
        { mountPath = "/usr/local/bin/ksops", name = "custom-tools", subPath = "ksops" },
        { mountPath = "/home/argocd/.config/sops/age/keys.txt", name = "sops-age", subPath = "keys.txt" },
      ]
    }

    # Root app-of-apps. Delivered via the chart's extraObjects so the Application CR
    # is applied by Helm *after* the Argo CD CRDs in the same release — this avoids
    # any Terraform plan-time dependency on CRDs that don't exist yet.
    extraObjects = [
      {
        apiVersion = "argoproj.io/v1alpha1"
        kind       = "Application"
        metadata = {
          name      = "bootstrap"
          namespace = kubernetes_namespace_v1.argocd.metadata[0].name
        }
        spec = {
          project = "default"
          source = {
            repoURL        = var.argocd_repo_url
            targetRevision = "main"
            path           = var.argocd_bootstrap_path
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "argocd"
          }
          syncPolicy = {
            automated   = { prune = true, selfHeal = true }
            syncOptions = ["CreateNamespace=true"]
          }
        }
      }
    ]
  })]

  depends_on = [
    kubernetes_secret_v1.argocd_repo,
    kubernetes_secret_v1.argocd_sops_age,
  ]
}
