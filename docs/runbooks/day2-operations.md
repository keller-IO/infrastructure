# Runbook — Day-2 Operations (Talos/Tofu)

Operative Anleitungen für den laufenden Cluster: Node-Lifecycle, Talos-/Kubernetes-
Upgrades, Schematic-Änderungen, Secrets-Rotation, Teil- und Voll-Destroy.

Alle Kommandos aus dem Repo-Root. Env-Verzeichnis:
`tofu/talos-cluster/envs/kellerIO/` (im Folgenden `$ENV`). `just env <recipe>`
ruft env-lokale Recipes (`secrets-edit`, `destroy`, `destroy-cluster`).

Voraussetzungen jeder Operation:
```bash
nix develop                                    # Dev-Shell (tofu, talosctl, kubectl, sops, age)
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
export TALOSCONFIG=$PWD/tofu/talos-cluster/envs/kellerIO/talosconfig
export KUBECONFIG=$PWD/tofu/talos-cluster/envs/kellerIO/kubeconfig
```

Vor **jedem** Apply: `just plan` reviewen. Tofu ist Source of Truth — keine
manuellen Änderungen an VMs/Talos-Config, die nicht im Code stehen.

---

## 1. Standard-Apply / Drift-Korrektur

Code-Änderung (z.B. an `cluster.auto.tfvars`) ausrollen:
```bash
just init        # nur nach Modul-/Provider-Updates nötig
just validate
just plan        # reviewen!
just apply
```
Health danach:
```bash
kubectl get nodes -o wide
talosctl -n 192.168.2.80 health      # VIP
tofu -chdir=tofu/talos-cluster/envs/kellerIO output    # control_plane_nodes / worker_nodes
```

---

## 2. Worker-Node hinzufügen

**Datei:** `tofu/talos-cluster/envs/kellerIO/cluster.auto.tfvars` (`nodes = [...]`)

1. Neuen Eintrag anhängen — nächste freie IP (aktuell belegt: `.80` VIP, `.81`–`.86`),
   freier `target_pve`-Host:
   ```hcl
   {
     name       = "kellerio-wrk4"
     target_pve = "cloud59"
     ip_address = "192.168.2.87"
     role       = "worker"
   },
   ```
2. Ausrollen + warten bis Ready:
   ```bash
   just plan && just apply
   kubectl get node kellerio-wrk4 -w
   ```
3. README-Tabelle in `$ENV/README.md` nachziehen.

> Control-Plane erweitern: gleiche Logik mit `role = "controlplane"`,
> `allow_scheduling = false` und CP-Ressourcen (2 vCPU / 2 GiB / 20 GB). Immer
> **ungerade** CP-Anzahl (3, 5) für etcd-Quorum.

---

## 3. Node entfernen

Reihenfolge wichtig — erst aus K8s/etcd raus, dann VM zerstören.

1. Cordon + Drain:
   ```bash
   kubectl cordon kellerio-wrk4
   kubectl drain kellerio-wrk4 --ignore-daemonsets --delete-emptydir-data
   ```
2. Talos zurücksetzen (verlässt etcd bei CP-Nodes sauber):
   ```bash
   talosctl -n 192.168.2.87 reset --graceful --reboot
   ```
3. Eintrag aus `nodes` in `cluster.auto.tfvars` löschen, dann:
   ```bash
   just plan && just apply        # entfernt die VM
   kubectl delete node kellerio-wrk4    # falls noch gelistet
   ```
4. README-Tabelle nachziehen.

---

## 4. Talos-Upgrade

**Datei:** `cluster.auto.tfvars` (`talos_version`, hat `# renovate:`-Marker).

1. `talos_version` auf Ziel setzen (z.B. `v1.13.4` → `v1.14.x`), damit Code = Ist:
   ```bash
   just plan && just apply
   ```
2. Nodes nacheinander auf das neue Installer-Image heben (Schematic-ID aus tfvars):
   ```bash
   talosctl -n 192.168.2.81 upgrade \
     --image factory.talos.dev/installer/<talos_schematic_id>:v1.14.x
   ```
   Pro Node einzeln, Health abwarten:
   ```bash
   talosctl -n 192.168.2.81 health
   kubectl get nodes
   ```
   Reihenfolge: Control-Planes (.81→.82→.83) zuerst, dann Worker (.84→.85→.86).
3. Kubernetes-Version separat anheben (Talos steuert das in-cluster):
   ```bash
   talosctl -n 192.168.2.80 upgrade-k8s --to 1.3x.y
   ```

> Immer **ein Node nach dem anderen**. CP-Quorum (mind. 2 von 3) muss erhalten bleiben.

---

## 5. Talos-Schematic ändern (Extensions)

Z.B. `iscsi_tools` entfernen — wird **nicht** gebraucht (Ceph RBD nutzt krbd,
CephFS den Kernel-Client).

1. Neues Schematic auf <https://factory.talos.dev> bauen (gewünschte Extensions
   wählen) → neue Schematic-ID.
2. `talos_schematic_id` in `cluster.auto.tfvars` setzen (Kommentar bei der Variable
   mit den enthaltenen Extensions aktuell halten).
3. `just plan && just apply`.
4. Nodes auf das neue Image upgraden (wie §4.2):
   ```bash
   talosctl -n <ip> upgrade --image factory.talos.dev/installer/<neue-id>:<talos_version>
   ```

---

## 6. Secrets rotieren / bearbeiten

**Dateien:** `$ENV/secrets.enc.yaml`, `$ENV/.sops.yaml`

```bash
just env secrets-edit            # öffnet secrets.enc.yaml in $EDITOR (SOPS)
# oder neu aus Vorlage:
#   cp $ENV/secrets.enc.yaml.example $ENV/secrets.yaml  (Werte eintragen)
#   just env secrets-encrypt   &&   rm $ENV/secrets.yaml
just plan && just apply          # proxmox-/git-Token, age-Key werden zur Plan-Zeit gelesen
```

Enthaltene Keys: `proxmox_api_token`, `git_token`, `sops_age_private_key`
(letzterer wird per KSOPS in den Argo-CD repo-server gemountet — muss zum
GitOps-`.sops.yaml`-Public-Key passen).

---

## 7. Destroy

**Nur Talos-VMs** neu aufsetzen (Cluster-Secrets bleiben im State):
```bash
just env destroy-cluster         # -target module.nodes...talos_node
just apply                       # VMs frisch provisionieren
```

**Kompletter Abriss** (entfernt erst Argo CD aus dem Cluster, dann alles):
```bash
just env destroy
```

> ⚠️ Voll-Destroy zerstört den gesamten Cluster inkl. ggf. lokaler Daten.
> PVCs liegen im externen Ceph — die überleben, aber prüfe Backups vorher.

---

## 8. Troubleshooting-Quickrefs

```bash
talosctl -n <ip> dmesg                    # Boot-/Kernel-Logs
talosctl -n <ip> services                 # Talos-Service-Status
talosctl -n <ip> get members              # etcd/Cluster-Membership
talosctl -n <ip> logs kubelet
tofu -chdir=tofu/talos-cluster/envs/kellerIO state list    # verwaltete Ressourcen
```
