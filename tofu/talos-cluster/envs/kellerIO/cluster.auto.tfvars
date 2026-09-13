# Non-sensitive cluster configuration for the "kellerIO" cluster (safe to commit).
# Secrets: secrets.auto.tfvars (local) or secrets.enc.yaml (SOPS, see secrets.enc.yaml.example).

# Proxmox cluster API endpoint (any node of the kellerIO Proxmox cluster).
# TODO: set the real endpoint of one of the cloud6x hosts.
proxmox_endpoint = "https://cloud61:8006"

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
    target_pve = "lat7440"
    ip_address = "192.168.2.84"
    role       = "worker"
  },
  {
    name       = "kellerio-wrk2"
    target_pve = "cloud58"
    ip_address = "192.168.2.85"
    role       = "worker"
  },
  {
    name       = "kellerio-wrk3"
    target_pve = "cloud64"
    ip_address = "192.168.2.86"
    role       = "worker"
  },
  {
    name = "kellerio-wrk4"
    # 24.08.2026: war "cloud59", die VM (2014) liegt real auf `cloud62` — gleiche
    # Lage wie bei wrk1, gleiche Begruendung. Achtung: wrk4s Disk liegt zudem auf
    # Ceph (`vmimages`), waehrend `vm_storage_id` global `local-zfs` ist. Das
    # Node-Schema kennt kein Storage-Feld pro Node, diese Abweichung ist hier
    # also NICHT abbildbar — sie erzwingt aber auch keine Ersetzung.
    target_pve = "cloud62"
    ip_address = "192.168.2.87"
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
