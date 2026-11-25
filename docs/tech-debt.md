# Tech debt register

Found by auditing the live cluster against this repo. Re-audited after the [K3s migration](migration-casaos-to-k3s.md) on 2026-11-25.

## Open

| # | Item | Impact | Fix |
|---|---|---|---|
| TD-1 | TrueNAS system dataset (`.system`) lives on the `Nextcloud` data pool | Blocks exporting/re-importing the pool (blocked the obvious fix in INC-001) | *System → Advanced → Storage*: move it to the boot pool |
| TD-2 | ZFS pool on external **USB** HDDs | USB bridges can drop off the bus or hide SMART data | Move to SATA when hardware allows. Scrub regularly, watch `zpool status` |
| TD-6 | Homarr data under `/data/appdata/homarr`, everything else under `/DATA/AppData` | Easy to miss in a backup of `/DATA/AppData` | Move it, update the `hostPath` |
| TD-7 | `:latest` / `:stable` on Homarr, Dozzle, n8n, Home Assistant | Unreproducible. A pod restart can silently upgrade | Pin versions, let Renovate bump them |
| TD-9 | raspi1 root filesystem on microSD | Wear from Postgres, HA recorder, containerd | Boot the Pi 5 from NVMe/USB SSD |
| TD-10 | Commented-out USB disk line in `/etc/fstab` (`/media/photos`) | Clutter | Delete |
| TD-11 | Live `~/k3s/ha-raspi2.yaml` says `replicas: 1`, cluster is scaled to 0 | Re-applying the file would start a **second Home Assistant** | Set `replicas: 0` in the file (done in this repo's copy) |
| TD-12 | Live manifests on raspi1 contain credentials inline | Anyone who reads `~/k3s` gets them | Switch to Secrets, as in [`k8s/`](../k8s/) |
| TD-13 | Nextcloud image exists only in raspi1's containerd | Card failure = can't start Nextcloud ([INC-005](../incidents/2026-11-25-nextcloud-image-removed-upstream.md)) | Mirror it, then move to the official image |
| TD-14 | Homarr mounts `/var/run/docker.sock` | Root-equivalent access. Docker no longer runs any app | Remove the mount, then uninstall Docker and CasaOS |
| TD-15 | No resource requests/limits, no liveness/readiness probes | No protection against a runaway pod. "Running" doesn't mean "healthy" | Add both, starting with Nextcloud/Postgres |
| TD-16 | The two Pi-holes have separate config dirs and nothing syncs them | Blocklists and local DNS can drift apart | `nebula-sync` (or Teleporter) on a schedule |
| TD-17 | HA standby lacks the primary's `NET_ADMIN`/`NET_RAW` + `/run/dbus` | Bluetooth degraded after a failover | Copy the `securityContext` and dbus mount to the standby manifest |
| TD-18 | Nextcloud's data mount has default propagation | A remount on the host doesn't reach the running pod (INC-002) | `mountPropagation: HostToContainer` on the data volumeMount |
| TD-19 | Leftover Docker images on raspi1 | Wasted space on the SD card | `docker image prune -a`, **after** TD-13 |

## Closed

| # | Item | How |
|---|---|---|
| TD-3 | Pi-hole `TZ=CEST` (invalid) | Manifests set `TZ=Europe/Budapest` on every workload |
| TD-4 | Pi-hole published an unused DHCP port | Gone with `hostNetwork` + K3s |
| TD-5 | Stale duplicate Pi-hole app in CasaOS | CasaOS app definitions no longer used |
| TD-8 | CasaOS set every memory limit to total RAM | CasaOS no longer generates the specs (real limits tracked as TD-15) |
| — | Home Assistant ran `privileged` | Replaced by `NET_ADMIN` + `NET_RAW` |
| — | Dozzle had the Docker socket | Replaced by read-only Kubernetes RBAC |
| — | Default/shared credentials | Rotated |
