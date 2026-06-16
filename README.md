<div align="center">

# 🏗️ keller.io — Infrastructure

**Der Cluster-Unterbau als Code — von der VM bis zu Argo CD.**

Provisionierung und Lifecycle-Management des **Talos-Linux**-Clusters für den
keller.io-Homelab, deklarativ über [**OpenTofu**](https://opentofu.org/).

<br>

[![CI](https://github.com/keller-IO/infrastructure/actions/workflows/ci.yml/badge.svg)](https://github.com/keller-IO/infrastructure/actions/workflows/ci.yml)
[![SOPS](https://img.shields.io/badge/secrets-SOPS_%2B_age-2F855A?logo=gnuprivacyguard&logoColor=white)](https://github.com/getsops/sops)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)
![Last commit](https://img.shields.io/github/last-commit/keller-IO/infrastructure?logo=git&logoColor=white)

[![OpenTofu](https://img.shields.io/badge/OpenTofu-FFDA18?logo=opentofu&logoColor=black)](https://opentofu.org/)
[![Talos Linux](https://img.shields.io/badge/Talos_Linux-FF7300?logo=talos&logoColor=white)](https://www.talos.dev/)
[![Proxmox](https://img.shields.io/badge/Proxmox_VE-E57000?logo=proxmox&logoColor=white)](https://www.proxmox.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Argo CD](https://img.shields.io/badge/Argo_CD-EF7B4D?logo=argo&logoColor=white)](https://argo-cd.readthedocs.io/)

</div>

---

Dieses Repo erzeugt die Proxmox-VMs, installiert Talos, bootstrapped Kubernetes und
installiert **Argo CD**. Ab dort übernimmt GitOps
([`kubernetes-gitops`](https://github.com/keller-IO/kubernetes-gitops)) den Rest des
Clusters.

> **Hinweis — Blaupausen-Phase:** Sensible Werte sind Platzhalter
> (`REPLACE_ME`, `CHANGE ME`, `TODO`) und bleiben bis zum Produktivbetrieb so. Was
> noch fehlt, steht in der Production-Readiness-Doku des GitOps-Repos.

---

## Inhaltsverzeichnis

- [Wie es funktioniert](#wie-es-funktioniert)
- [Repository-Aufbau](#repository-aufbau)
- [Entwicklungsumgebung (Nix Shell)](#entwicklungsumgebung-nix-shell)
- [Deployment](#deployment)
- [Secrets verwalten (SOPS + age)](#secrets-verwalten-sops--age)
- [Weiterführende Dokumentation](#weiterführende-dokumentation)
- [Lizenz](#lizenz)

---

## Wie es funktioniert

```
tofu apply ──▶ Proxmox-VMs ──▶ Talos + Kubernetes ──▶ Argo CD ──▶ GitOps übernimmt
```

Der gesamte Cluster-Zustand wird aus Code erzeugt. Zwei externe Module
(`talos-proxmox-nodes`, `talos-cluster`) erstellen die VMs und konfigurieren Talos;
`argocd.tf` installiert Argo CD und richtet die app-of-apps-Bootstrap-Application
ein, die auf das GitOps-Repo zeigt.

---

## Repository-Aufbau

| Pfad | Inhalt |
|------|--------|
| `tofu/talos-cluster/envs/kellerIO/` | Aktive Deployment-Umgebung (Cluster-Definition, Argo-CD-Bootstrap, env-lokale Recipes) |
| `justfile` | Task-Runner — wrappt die gängigen `tofu`-Kommandos der Umgebung |
| `flake.nix` / `.envrc` | Reproduzierbare Entwicklungsumgebung (siehe unten) |
| `AGENTS.md` | Architektur-Prinzipien & Arbeitsregeln |

Details zur Topologie (Nodes, IPs, Proxmox-Verteilung), zu den verwendeten Modulen
und zum Argo-CD-Bootstrap stehen in der
[Umgebungs-README](tofu/talos-cluster/envs/kellerIO/README.md).

---

## Entwicklungsumgebung (Nix Shell)

Alle benötigten Werkzeuge sind in `flake.nix` gepinnt — keine manuelle Installation
nötig.

```bash
nix develop          # Dev-Shell mit allen Tools betreten
```

Mit [direnv](https://direnv.net/) lädt sich die Shell beim Betreten des Verzeichnisses
automatisch (eine `.envrc` mit `use flake` liegt bereits im Repo):

```bash
direnv allow         # einmalig erlauben
```

Enthaltene Werkzeuge: `opentofu`, `talosctl`, `kubectl`, `sops`, `age`, `just`.

---

## Deployment

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

just init       # tofu init — lädt die gepinnten Module + Provider
just validate   # tofu validate
just plan       # Änderungen prüfen
just apply      # VMs provisionieren, Talos + Argo CD bootstrappen
```

`just` ohne Argument listet alle verfügbaren Recipes auf. Env-lokale Recipes
(z. B. `secrets-edit`, `destroy`) erreichst du über `just env <recipe>`.

Nach erfolgreichem Apply liegen `talosconfig` und `kubeconfig` in der
Umgebungs-Directory (beide gitignored):

```bash
export TALOSCONFIG=$PWD/tofu/talos-cluster/envs/kellerIO/talosconfig
export KUBECONFIG=$PWD/tofu/talos-cluster/envs/kellerIO/kubeconfig
kubectl get nodes
talosctl health
```

---

## Secrets verwalten (SOPS + age)

Secrets werden **nie im Klartext** committet. Sie werden mit SOPS/age verschlüsselt
(`secrets.enc.yaml`) und zur Plan-Zeit vom `carlpett/sops`-Provider gelesen.

```bash
age-keygen -o ~/.config/sops/age/keys.txt    # 1. age-Schlüssel erzeugen (privat!)
age-keygen -y ~/.config/sops/age/keys.txt    #    Public Key in .sops.yaml eintragen
just env secrets-encrypt                      # 2. secrets.yaml -> secrets.enc.yaml
just env secrets-edit                         #    später bearbeiten
```

Vollständige Anleitung (benötigte Keys, Argo-CD-/KSOPS-Verdrahtung) in der
[Umgebungs-README](tofu/talos-cluster/envs/kellerIO/README.md#secrets--sops).

---

## Weiterführende Dokumentation

- [`AGENTS.md`](AGENTS.md) — Architektur-Prinzipien & Arbeitsregeln
- [`tofu/talos-cluster/envs/kellerIO/README.md`](tofu/talos-cluster/envs/kellerIO/README.md) — Umgebungs-Details, Topologie, Bootstrap
- [`kubernetes-gitops`](https://github.com/keller-IO/kubernetes-gitops) — Workloads & GitOps

---

## Lizenz

Veröffentlicht unter der [BSD-3-Clause-Lizenz](LICENSE).
