# Migration: CasaOS (Docker) → two-node K3s cluster

**Completed:** 2026-11-25 · **Result:** all workloads migrated, verified, and legacy Docker containers removed. **No data lost** (one near-miss, see [INC-004](../incidents/2026-11-25-casaos-uninstall-deleted-ha-config.md)).
**Decision record:** [ADR-0004](adr/0004-migrate-to-k3s.md)

## Before → after

| | Before | After |
|---|---|---|
| Orchestration | CasaOS + Docker Compose, one host | **K3s**, 2 nodes |
| Nodes | `raspi1` (Pi 5) | `raspi1` (Pi 5, control plane + primary worker) · `raspi2` (Pi 4 2 GB, 192.168.1.126, secondary worker / cold standby) |
| DNS | 1 × Pi-hole | **2 × Pi-hole** (one per node), so DNS survives losing a node |
| Home Assistant | single container | primary on `raspi1` + **cold standby on `raspi2`** with nightly config replication |
| Logs | Dozzle via Docker socket + TrueNAS agent | Dozzle in **Kubernetes mode** (RBAC, every pod on both nodes). TrueNAS container logs are no longer included |
| Nextcloud | 4 containers in one compose project | 4 Deployments + 2 ClusterIP Services in a dedicated `nextcloud` namespace |
| New | | **ESPHome** with USB serial passthrough for flashing ESP32 boards |

## Final layout

Cluster: **K3s v1.37.2+k3s1** (containerd 2.3.7), both nodes Debian 13 "trixie" arm64. K3s defaults kept: CoreDNS, flannel, Traefik + ServiceLB (holding `:80`/`:443` on both nodes), local-path-provisioner, metrics-server. Manifests are in [`k8s/`](../k8s/).

### Namespace `default`

| Workload | Node | Network | Storage / host mounts | Notes |
|---|---|---|---|---|
| `homeassistant-primary` | raspi1 | hostNetwork `:8123` | `/DATA/AppData/homeassistant/config`, `/run/dbus` | Capabilities `NET_ADMIN` + `NET_RAW` for Bluetooth. `strategy: Recreate` |
| `homeassistant-backup` | raspi2 | hostNetwork `:8123` | `/opt/homeassistant-k3s/config` | **`replicas: 0`** (cold standby), config rsynced nightly at 02:00 |
| `esphome` | raspi1 | hostNetwork `:6052` | `/DATA/AppData/esphome/config`, `/dev/ttyUSB0` | `privileged` for serial flashing |
| `dozzle` | raspi1 | hostNetwork `:8888` | stateless | `DOZZLE_MODE=k8s`, ServiceAccount + read-only ClusterRole |
| `pihole-primary` | raspi1 | hostNetwork `:53`, web `:8080` | `/DATA/AppData/big-bear-pihole/*` | Primary DNS |
| `pihole-backup` | raspi2 | hostNetwork `:53`, web `:8080` | `/opt/pihole-k3s/*` | Secondary DNS (own config, not synced) |
| `homarr` | raspi1 | hostNetwork `:7575` | `/data/appdata/homarr/appdata`, host Docker socket | Dashboard |
| `n8n` | raspi1 | hostNetwork `:5678` | `/DATA/AppData/n8n` | Workflow automation (re-enabled, `:latest`) |
| `beszel` | raspi1 | hostNetwork `:8090` | `/DATA/AppData/big-bear-beszel/data` | Monitoring hub |

### Namespace `nextcloud`

| Workload | Kind | Node | Network | Storage |
|---|---|---|---|---|
| `db-nextcloud` | Deployment + ClusterIP Service | raspi1 | `:5432` (cluster-internal) | `/DATA/AppData/big-bear-nextcloud/pgdata` (`postgres:14.2`) |
| `redis-nextcloud` | Deployment + ClusterIP Service | raspi1 | `:6379` (cluster-internal) | `/DATA/AppData/big-bear-nextcloud/redis` (`redis:6.2.20`) |
| `nextcloud` | Deployment | raspi1 | `hostPort 7580 → 80` | `/DATA/AppData/big-bear-nextcloud/html` + `/mnt/nextcloud-data` (NFS from TrueNAS) |
| `nextcloud-cron` | Deployment (`command: /cron.sh`) | raspi1 | none | same as above |

## Approach

The migration was done **one service at a time, in place**, reusing the existing data directories. No data was copied or converted:

1. **Inspect first.** `docker inspect` on each container to record the exact bind mounts, environment and capabilities, so the Kubernetes spec reproduces them 1:1.
2. **Stop the Docker container** to free its port (most workloads use `hostNetwork`).
3. **Apply the manifest**, pinned to a node with a `nodeSelector`, pointing `hostPath` volumes at the *same* `/DATA/AppData/...` directories.
4. **Verify** the app, then move on. The stopped Docker container stays as a rollback path until the end.
5. **Clean up** legacy containers with `docker rm`, **never** with the CasaOS uninstaller (see INC-004).

### Phase 1: Home Assistant + cold standby
- Primary pinned to `raspi1`, `hostNetwork: true` (mDNS/SSDP discovery), `strategy.type: Recreate` so two HA instances never run against the same config at once.
- Standby Deployment on `raspi2` at `replicas: 0`. It uses no CPU or RAM and can't fire duplicate automations. Failover is one `kubectl scale` ([runbook](../runbooks/home-assistant-failover.md)).
- Nightly replication from `raspi1` → `raspi2` with a root cron job using a dedicated `ed25519` key (root is needed to read the `root`-owned `.storage` files):
  ```cron
  0 2 * * * /usr/bin/rsync -az --delete --exclude 'home-assistant_v2.db*' --exclude '*.log*' \
    /DATA/AppData/homeassistant/config/ beni@192.168.1.126:/opt/homeassistant-k3s/config/ >/var/log/ha-sync.log 2>&1
  ```
  The recorder database and logs are excluded: they are large, change constantly, and aren't needed to fail over.

### Phase 2: ESPHome and Dozzle
- **ESPHome** (`esphome/esphome:2026.10`): `privileged` with a `hostPath` for `/dev/ttyUSB0`. The volume deliberately has **no `type: CharDevice`**, so the pod still starts when no ESP32 is plugged in.
- **Dozzle**: switched from Docker-socket mode to `DOZZLE_MODE=k8s`, with its own ServiceAccount and a ClusterRole limited to `get`/`list`/`watch` on pods, pod logs, nodes, namespaces and metrics. One UI now streams logs from both nodes, and Dozzle no longer needs the Docker socket.

### Phase 3: Nextcloud (4 containers)
- New `nextcloud` namespace.
- ClusterIP Services named exactly `db-nextcloud` and `redis-nextcloud`. CoreDNS resolves the same hostnames Docker used, so **Nextcloud's existing `config.php` worked without a single edit**.
- Web pod exposed on `hostPort: 7580`, so existing clients, bookmarks and the Homarr tile kept working.
- Cron runs as a separate Deployment overriding the command to `/cron.sh`.

### Phase 4: Cleanup
Stopped CasaOS containers removed with `sudo docker rm`, keeping every bind-mounted directory under `/DATA/AppData/`.

## Problems hit along the way

| # | Problem | Root cause | Fix |
|---|---|---|---|
| 1 | `ErrImagePull` for `home-assistant:stable` even though the image was on the host | K3s has its **own containerd image store**, separate from Docker, and the pull from `ghcr.io` failed | `docker save … \| k3s ctr images import -` + `imagePullPolicy: IfNotPresent` |
| 2 | HA: *"Bluetooth adapter hci0 is operating in degraded mode"* | Kubernetes drops Linux capabilities by default, so BlueZ can't manage `hci0` or run passive BLE scans | Add `NET_ADMIN` + `NET_RAW` under `securityContext.capabilities.add` (+ `/run/dbus` mount). Avoids running HA fully `privileged` |
| 3 | HA dashboards gone, `.storage/lovelace*` missing | Uninstalling the old app in the **CasaOS UI deleted `/DATA/AppData/homeassistant`** | Restored from the `raspi2` standby copy → [INC-004](../incidents/2026-11-25-casaos-uninstall-deleted-ha-config.md) |
| 4 | `ImagePullBackOff`: *pull access denied* for `big-bear-nextcloud-with-smbclient:35.0.1` | Tag **removed from Docker Hub**. The local copy existed only by digest, without a tag | Re-tag by image ID, import into containerd → [INC-005](../incidents/2026-11-25-nextcloud-image-removed-upstream.md) |
| 5 | `No space left on device` while taking a safety backup to `/tmp` | `/tmp` is a **RAM-backed tmpfs**, filled by ESPHome's multi-GB `.esphome` build cache | Back up to disk (`/var/backups/appdata-safety-backup`) and `--exclude '.esphome'` |

## Lessons

- **Back up before you clean up, and back up to disk.** The safety backup to tmpfs failed, and the cleanup step was the one that destroyed data. The standby replica built in Phase 1 is what saved the day.
- **Don't let a GUI manage data you've migrated away from it.** "Uninstall" in a one-click platform can mean "delete the data directory".
- **An image you can't pull again is a single point of failure.** Pinning by digest records *what* you ran. It doesn't guarantee you can *get it again*.
- **Keep names stable across platforms.** Matching Service names to old container hostnames, and keeping `hostPort`s, made the Nextcloud cutover a no-op for the app and its clients.

## Open follow-ups

- [ ] Tailscale: mobile clients lose general internet while connected. Likely the tailnet's global nameservers point at the LAN-only Pi-hole IPs (`192.168.1.57` / `.126`) instead of their Tailscale `100.x` addresses (or an exit node is expected but not configured).
- [ ] `docker image prune -a` on `raspi1` to reclaim root-filesystem space. **Only after** INC-005 action item 1 (the Nextcloud image must exist somewhere other than the local Docker cache).
- [ ] Add `raspi2` to Beszel.
- [ ] Set `replicas: 0` in the live `ha-raspi2.yaml` on raspi1 (the repo version already has it). Re-applying the old file would start a second Home Assistant.
- [ ] Move inline credentials in the live manifests into Secrets, as the repo versions do.
