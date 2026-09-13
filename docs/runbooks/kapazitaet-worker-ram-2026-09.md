# Plan — media-RAM, Laptop als PVE-Node, Worker-Kapazitaet

> ## ⚠️ Kurswechsel 13.09.2026 — fuenfter Worker statt 4 × 12 GB
>
> **Der Weg „alle vier Worker auf 12 GB" ist verworfen.** Stattdessen kommt ein
> **fuenfter Worker `kellerio-wrk5` auf `cloud67` mit 12 GB**. Die Abschnitte P3,
> P4 und P5 unten beschreiben den alten Weg und sind damit **ueberholt** — P4
> (wrk1 auf den Laptop) hat Ingo ohnehin schon selbst erledigt.
>
> ### Warum
>
> | | Host-RAM | N-1 danach | Eingriff |
> |---|---:|---:|---|
> | 4 × 12 GB (alt) | +16 GB | 59 % | 4 Worker-Reboots, CNPG-Drain, 2 Umzuege |
> | **wrk5, 12 GB (neu)** | +12 GB | 69 % | **keine bestehende Node angefasst** |
>
> N-1 ist heute wirklich eng: **20.503 MiB Requests gegen 3 × 7.435 MiB
> Allocatable = 92 %**, bei einem Ausfall blieben Pods Pending. Beide Wege loesen
> das. Den Ausschlag gibt nicht die Prozentzahl, sondern der Eingriff: fuer
> 4 × 12 GB sind **cloud64 (28,0 gegen ~27,3 Budget) und cloud62 (26,0 gegen
> ~25,3) schon ueberbucht**, wrk3 muesste weg und `media-test-trixie` gestoppt
> werden — dazu vier Reboots gegen die sechs CNPG-Cluster mit `instances: 1`,
> deren PDBs null Unterbrechungen erlauben. **Das gesamte Drain-Problem aus P5
> entsteht nur durch den alten Weg.** Eine neue Node umgeht es vollstaendig.
>
> Groesste Einzel-Request im Cluster ist **1.280 MiB** — Node-Groesse ist nirgends
> der Engpass, eine fuenfte Node ist also gleichwertig zu groesseren Nodes.
>
> ### cloud67 als Standort
>
> Ingo hat `cloud67` am 13.09. auf **32 GB** aufgeruestet (dieses Dokument fuehrte
> es oben noch mit 15,6 GB — **die Tabelle in Abschnitt 0 ist insoweit veraltet**).
> Der Host traegt **keine einzige VM**, Load 0,17, 8 Xeon-Kerne im Leerlauf,
> 183 GB freies `local-zfs`, `vmbr0` aktiv, `cephfs` erreichbar, Mon + Mgr-Standby.
> Ein RAM-Upgrade der bestehenden Worker haette **null CPU** dazugebracht.
>
> **1 GBit/s statt 10.** `cloud67` haengt mit `enp1s0f0` an 1 GBit/s, waehrend
> cloud58, cloud61, cloud62 und lat7440 auf 10 GBit/s liegen. Bewusst in Kauf
> genommen: **`cloud64` haengt ebenfalls an 1 GBit/s und traegt dort seit jeher
> wrk3 unauffaellig** — wrk5 ist also keine neue Klasse von Problem. PVCs kommen
> ueber Ceph RBD uebers Netz; I/O-schwere Workloads gehoeren eher nicht auf wrk5.
>
> **12 GB statt 8:** kostet auf dem leeren cloud67 keinen zusaetzlichen Eingriff
> und macht wrk5 gross genug, um spaeter eine komplette andere Node per Drain
> aufzunehmen. Damit wird 4 × 12 GB **nachtraeglich** moeglich, ohne an den
> CNPG-PDBs haengenzubleiben.
>
> ### ⚠️ Zwei Funde, die vor jedem Tofu-Lauf zaehlen
>
> **1. wrk1-Drift war eine scharfe Mine.** State, tfvars und Realitaet sagten
> **drei verschiedene Dinge**: State `cloud67`, tfvars `pve`, real `lat7440`
> (Ingo hat die VM am 13.09. verschoben). `node_name` erzwingt Ersetzung — ein
> `apply` haette **wrk1 zerstoert und neu gebaut**, und dort liegen **5 der 6
> CNPG-Primaries**. Korrigiert auf `lat7440`. **Merksatz: vor jedem Lauf
> `pvesh get /cluster/resources` gegen die tfvars halten.**
>
> **2. Ein pauschaler `tofu apply` bleibt verboten.** Der volle Plan meldet
> `4 to add, 9 to change, 1 to destroy` — darunter:
> - `wrk4`: `datastore_id "vmimages" -> "local-zfs"`, also ein Griff an die Platte
>   einer laufenden Node (die Ceph-Lage von wrk4 ist im Node-Schema nicht
>   abbildbar)
> - alle 7 Nodes: `talos_machine_configuration_apply` neu angewandt, `apply_mode`
>   „auto" — genau deshalb wurde der DNS-Fallback im August per `talosctl patch`
>   gemacht und nicht per Tofu
> - `helm_release.argocd_bootstrap` **wuerde angelegt** und `argocd` in-place
>   geaendert, in einen laufenden, GitOps-verwalteten ArgoCD hinein (PR #5 offen)
>
> **Deshalb nur gezielt anwenden** (Ergebnis verifiziert: `2 to add, 0 to change,
> 0 to destroy`):
>
> ```sh
> cd infrastructure/tofu/talos-cluster/envs/kellerIO
> export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
> tofu plan -var="proxmox_endpoint=https://192.168.2.8:8006" \
>   -target='module.nodes.proxmox_virtual_environment_vm.talos_node["kellerio-wrk5"]' \
>   -target='module.cluster.talos_machine_configuration_apply.worker["kellerio-wrk5"]'
> ```
>
> Zwei Stolpersteine dabei: der Endpunkt steht als **Hostname** `cloud61` in den
> tfvars und ist vom Laptop aus nicht aufloesbar — `-var` ueberschreiben, denn
> **`TF_VAR_` wird von `.auto.tfvars` ueberstimmt**. Und ein Lauf mit kaputtem
> Endpunkt meldete faelschlich, das Talos-ISO auf `cephfs` sei geloescht; es liegt
> dort mit 325 MB. **Fehlgeschlagene API-Aufrufe als „Ressource weg" zu lesen ist
> ein Artefakt, kein Befund.**
>
> ### ⚠️ Offen: die Node-IPs liegen ungeschuetzt im DHCP-Pool
>
> **Im Netz `192.168.2.0/24` vergibt nicht die UDM, sondern dnsmasq auf
> `192.168.2.10` (= Host `pve`).** Dessen Bereich ist
> `dhcp-range=192.168.2.60,192.168.2.170` und **umschliesst damit .80 (VIP),
> .81–.87 (alle Talos-Nodes) und .88 (wrk5)**. Es gibt **keine einzige
> `dhcp-host`-Reservierung fuer die Nodes** (29 Reservierungen existieren, keine
> davon fuer .81–.88). Aktuell 10 Leases, keine im Bereich .80–.95 — es hat also
> nur nie gekracht, weil 10 Clients auf 110 Adressen treffen.
>
> `.88` ist heute frei (kein Lease, keine Reservierung, kein DNS, kein ARP, keine
> VM-Config). **Empfehlung, unabhaengig von wrk5:** den Pool um den Node-Block
> herumfuehren, also statt einem Bereich
> `dhcp-range=192.168.2.60,192.168.2.79` **plus**
> `dhcp-range=192.168.2.95,192.168.2.170`. Keiner der 10 aktuellen Leases liegt
> im ausgesparten Block, der Umbau trifft also niemanden. Alternativ feste
> `dhcp-host`-Eintraege je Node-MAC.


Stand der Ist-Aufnahme: **11.09.2026** (live erhoben, nicht aus der Doku).
Status: **geplant, nichts davon ausgeführt.** Offene Fragen am Ende blockieren
einzelne Phasen.

Env und Werkzeuge wie in `day2-operations.md`. Kurz:
`KUBECONFIG=tofu/talos-cluster/envs/kellerIO/kubeconfig`, PVE-API von `cloud61`
(192.168.2.8), media = `192.168.2.23`.

---

## 0. Ausgangslage

### Kubernetes

| Node | VM-RAM | Nutzung | Requests | Limits |
|---|---:|---:|---:|---:|
| cp1–cp3 | 6 GB | 49–58 % | 25–26 % | 25–42 % |
| wrk1 | 8 GB | 61 % | 72 % | 206 % |
| wrk2 | 8 GB | 74 % | 73 % | 170 % |
| wrk3 | 8 GB | 69 % | 67 % | 176 % |
| wrk4 | 8 GB | 60 % | 59 % | 147 % |

- Summe der Worker-Requests: **20.279 MiB**. Allocatable je 8-GB-Worker: 7.435 MiB
  (≈ 757 MiB Overhead).
- **N-1 geht heute nicht auf:** fällt ein Worker aus, stehen 19,8 GiB Requests
  gegen 21,8 GiB Allocatable, also 91 %. Pods bleiben dann Pending.
  Mit 12 GB je Worker sind es 59 %.
- Keine Pending-Pods. Die drei letzten OOMKills (mailman-web, roundcube,
  wordpress-1) waren Container-Limits, kein Node-Druck.
- **wrk1 trägt 5 der 6 CNPG-Primaries** (crowdsec, expense, forgejo, paperless,
  roundcube; mailman-pg liegt auf wrk3). Alle haben `instances: 1`, die PDBs
  erlauben **0 Unterbrechungen** und blockieren deshalb `kubectl drain`.
- Control Planes bleiben bei 6 GB, sie haben genug Luft.

### PVE-Hosts

VM-Budget = Host-RAM − 2 GB (PVE/ARC) − 4 GB je OSD (`osd_memory_target`
Default, osd.1: 3 GB) − ~1 GB je Mon/Mgr/MDS.

| Host | RAM | Ceph-Rollen | Budget | vergeben | Swap | Soll nach Plan |
|---|---:|---|---:|---:|---|---:|
| pve | 31,2 | osd.2, osd.6 | ~21 | **28,5** | **8/8 voll**, Load 8 auf 4 Kernen | 20,5 |
| cloud58 | 31,3 | – | ~29 | 17,0 | 6,9/8 | 27,0 |
| cloud61 | 31,3 | osd.5, osd.10, MDS | ~20 | 20,0 | **8/8 voll** | 20,0 |
| cloud62 | 31,3 | osd.0 | ~25 | 26,0 | 7,1/8 | 22,0 |
| cloud64 | 31,3 | Mon, Mgr aktiv | ~27 | **28,0** | **8/8 voll**, Load 12 | 26,0 |
| cloud65 | 15,6 | osd.1, Mon, Mgr, MDS | ~7 | **11,9** | 5,8/8, 2,4 GB frei | 11,9 ⚠️ |
| cloud67 | 15,6 | Mon, Mgr | ~11,5 | 10,4 | 5,5/8 | 10,4 |
| cloud59 | 15,6 | osd.8, osd.9 | ~5,5 | 0 | 2,7/16 | 0 |
| pve2 | 15,6 | – | nur x86-64-v1-Gäste | 0 | – | 0 |
| **Laptop** | ? | – | RAM − 2 | – | – | 12 (wrk1) |

- pve2 (AMD K10) kann keine Talos-Nodes fahren (`x86-64-v2-AES`).
- cloud59 ist ohne eine einzige VM bei Load 15–17 und nimmt deshalb keine Last.
- Ceph: 497/497 PGs `active+clean`, **kein Backfill**. Slow Ops auf osd.0/2/6,
  osd.3 und osd.4 laufen noch mit 19.2.3, osd.4 ist `out`, osd.3 hat
  `primary_affinity 0`. Alle Pools size 3 / min_size 2.

### media (Bare Metal, heute noch kein PVE-Node)

Geplant ist der Umbau zum PVE-Node `pve-media` (192.168.2.35) mit
Debian-13-Storage-Gast, siehe `~/ansible/jit/README_media_proxmox_conversion_plan_2026-08-24.md`.
Dessen RAM geht an den Storage-Gast (12–16 GB) plus 8 GB Hypervisor-Reserve,
für k8s-Worker bleibt dort nichts.

- ASUS H87-PRO, **max. 32 GB**, 4 Slots belegt: 2× 8 GB `M378B1G73QH0-CK0`
  (ChannelA/B-DIMM0) + 2× 4 GB `M378B5173QH0-CK0` (ChannelA/B-DIMM1).
  DDR3-1600 UDIMM, ohne ECC.
- 24 GB RAM, davon **9,6 GB im Swap**. Größter Verbraucher ist Elasticsearch
  7.17.4 mit 7,5 GB RSS **plus 5,5 GB Swap**.
- ⚠️ **ES-Heap ist nicht gepinnt.** `-Xms/-Xmx11952m` sind exakt 50 % von
  23.905 MB (Auto-Heap). **Nach dem Upgrade nimmt sich ES 16 GB und schluckt den
  Gewinn komplett.** ES lauscht nur auf localhost und hatte bei der Prüfung
  keinen einzigen verbundenen Client.
- Daneben laufen: osd.3 und osd.4 (osd.3 ~2 GB RSS), Plex, Sonarr/Radarr, MariaDB,
  InfluxDB, nfs-ganesha (`/data/media`) und die borg-Repos von mail05 und db11.
  `corosync-qnetd` läuft ohne Clients.

**Wie das mit k8s zusammenhängt:** media-RAM bringt dem Cluster keine
VM-Kapazität. Er entlastet die OSDs, an denen alle `ceph-rbd`-PVCs hängen.
Die RAM-Erhöhung der Worker hängt nur am Laptop und an Phase 3.

---

## Reihenfolge und Abhängigkeiten

```
P0 Vorbereitung ─┬─ P1 media-RAM            (unabhängig, eigenes Fenster)
                 ├─ P2 Laptop → PVE ── P4 wrk1 → Laptop ──┐
                 ├─ P3 Platz schaffen ────────────────────┼─ P5 Worker 12 GB
                 └─ wrk2 geht SOFORT (cloud58 hat Platz) ─┘   (wrk2→wrk4→wrk3→wrk1)
                                                           └─ P6 Git/tfvars
```

**Warum 12 GB und nicht 16 GB:** +32 GB passen nirgends hin. cloud62 käme auf
26 GB bei ~25 GB Budget, cloud58 mit mx02 auf 31 GB bei ~29 GB. 16 GB erst nach
weiterer Hardware oder dem Rückbau von pve2.

---

## P0 — Vorbereitung (kein Ausfall)

1. **Elasticsearch auf media abschalten** (Frage 3). Laut media-Umbauplan
   enthält es nur `.geoip_databases`, hat keinen Verbraucher und wird nicht
   migriert. Das wirkt schon **vor** dem Modultausch und gibt ~7,5 GB RAM plus
   5,5 GB Swap frei:
   ```bash
   ssh root@192.168.2.23 'systemctl disable --now elasticsearch; free -m'
   ```
   Falls ES doch gebraucht wird: Heap per
   `/etc/elasticsearch/jvm.options.d/heap.options` auf `-Xms4g`/`-Xmx4g` pinnen.
2. **telegraf auf den Hosts mit vollem Swap neu starten** (pve, cloud61, cloud64),
   bewährter Handgriff. Direkt danach steigt die Load ~4 min stark an, das ist
   normal.
3. Freie IP für den Laptop in UniFi reservieren. Vorschlag **192.168.2.2**
   (antwortete am 11.09. weder auf Ping noch per ARP, das ist aber kein Beweis).
4. Offene Fragen (unten) klären.

---

## P1 — media: 24 → 32 GB

**Stand 11.09. 18:53: 28 GB.** 3× 8 GB `M378B1G73QH0-CK0` (ChannelA-DIMM0,
ChannelB-DIMM0, ChannelB-DIMM1) plus 1× 4 GB `M378B5173QH0-CK0` in
ChannelA-DIMM1. Der vierte 8-GB-Riegel ist laut Ingo defekt, mit ihm startete
media nicht. **Für 32 GB fehlt also ein funktionierender `M378B1G73QH0-CK0`**,
der den 4-GB-Riegel in A-DIMM1 ersetzt. Der Memtest steht noch aus.

**Fenster:** ~30 min, media ist währenddessen offline. Nicht legen auf:
- 22:30–23:30: db11-Dump + borg db11, borg mail05 um 23:00 (Repos liegen auf media)
- So 04:40: `borg-maintenance-compact`
- am 1. des Monats 05:17: `borg-maintenance-check`

Plex/NFS-Nutzer vorwarnen.

```bash
# vorher, von cloud61
ceph -s                              # muss 497 active+clean zeigen
ceph osd set-group noout media       # nur media, nicht clusterweit

# media
systemctl stop elasticsearch plexmediaserver
poweroff
# Module tauschen, booten

# danach auf media
free -g                              # ~31 GiB total
dmidecode -t 17 | grep -E 'Size|Locator:'   # 4× 8 GB
systemctl status ceph-osd@3 ceph-osd@4 elasticsearch plexmediaserver

# von cloud61
ceph osd tree | grep -A3 'host media'  # osd.3/4 up
ceph osd unset-group noout media
ceph -s                              # warten bis wieder active+clean
```

Danach **einen vollständigen Memtest** fahren: Das verlangt der
media-Umbauplan, und für die heutige 24-GB-Bestückung steht er seit dem 27.08.
auch noch aus. Beides lässt sich in einem Fenster erledigen.

Rollback: alte Module wieder einsetzen, sonst nichts zu tun.

---

## P2 — Laptop als PVE-Node

**Voraussetzungen** (Laptop vorher prüfen):
- **RAM ≥ 16 GB.** Bei 16 GB passt genau wrk1 mit 12 GB. Bei 32 GB kann er
  zusätzlich **jens05 (5,9 GB) von cloud65** übernehmen, das ist heute überbucht.
- CPU: `grep -owE 'ssse3|sse4_2|aes|popcnt' /proc/cpuinfo | sort -u` muss alle
  vier liefern, dazu VT-x/AMD-V im BIOS.
- **Kabel-LAN.** Corosync nie über WLAN. Ein USB-NIC nur mit festem Namen per
  systemd-`.link` auf die MAC.
- SSD mit ≥ 60 GB frei für `local-zfs`.

**Installation:**
- **PVE 9.2.11** (Clusterstand, cloud58 hängt noch auf 9.2.3, separat), Dateisystem
  **ZFS (RAID0)**, damit `local-zfs` wie auf den anderen Nodes existiert
  (storage.cfg hat keine `nodes`-Einschränkung).
- Name nach Schema, Vorschlag **`cloud68`**, IP aus P0. DNS-Eintrag `*.jit.land`
  anlegen.
- Laptop-Eigenheiten:
  ```bash
  # /etc/systemd/logind.conf
  HandleLidSwitch=ignore
  HandleLidSwitchExternalPower=ignore
  HandleLidSwitchDocked=ignore
  systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
  # ARC klein halten
  echo 'options zfs zfs_arc_max=1073741824' > /etc/modprobe.d/zfs.conf && update-initramfs -u
  ```
  Im BIOS „Power on AC" setzen und, falls vorhanden, ein Ladelimit (~80 %). Der
  Akku dient als Mini-USV, 24/7 auf 100 % bläht er sich auf.

**Beitritt** (Laptop ohne eigene Gäste):
```bash
pvecm add 192.168.2.8 --link0 192.168.2.2
pvecm status        # 10 Nodes, Quorum 6
pveceph install     # nur Client-Pakete für vmimages/cephfs — KEIN OSD, KEIN Mon
```

**Nicht:** Ceph-OSD/Mon auf dem Laptop, HA-Ressourcen darauf.

**Quorum:** Mit dem Laptop sind es 10 Stimmen (Quorum 6), mit `pve-media` aus
dem media-Umbau 11. Die rechnerische Ausfalltoleranz bleibt gleich, ein QDevice
ist nicht nötig. **pve2 NICHT zurückbauen** (Korrektur 11.09.): pve2 hat zwar
keine VMs, ist aber NFS-Server für `/downloads`, `/data` und den
Pre-PVE-Backup-Satz von media.

Monitoring: telegraf → vizmon01 nachziehen (siehe Monitoring-Lücken).

---

## P3 — Platz auf cloud62 und cloud64 schaffen (kein k8s-Ausfall)

1. **media-test-trixie (VM 2009, cloud62) NICHT stoppen** (Korrektur 11.09.).
   Sie ist der vorbereitete Nachfolger von media
   (`/etc/ansible/playbooks/media_storage_guest.yml` auf cfgmgmt01) und zieht
   nach der Neuinstallation live auf `pve-media` um (die Disk liegt auf Ceph).
   Erst dann sind die 8 GB auf cloud62 frei. Bis dahin kann wrk4 dort nicht auf
   12 GB. Ausweg: wrk4 vorher live auf einen anderen Host verschieben, seine
   Disk liegt ebenfalls auf Ceph.
2. **mx02 (VM 2027, 6 GB, 25 G local-zfs) cloud64 → cloud58**, live. Vorbild:
   db10 mit 112 ms Downtime. Außerhalb der Mail-Spitzen fahren, Postfix-Queues
   holen den Rest nach.
   ```bash
   ssh root@cloud64 qm migrate 2027 cloud58 --online --with-local-disks
   ```
   Port-Forward :25/:587 → .209 bleibt unverändert, die IP wandert mit.

---

## P4 — wrk1 von pve auf den Laptop (online)

```bash
ssh root@pve qm migrate 2046 cloud68 --online --with-local-disks
```
40 G über 1 GbE, ~5–8 min. Die Pods laufen durch, weil nichts neu startet.
Danach `kubectl get nodes` und Load/Swap auf pve prüfen (Soll 20,5 GB vergeben).

Die tfvars **sofort** angleichen (P6), sonst will jeder `plan` wrk1 ersetzen
(`node_name` forces replacement, siehe 24.08.).

---

## P5 — Worker 8 → 12 GB, strikt einer nach dem anderen

| Reihenfolge | Node | VMID | Host | Voraussetzung |
|---|---|---|---|---|
| 1 | wrk2 | 2042 | cloud58 | keine, **sofort machbar** |
| 2 | wrk4 | 2014 | cloud62 | P3.1 |
| 3 | wrk3 | 2010 | cloud64 | P3.2 |
| 4 | wrk1 | 2046 | cloud68 | P4 |

wrk1 kommt zuletzt: bis dahin haben die anderen drei Platz für seine
CNPG-Primaries.

Ablauf je Node (~5 min; Single-Replica-Dienste des Nodes sind 1–3 min weg):
```bash
N=kellerio-wrk2; VMID=2042; HOST=cloud58

kubectl cordon $N
# alles außer CNPG verdrängen (CNPG-PDBs erlauben 0 Disruptions)
kubectl drain $N --ignore-daemonsets --delete-emptydir-data \
  --pod-selector='!cnpg.io/cluster' --timeout=10m
# CNPG-Instanzen gezielt umsetzen, landen dank cordon auf anderen Nodes
kubectl get pods -A -l cnpg.io/cluster --field-selector spec.nodeName=$N
kubectl -n <ns> delete pod <cluster>-1        # je DB ~1–2 min weg, einzeln!

ssh root@$HOST "qm set $VMID --memory 12288 && \
  qm shutdown $VMID --timeout 90 --forceStop 1 && qm start $VMID"

kubectl wait --for=condition=Ready node/$N --timeout=10m
# bekannte Falle: Cilium-Agent nach VM-Neustart tot → blockiert jeden neuen Pod
kubectl -n kube-system get pods -l k8s-app=cilium -o wide --field-selector spec.nodeName=$N
kubectl uncordon $N
kubectl get node $N -o jsonpath='{.status.allocatable.memory}'   # ~11,5 GiB
```

Nach allen vier: `kubectl top nodes`, `kubectl get pods -A | grep -vE 'Running|Completed'`,
Stichproben webmail.jit.services, lists.jitmail.de, kimai.savar.de. Die
Pod-Verteilung ist danach schief, K8s verteilt nicht zurück. Falls nötig
Rebalancing wie am 07.08. per `rollout restart` zustandsloser Deployments.

Rollback je Node: dasselbe mit `--memory 8192`.

---

## P6 — Git nachziehen (Tofu nur prüfen, nie anwenden)

`cluster.auto.tfvars`:
- `default_memory_mb = 12288` (gilt nur für Worker, CPs haben eigene Werte)
- wrk1: `target_pve = "cloud68"` mit Kommentar

Danach `just plan`. **Erwartung: keine Änderung an `talos_node`.**

⚠️ **Für diese Änderung nie `just apply`.** Das Modul setzt
`reboot_after_update` nicht auf false. Der bpg-Provider darf also neu starten
und würde **alle vier Worker gleichzeitig** neu starten. Deshalb live per `qm`
(wie bei den CPs am 07.08.) und tfvars nur als Soll-Stand, damit keine Drift
entsteht.

Doku zusätzlich nach `cfgmgmt01:/root/ansible/kellerio-docs/`.

---

## Offene Fragen (blockieren)

1. **Laptop:** Modell, RAM, CPU, Kabel-NIC? Passen Name `cloud68` und IP
   `192.168.2.2`? → blockiert P2/P4 und damit wrk1.
2. ~~media-test-trixie: darf die VM aus?~~ **Geklärt am 11.09.:** Nein, sie ist
   der Nachfolger von media. wrk4 wartet auf ihren Umzug nach `pve-media`.
3. **Elasticsearch auf media:** wird es noch gebraucht? Wenn ja: Heap 4 GB. Wenn
   nein: abschalten. → sollte **vor** P1 entschieden sein.
4. **media-Module:** schon beschafft, gleiche Part-Nummer?

## Nebenbefunde (nicht Teil dieses Plans)

- **cloud65 ist überbucht:** ~7 GB Budget, 11,9 GB vergeben (cp3 6 + jens05 5,9),
  nur 2,4 GB frei. Lösung, wenn der Laptop 32 GB hat: jens05 dorthin.
- cloud58 läuft noch PVE 9.2.3, alle anderen 9.2.11.
- osd.3/osd.4 (media) laufen mit Ceph 19.2.3, osd.4 ist `out`.
- pve bleibt auch nach P4 der Host mit 4 Kernen, 2 OSDs und dem cluster-weiten
  dnsmasq und bekommt deshalb keine neue Last.
