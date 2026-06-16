# infrastructure — AGENTS.md

## Purpose
Provisioning and lifecycle management of the **Talos Linux** cluster using **OpenTofu**.

## Ownership
Owns `tofu/talos-cluster/envs/kellerIO/` (main deployment environment).

## Local Contracts
- **Infrastructure as Code**: OpenTofu.
- **Providers**: Talos, Proxmox (implied by homelab/talos), SOPS, Kubernetes, Helm (for ArgoCD bootstrap).
- **Secrets**: `secrets.enc.yaml` (SOPS-encrypted), generated from `secrets.enc.yaml.example`.
- **Workflow**: `justfile` in `envs/kellerIO/` for common tofu operations.
- **Output**: Kubeconfig and Talosconfig for cluster access.

## Work Guidance
- Follow Root AGENTS.md for global rules (Caveman, Commit).
- Deployment flow: `tofu init` → `tofu plan` → `tofu apply`.
- Post-apply: Cluster is ready for GitOps takeover via ArgoCD (see `argocd.tf`).
- Use placeholders for sensitive data in examples.

## Verification
- `tofu plan` must be clean before apply.
- `talosctl health` to verify cluster state.

## Index
None.
