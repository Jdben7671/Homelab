# Storage

## Layout

| Data | Where | Why |
|---|---|---|
| App config + small DBs (`/DATA/AppData/*`, K3s `hostPath` volumes) | raspi1 microSD (117 GB, about 24 % used) | Fast, local, small |
| Home Assistant standby config | raspi2 `/opt/homeassistant-k3s/config` | Nightly rsync from raspi1 |
| Container images | K3s containerd store on each node | See [INC-005](../incidents/2026-11-25-nextcloud-image-removed-upstream.md): some images exist only here |
| Nextcloud Postgres (`pgdata`) | Pi microSD | Postgres over NFS is a known source of locking/corruption issues |
| Nextcloud user files (`data/`) | TrueNAS ZFS → NFS → Pi | Large, needs checksumming and room to grow (900 GB pool) |

## TrueNAS / ZFS

- Pool: `Nextcloud` (on the 2 external USB HDDs). Dataset: `Nextcloud/Nextcloud`.
- TrueNAS imports pools with `altroot=/mnt`, so the **pool's `mountpoint` property must be `/Nextcloud`, not `/mnt/Nextcloud`**. Get this wrong and ZFS mounts the data at `/mnt/mnt/Nextcloud/...`. That is exactly what caused [INC-001](../incidents/2026-11-17-nextcloud-zfs-mountpoint.md).
- The pool also holds the TrueNAS system dataset (`Nextcloud/.system`). This blocks exporting the pool and is tracked in [tech debt](tech-debt.md).

Quick health check on TrueNAS:

```bash
zpool status Nextcloud
zfs list -r -o name,mounted,mountpoint,canmount,used,avail Nextcloud
```

## NFS share

| | |
|---|---|
| Export | `192.168.1.226:/mnt/Nextcloud/Nextcloud`, NFSv4.2, read-write |
| Client mount | `/mnt/nextcloud-data` on `raspi1` |
| fstab | `192.168.1.226:/mnt/Nextcloud/Nextcloud /mnt/nextcloud-data nfs defaults,noatime,bg,nofail 0 0` |
| Ownership | files owned by `www-data` (uid **33**) to match the Nextcloud container |

Mount options were chosen deliberately:

- `bg`: if the NAS is down at boot, keep retrying in the background instead of stalling the Pi's boot. Pi-hole (DNS for the whole house) must come up regardless.
- `nofail`: a missing share must never put the Pi into emergency mode.
- `noatime`: avoids a metadata write on every read over the network.

The trade-off: with `bg,nofail`, K3s (and before it, Docker) can start Nextcloud **before** the share is mounted. The container then bind-mounts the empty local directory and keeps it even after the share arrives ([INC-002](../incidents/2026-11-17-nextcloud-stale-bind-mount.md)). [`scripts/nextcloud-nfs-guard.sh`](../scripts/nextcloud-nfs-guard.sh) closes that gap. On Kubernetes there's also a cleaner fix: set `mountPropagation: HostToContainer` on the `/var/www/html/data` volumeMount, so a mount that appears on the host later also appears inside the running pod.

### Permissions gotcha: root_squash

`sudo ls /mnt/nextcloud-data` returns *Permission denied*. That is expected: NFS maps root to `nobody` (root squash). **Always test as the app's UID:**

```bash
sudo -u '#33' ls -la /mnt/nextcloud-data/.ncdata
sudo -u '#33' touch /mnt/nextcloud-data/.writetest && sudo -u '#33' rm /mnt/nextcloud-data/.writetest
```

## Installing the NFS guard

```bash
sudo install -m 0755 scripts/nextcloud-nfs-guard.sh /usr/local/bin/
sudo install -m 0644 scripts/systemd/nextcloud-nfs-guard.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now nextcloud-nfs-guard.timer
journalctl -t nextcloud-nfs-guard -f     # watch it work
```

## Backups: current state and plan

Current state: user files are on ZFS, which provides checksumming and self-healing scrubs. Home Assistant's config is **replicated** nightly to raspi2. That saved the day in [INC-004](../incidents/2026-11-25-casaos-uninstall-deleted-ha-config.md), but a mirror with `--delete` is not a versioned backup. There is **no off-site copy yet**, and the rest of the app config on raspi1's microSD isn't backed up. This is the biggest open risk in the lab (see the [roadmap](../README.md#roadmap)).

Target (3-2-1):

1. Periodic ZFS snapshots of `Nextcloud/Nextcloud` (TrueNAS Periodic Snapshot Task) for "oops I deleted it" recovery.
2. Nightly `tar` of `/DATA/AppData` (excluding `.esphome` build caches) + `pg_dump` of the Nextcloud DB from raspi1 to a dataset on TrueNAS, plus `k3s ctr images export` of images that can't be pulled again.
3. TrueNAS Cloud Sync task (encrypted) of both to an off-site bucket.
4. A restore test written up as a runbook. A backup that has never been restored doesn't count.
