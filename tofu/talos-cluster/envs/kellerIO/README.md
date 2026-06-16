# kellerIO — Talos cluster environment

OpenTofu environment that provisions and bootstraps the **kellerIO** Kubernetes
cluster: 3 dedicated control planes + 3 workers running [Talos
Linux](https://www.talos.dev/) on a Proxmox cluster. Persistent storage comes from
an **external Ceph cluster** (via ceph-csi, deployed through GitOps — no local
Longhorn disks). [Argo CD](https://argo-cd.readthedocs.io/) is installed and points
at the [`keller.io`](https://git.f4mily.net/kreativmonkey/keller.io) GitOps repo to
reconcile everything else.

## Used modules

Both modules are consumed from the external repository
[`kreativmonkey/terraform-module`](https://github.com/kreativmonkey/terraform-module),
pinned to a tag:

| Module | Source | Purpose |
|---|---|---|
| `nodes` | `git::https://github.com/kreativmonkey/terraform-module.git//talos-proxmox-nodes?ref=v0.1.0` | Creates the Proxmox VMs and downloads the Talos ISO. |
| `cluster` | `git::https://github.com/kreativmonkey/terraform-module.git//talos-cluster?ref=v0.1.0` | Configures Talos on those VMs and bootstraps Kubernetes. |

Argo CD install + bootstrap (`argocd.tf`) lives in this environment, not in the
modules, so the modules stay GitOps-agnostic.

## Topology

Talos **v1.13.4** (latest stable). Node IPs start at `192.168.2.81`; the
control-plane VIP / Kubernetes API endpoint is `192.168.2.80`.

| Node | Role | Proxmox host | IP | vCPU | RAM | OS disk |
|---|---|---|---|---|---|---|
| kellerio-cp1 | controlplane (manager-only) | cloud64 | 192.168.2.81 | 2 | 8 GiB | 40 GB |
| kellerio-cp2 | controlplane (manager-only) | cloud65 | 192.168.2.82 | 2 | 8 GiB | 40 GB |
| kellerio-cp3 | controlplane (manager-only) | cloud62 | 192.168.2.83 | 2 | 8 GiB | 40 GB |
| kellerio-wrk1 | worker (defaults) | cloud61 | 192.168.2.84 | 4 | 16 GiB | 40 GB |
| kellerio-wrk2 | worker (defaults) | cloud64 | 192.168.2.85 | 4 | 16 GiB | 40 GB |
| kellerio-wrk3 | worker (defaults) | cloud65 | 192.168.2.86 | 4 | 16 GiB | 40 GB |

Workers inherit the `default_*` variables; control planes override them with a
smaller footprint and `allow_scheduling = false` (no workloads). No node carries a
local data disk — storage is provided by the **external Ceph cluster**. The VMs are
spread across all four Proxmox hosts (cloud61/62/64/65); the three control planes
sit on three distinct hosts for HA.

> **Before you apply**, double-check the `TODO`s in `cluster.auto.tfvars`:
> `proxmox_endpoint`, `vm_storage_id` and `iso_storage_id`. `iso_storage_id` must
> be **shared** storage reachable from every cloud6x host, because the Talos ISO
> is downloaded once and booted by VMs on all four hosts.

## Prerequisites

- [OpenTofu](https://opentofu.org/) `>= 1.6`
- [`just`](https://github.com/casey/just) (optional, wraps the common commands)
- [`sops`](https://github.com/getsops/sops) + [`age`](https://github.com/FiloSottile/age)
- A Proxmox API token on the kellerIO cluster
- A Forgejo token with read access to the `keller.io` GitOps repo (for Argo CD)

## Secrets & SOPS

Secrets are **never committed in plaintext**. They are encrypted with SOPS/age and
read at plan-time by the `carlpett/sops` provider. Three keys are required:

| Key | Used for |
|---|---|
| `proxmox_api_token` | Proxmox provider auth (`user@pam!tokenid=<uuid>`). |
| `git_token` | Argo CD repository credential — lets it clone the (private) `keller.io` repo. |
| `sops_age_private_key` | Mounted into the Argo CD repo-server so KSOPS can decrypt SOPS-encrypted manifests in the GitOps repo. |

### 1. Create your age key (once per machine/operator)

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt      # writes the PRIVATE key
age-keygen -y ~/.config/sops/age/keys.txt      # prints the PUBLIC key
```

**Where the keys go:**

- **Private key** → `~/.config/sops/age/keys.txt` on your machine. Never commit it.
  Expose it to tooling via `export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt`.
- **Public key** → paste it into `.sops.yaml` in this directory, replacing
  `REPLACE_WITH_YOUR_AGE_PUBLIC_KEY`. This decides who can decrypt
  `secrets.enc.yaml`.

### 2. Create the encrypted secrets file

```bash
cp secrets.enc.yaml.example secrets.yaml   # fill in the three real values
just secrets-encrypt                       # -> writes secrets.enc.yaml (committable)
rm secrets.yaml                            # drop the plaintext copy
```

`secrets.enc.yaml` is safe to commit (only the values are encrypted, per the
`encrypted_regex` in `.sops.yaml`). Edit it later with `just secrets-edit`.

> Alternatively, for local-only use you can skip SOPS and put the same three keys
> in `secrets.auto.tfvars` (gitignored) — see `secrets.auto.tfvars.example`.

## GitOps with Argo CD

`argocd.tf` installs Argo CD (Helm chart `argo-cd`, pinned via
`argocd_chart_version`) and bootstraps a single **app-of-apps** Application named
`bootstrap`, pointing at:

- repo: `argocd_repo_url` (default `https://git.f4mily.net/kreativmonkey/keller.io.git`)
- revision: `main`
- path: `argocd_bootstrap_path` (default `bootstrap`)

From there Argo CD reconciles the rest of the cluster (incl. ceph-csi / storage
classes) out of the GitOps repo. The Forgejo credential is created as a
`argocd.argoproj.io/secret-type=repository` secret from `git_username` + `git_token`.

> Adjust `argocd_repo_url` / `argocd_bootstrap_path` in `cluster.auto.tfvars` to
> match the actual layout of the `keller.io` repo.

### In-cluster secrets: SOPS via KSOPS

`argocd.tf` wires up the [KSOPS](https://github.com/viaduct-ai/kustomize-sops)
kustomize plugin so SOPS-encrypted manifests committed to the GitOps repo are
decrypted **inside** the repo-server:

- the `sops_age_private_key` is stored in the `argocd-sops-age` secret and mounted
  at `/home/argocd/.config/sops/age/keys.txt` (`SOPS_AGE_KEY_FILE`);
- an init container (`ksops_image`, default `viaductoss/ksops:v4.5.1`) drops the
  `ksops` + `kustomize` binaries into the repo-server;
- `kustomize.buildOptions: --enable-alpha-plugins --enable-exec` lets Argo CD run
  the plugin.

> The **public** counterpart of `sops_age_private_key` must be a recipient in the
> `keller.io` repo's own `.sops.yaml`, otherwise the repo-server cannot decrypt. It
> may be the same age key you use to encrypt this environment's `secrets.enc.yaml`.
> In your kustomizations reference the KSOPS generator (a `ksops` `generators:`
> entry pointing at the encrypted files).

## Initialize & deploy

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

just init       # tofu init — downloads the pinned modules + providers
just validate   # tofu validate
just plan       # review
just apply      # provision VMs, bootstrap Talos + Argo CD
```

After a successful apply, `talosconfig` and `kubeconfig` are written into this
directory (both gitignored, mode 0600):

```bash
export TALOSCONFIG=$PWD/talosconfig
export KUBECONFIG=$PWD/kubeconfig
kubectl get nodes
```

## Teardown

```bash
just destroy            # removes Argo CD from the cluster, then destroys all infra
just destroy-cluster    # destroys only the Talos VMs (keeps cluster secrets in state)
```

## Notes

- **Talos version:** pinned to `v1.13.4` (latest stable as of 2026-06). It is a
  patch bump over the module default (`v1.13.2`) within the same `1.13` minor, so
  the `v1alpha1` machine-config schema is unchanged — **no module changes were
  required**. Renovate keeps the pin current via the annotation in
  `cluster.auto.tfvars`.
- **Storage:** external Ceph via ceph-csi (deployed through Argo CD). No Longhorn,
  no local data disks (`default_longhorn_disk_gb = 0`).
- **`kubelet_valid_subnet`** is set to `192.168.2.0/24` and forwarded to the
  `cluster` module so the kubelet registers a node IP from the kellerIO LAN
  (metrics-server / exec / port-forward depend on this).
- **Schematic ID** matches homelab-kube (bundles `qemu-guest-agent`,
  `iscsi-tools`, `nfs-tools`); regenerate at <https://factory.talos.dev/> if you
  need different system extensions.
