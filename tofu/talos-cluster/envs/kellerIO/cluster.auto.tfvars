# Non-sensitive cluster configuration for the "kellerIO" cluster (safe to commit).
# Secrets: secrets.auto.tfvars (local) or secrets.enc.yaml (SOPS, see secrets.enc.yaml.example).

# Proxmox cluster API endpoint (any node of the kellerIO Proxmox cluster).
# 13.09.2026: FQDN statt Kurzname. `cloud61` allein ist nur mit passender
# Search-Domain aufloesbar; von einem Arbeitsplatz aus scheitert jeder Lauf mit
# "lookup cloud61 ... no such host", und der Provider meldet dann irrefuehrend,
# Ressourcen seien geloescht (z. B. das Talos-ISO auf cephfs, das sehr wohl
# dort liegt). `cloud61.jit.land` steht als host-record im dnsmasq auf
# 192.168.2.10 und loest ueberall im LAN auf.
proxmox_endpoint = "https://cloud61.jit.land:8006"

cluster_name        = "kellerio"
cluster_endpoint_ip = "192.168.2.80" # control-plane VIP (unused IP just below the node range)

# Worker defaults (workers inherit these; control planes override below).
# No Longhorn disk: kellerIO uses an external Ceph cluster via ceph-csi.
default_cpu_cores        = 4
default_cpu_sockets      = 1
default_memory_mb        = 8192
default_disk_gb          = 40
default_longhorn_disk_gb = 0

# TODO: set storage IDs that exist on the kellerIO Proxmox cluster.
# iso_storage_id must be SHARED storage reachable from every Proxmox host
# (the ISO is downloaded once and booted by VMs across all target hosts).
vm_storage_id  = "local-zfs"
iso_storage_id = "cephfs"

# Roles:
#   role = "controlplane" + allow_scheduling = false -> manager only (dedicated)
#   role = "worker"                                   -> dedicated worker (uses defaults)
# Control planes are manager-only (allow_scheduling = false). Storage for workloads
# comes from the external Ceph cluster, so no node carries a local data disk.
# IPs start at 192.168.2.81; VMs are spread across cloud58/59/65/67/61/62.
# 07.08.2026: Control planes von 4096 auf 6144 MB. Bei 4 GB (=3,3 GiB allocatable)
# lagen cp1/cp2/cp3 real bei 78-93 % Speicher — cp1 bei 3052Mi = 93 %. Allein
# kube-apiserver braucht dort 1,4-1,8 GiB, der Rest geht fuer etcd, kubelet und
# die Cilium-/CSI-DaemonSets drauf. Damit war die Control Plane der engste Punkt
# im Cluster, und ein CP-Ausfall wiegt schwerer als ein Worker.
nodes = [
  # --- Control plane (manager-only, smaller footprint) ---
  {
    name             = "kellerio-cp1"
    target_pve       = "cloud62"
    ip_address       = "192.168.2.81"
    role             = "controlplane"
    allow_scheduling = false
    cpu_cores        = 2
    memory_mb        = 6144
    disk_gb          = 20
  },
  {
    name             = "kellerio-cp2"
    target_pve       = "cloud61"
    ip_address       = "192.168.2.82"
    role             = "controlplane"
    allow_scheduling = false
    cpu_cores        = 2
    memory_mb        = 6144
    disk_gb          = 20
  },
  {
    name = "kellerio-cp3"
    # cloud65 ist mit 15,6 GB der kleinste Host dieser drei: mit 6 GB fuer cp3
    # sind dort 12,9 von 15,6 GB vergeben (83 %) — im Blick behalten.
    target_pve       = "cloud65"
    ip_address       = "192.168.2.83"
    role             = "controlplane"
    allow_scheduling = false
    cpu_cores        = 2
    memory_mb        = 6144
    disk_gb          = 20
  },

  # --- Workers (use the default_* resources) ---
  {
    name = "kellerio-wrk1"
    # 13.09.2026: die VM (2046) liegt real auf `lat7440` — Ingo hat sie dorthin
    # verschoben. Davor stand hier "pve" (24.08.) und davor "cloud67". Der Wert
    # MUSS der Realitaet folgen: `node_name` erzwingt Ersetzung, und wrk1 traegt
    # 5 der 6 CNPG-Primaries — ein falscher Eintrag laesst jeden plan die VM
    # zerstoeren und neu bauen. Vor jedem Lauf gegen
    # `pvesh get /cluster/resources` pruefen.
    #
    # 18.10.2026: 8 -> 12 GB (wie wrk2). lat7440 traegt kein Ceph, hat 32 GB
    # (verloetet, Maximum) und behaelt danach ~4,5 GB Reserve.
    target_pve = "lat7440"
    ip_address = "192.168.2.84"
    memory_mb  = 12288
    role       = "worker"
  },
  {
    name = "kellerio-wrk2"
    # 18.10.2026: 8 -> 12 GB. Worker-Requests 25.817 MiB lagen bei 63 %, N-1
    # (Ausfall wrk5) bei 87 %; mit wrk1+wrk2 auf 12 GB 52 % bzw. 68 %.
    # Nur Hosts ohne nennenswerte Ceph-Last: cloud58 hat kein OSD/Mon/MDS.
    # wrk3 bleibt 8 GB (cloud64 swappt, Mon+aktiver Mgr+RGW), wrk4 ebenso
    # (cloud62 traegt osd.0). Alle Hosts ausser cloud59/65 stehen bereits auf
    # dem Board-Maximum von 32 GB — mehr RAM geht nur durch Umverteilen.
    # Live per `qm set` + Drain + `qm reboot` gesetzt; dieser Eintrag gleicht
    # nur an (Modul setzt kein reboot_after_update, apply ohne -target verboten).
    target_pve = "cloud58"
    ip_address = "192.168.2.85"
    memory_mb  = 12288
    role       = "worker"
  },
  {
    name = "kellerio-wrk3"
    # 18.10.2026: 8 -> 12 GB, nachdem db11 (VM 2023, 4 GB) per HA-Prioritaet
    # nach cloud67 umgezogen ist. Vorher swappte cloud64 bereits 2,5 GB.
    target_pve = "cloud64"
    ip_address = "192.168.2.86"
    memory_mb  = 12288
    role       = "worker"
  },
  {
    name = "kellerio-wrk4"
    # 24.08.2026: war "cloud59", die VM (2014) liegt real auf `cloud62` — gleiche
    # Lage wie bei wrk1, gleiche Begruendung.
    #
    # 18.10.2026 17:19: wrk4s Systemplatte live von Ceph `vmimages` nach cloud62
    # `local-zfs` verschoben (qmmove, ohne Downtime), nachdem aios01 (2017) und
    # office02 (2028) dort Platz gemacht hatten; `rpool` danach 72 %, 60,7 G frei.
    # Damit gilt wieder der globale `vm_storage_id`, kein `storage_id` noetig.
    # Das Cloud-Init-Laufwerk liegt weiter auf `vmimages`. NICHT per Tofu
    # verschieben: bei einem Wechsel von `initialization.datastore_id` schaltet
    # bpg/proxmox die VM aus (vmPowerOffForPendingChanges). Deshalb pinnt
    # `cloudinit_storage_id` den Ist-Stand. Verschieben nur in einem geplanten
    # Wartungsfenster mit gedrainter wrk4, danach die Zeile entfernen.
    #
    # 19.10.2026: 8 -> 12 GB, damit alle Worker mindestens 12 GB haben. Platz
    # auf cloud62 kam von talk01-dev (2024) und talk01 (2037), die live nach
    # pve-media umgezogen sind. wrk4 selbst nach pve-media passte nicht
    # (10,5 GB frei, kein Swap, 4 Kerne, 2 OSDs). Im selben Wartungsfenster
    # (wrk4 gedrained) das Cloud-Init-Laufwerk live nach `local-zfs` umgehaengt,
    # das alte RBD `vmimages:vm-2014-cloudinit` entfernt — der Pin
    # `cloudinit_storage_id` ist damit entfallen.
    target_pve = "cloud62"
    ip_address = "192.168.2.87"
    memory_mb  = 12288
    role       = "worker"
  },
  {
    name = "kellerio-wrk5"
    # 13.09.2026 neu. Grund: N-1 ging mit vier Workern nicht auf — 20.503 MiB
    # Requests gegen 3x7.435 MiB Allocatable sind 92 %, bei einem Ausfall
    # blieben Pods Pending. Eine fuenfte Node loest das auf 69 %, ohne eine
    # einzige bestehende Node anzufassen. Die Alternative (alle vier auf 12 GB)
    # haette vier Reboots gekostet, und die sechs CNPG-Cluster mit
    # `instances: 1` erlauben per PDB null Unterbrechungen.
    #
    # cloud67: am 13.09. auf 32 GB aufgeruestet, traegt sonst keine VM,
    # 8 Xeon-Kerne im Leerlauf, 183 GB freies local-zfs, Mon+Mgr-Standby.
    # ACHTUNG: cloud67 haengt an 1 GBit/s, nicht an 10 wie cloud58/61/62 und
    # lat7440. Das ist bewusst in Kauf genommen — cloud64 (wrk3) haengt
    # ebenfalls an 1 GBit/s und laeuft unauffaellig. PVCs kommen ueber Ceph
    # RBD uebers Netz, I/O-schwere Workloads gehoeren also eher nicht hierher.
    #
    # 12 GB statt der 8 GB Default: kostet auf dem leeren cloud67 keinen
    # zusaetzlichen Eingriff und macht wrk5 gross genug, um beim spaeteren
    # Ausbau eine komplette andere Node aufzunehmen. Damit wird 4x12 GB
    # nachtraeglich per Drain moeglich, statt wie bisher an den CNPG-PDBs
    # haengenzubleiben.
    target_pve = "cloud67"
    ip_address = "192.168.2.88"
    memory_mb  = 12288
    role       = "worker"
    # 13.09.2026, fuer die naechste neue Node wichtig: `main.tf` setzt modulweit
    # `attach_install_iso = false`. Fuer die bestehenden Nodes ist das richtig
    # (Talos liegt auf scsi0, und der Autostart soll nicht am CephFS-ISO-Storage
    # haengen), fuer eine NEUE Node aber toedlich - sie bekommt eine leere
    # Platte, `boot: order=scsi0;net0` und nichts zum Booten. Das sieht wie eine
    # Boot-Schleife aus; zusaetzlich haengt danach jeder `plan`, weil der
    # Provider den qemu-guest-agent abfragt, den eine nicht bootende VM nie
    # bedient. Abhilfe: `attach_install_iso = true` NUR fuer die neue Node
    # setzen, installieren lassen, danach wieder entfernen.
    # wrk5 ist installiert, das ISO ist abgehaengt - deshalb steht hier nichts.
  },
]

# Talos image (guest_agent nfs_tools) — same schematic as homelab-kube.
talos_schematic_id = "3abf06e1d81e509d779dc256f9feae6cd6d82c69337c661cbfc383a92594faf5"
# renovate: datasource=github-releases depName=siderolabs/talos versioning=semver
talos_version  = "v1.13.4"
image_platform = "nocloud"
image_arch     = "amd64"

network_gateway      = "192.168.2.94"
network_subnet       = 24
kubelet_valid_subnet = "192.168.2.0/24"

# GitOps: Argo CD reconciles the keller.io repo (root app-of-apps under bootstrap/).
argocd_repo_url       = "https://github.com/keller-IO/kubernetes-gitops.git"
argocd_bootstrap_path = "clusters/main"
git_username          = "ltsavar"

# Cilium übernimmt CNI + kube-proxy-Ersatz (kubeProxyReplacement). Talos-Defaults
# kube-proxy + flannel deaktivieren, damit sie nicht parallel zu Cilium laufen
# (14.07.: liefen als Altlast mit, flannel-conflist war eh von Cilium deaktiviert).
extra_config_patches = [
  {
    cluster = {
      network = {
        cni = {
          name = "none"
        }
      }
      proxy = {
        disabled = true
      }
    }
    # DNS explizit setzen statt per DHCP beziehen. Ohne das nimmt Talos den
    # Resolver, den der jeweilige Proxmox-Host liefert — auf cloud58/61/62/64/65/67
    # ist das der Gateway 192.168.2.94, auf cloud59 kam dagegen 100.88.112.65
    # (CGNAT, ueber das NetBird-Mesh). kellerio-wrk4 haette als einziger Node seine
    # Namensaufloesung ueber das Mesh bezogen: faellt NetBird aus, verliert der
    # Node DNS. Funktional war beides gleichwertig (intern wie extern identisch
    # aufgeloest) — es geht um die Abhaengigkeit, nicht um einen akuten Defekt.
    #
    # Gilt fuer ALLE Nodes: das Modul haengt extra_config_patches an jede
    # Machine-Config an (talos-cluster/machine.tf:94 und :160), einen Per-Node-Hook
    # gibt es nicht.
    #
    # Bewusst im SELBEN Listenelement wie der cluster-Patch: extra_config_patches
    # ist als list(any) deklariert, und OpenTofu verlangt dann fuer alle Elemente
    # denselben Typ. Ein zweites Element mit nur einem machine-Key scheitert an
    # "all list elements must have the same type".
    #
    # 10.08.2026: 9.9.9.9 als ZWEITER Resolver ergaenzt. Mit nur 192.168.2.10 war
    # dnsmasq auf dem PVE-Host `pve` ein Single Point of Failure fuer die externe
    # Namensaufloesung des GESAMTEN Clusters. Real eingetreten am 10.08.2026: pve
    # war ~40 min stromlos (DECT-Dose), und danach kam dnsmasq zwar als "active"
    # hoch, beantwortete aber keine einzige Anfrage — CoreDNS lieferte SERVFAIL
    # fuer alle externen Namen, Roundcube fand mail.jit-creatives.de nicht mehr
    # ("getaddrinfo failed"), Kunden konnten nicht mailen. Siehe pve-dect-failsafe.
    #
    # Reihenfolge ist Absicht: .10 zuerst, damit die internen Spezialrouten von
    # dnsmasq (server=/jit.services/…, /box/…, /spamhaus.org/…) weiter greifen.
    # 9.9.9.9 ist reiner Fallback fuer den Fall, dass .10 nicht antwortet, und
    # kennt die internen Namen NICHT — er ersetzt dnsmasq also nicht, er
    # verhindert nur den Totalausfall. Quad9 statt 8.8.8.8/1.1.1.1 gewaehlt, weil
    # 1.1.1.1 und 8.8.8.8 hier bereits als Spezial-Upstreams fuer /jit.services
    # bzw. in cert-manager belegt sind — ein dritter Anbieter haelt die
    # Fehlerbilder auseinander.
    machine = {
      network = {
        nameservers = ["192.168.2.10", "9.9.9.9"]
      }
    }
  }
]

# 18.10.2026 (kubernetes-gitops#287): Talos-API-Zugang fuer den
# system-upgrade-controller. Talos erzeugt fuer eine talos.dev-ServiceAccount-CR
# im erlaubten Namespace selbst ein Secret mit talosconfig (Key `config`):
# Client-Zertifikat der OS-CA, 6 h gueltig, 1 h vor Ablauf automatisch erneuert.
# Damit liegt kein langlebiges Admin-Zertifikat in Git, im Tofu-State oder im
# Cluster. Die CR selbst liegt im GitOps-Repo (system-upgrade-controller).
#
# `os:admin` ist noetig: In Talos 1.13 verlangt MachineService/Upgrade genau
# diese Rolle (internal/app/machined/pkg/system/services/machined.go),
# `os:operator` reicht nicht. Begrenzt wird ueber den Namespace: nur CRs in
# `system-upgrade-controller` bekommen ein Zertifikat, und nur dessen Jobs
# mounten es.
#
# Nur Control Planes: Talos lehnt das Feature auf Workern ab ("can only be
# enabled on control plane machines").
extra_controlplane_config_patches = [
  {
    machine = {
      features = {
        kubernetesTalosAPIAccess = {
          enabled                     = true
          allowedRoles                = ["os:admin"]
          allowedKubernetesNamespaces = ["system-upgrade-controller"]
        }
      }
    }
  }
]

# Talos-Auto-Updates (kubernetes-gitops, system-upgrade-controller, Plan `talos`)
# laufen nur auf Nodes mit `keller.io/talos-upgrade=enabled`. Die Freigabe ist
# bewusst pro Node und deklarativ (kubernetes-gitops#287). Talos setzt
# nodeLabels ohne Reboot, aber der SUC startet den Upgrade-Job sofort, sobald
# das Label da ist: Ein Apply mit neuem Label IST der Upgrade-Start fuer diesen
# Node. Entfernen des Labels stoppt weitere Laeufe, nicht einen laufenden.
#
# 19.10.2026: Canary cp3 lief durch, danach alle Nodes freigegeben. SUC arbeitet
# sie nacheinander ab (concurrency 1); vor jedem Drain prueft der Preflight den
# ganzen Cluster. Talos-Versionen kommen per Renovate-PR im GitOps-Repo, der
# manuelle Merge dort startet den Rollout. Einen Node herausnehmen: Eintrag hier
# entfernen und gezielt applien.
node_config_patches = {
  "kellerio-cp1" = [
    { machine = { nodeLabels = { "keller.io/talos-upgrade" = "enabled" } } }
  ]
  "kellerio-cp2" = [
    { machine = { nodeLabels = { "keller.io/talos-upgrade" = "enabled" } } }
  ]
  "kellerio-cp3" = [
    { machine = { nodeLabels = { "keller.io/talos-upgrade" = "enabled" } } }
  ]
  "kellerio-wrk1" = [
    { machine = { nodeLabels = { "keller.io/talos-upgrade" = "enabled" } } }
  ]
  "kellerio-wrk2" = [
    { machine = { nodeLabels = { "keller.io/talos-upgrade" = "enabled" } } }
  ]
  "kellerio-wrk3" = [
    { machine = { nodeLabels = { "keller.io/talos-upgrade" = "enabled" } } }
  ]
  "kellerio-wrk4" = [
    { machine = { nodeLabels = { "keller.io/talos-upgrade" = "enabled" } } }
  ]
  "kellerio-wrk5" = [
    { machine = { nodeLabels = { "keller.io/talos-upgrade" = "enabled" } } }
  ]
}
