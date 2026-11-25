# Runbook: Nextcloud down after TrueNAS restart ("data directory is invalid")

_Confirmed fix, 2026-11-17. Updated for K3s on 2026-11-25 ([INC-001](../incidents/2026-11-17-nextcloud-zfs-mountpoint.md), [INC-002](../incidents/2026-11-17-nextcloud-stale-bind-mount.md)). Use this first whenever Nextcloud breaks after TrueNAS reboots._

## Setup
| | |
|---|---|
| Nextcloud host | Raspberry Pi `raspi1`, 192.168.1.57, K3s namespace `nextcloud`. Nextcloud 35 on hostPort :7580, Deployments `nextcloud`, `nextcloud-cron`, `db-nextcloud`, `redis-nextcloud` |
| Storage | TrueNAS SCALE, 192.168.1.226 (HP EliteDesk G4 mini, internal SSD + 2 external USB HDDs) |
| ZFS | pool `Nextcloud`, dataset `Nextcloud/Nextcloud` → must mount at `/mnt/Nextcloud/Nextcloud` |
| NFS | TrueNAS exports `/mnt/Nextcloud/Nextcloud` (NFSv4.2). The Pi mounts it at `/mnt/nextcloud-data` via `/etc/fstab` |
| Inside the container | data dir = `/var/www/html/data` (bind of `/mnt/nextcloud-data`), files owned by `www-data` (uid 33) |
| Pi user | `kubectl` is run as `sudo k3s kubectl` |

## Symptom chain (how it showed up)
1. Nextcloud (`http://192.168.1.57:7580/status.php`) → HTTP 503: **"Your data directory is invalid. Ensure there is a file called .ncdata…"**
2. On the Pi: `sudo ls /mnt/nextcloud-data/.ncdata` → *Permission denied*, later *No such file or directory*
3. `sudo mount -a` → **`mount.nfs: access denied by server while mounting 192.168.1.226:/mnt/Nextcloud/Nextcloud`**
4. TrueNAS → Datasets shows the dataset as **not shared**. Saving the NFS share fails with **`[ENOENT] Path /mnt/Nextcloud/Nextcloud not found`**, and the path picker can't see it, even though the pool is ONLINE.
5. After fixing TrueNAS and remounting, Nextcloud still said **"data directory is invalid" + "not writable"**, because the container had been started before the share was mounted (see the last step of the fix).

> The original incident happened on Docker/CasaOS. The commands below are the K3s equivalents. The failure mode is the same, because a `hostPath` volume is a bind mount.

## Root cause
The ZFS `mountpoint` property of the pool was set to `/mnt/Nextcloud`. TrueNAS imports pools with `altroot=/mnt`, so ZFS prepended `/mnt` twice:
- `Nextcloud` → `/mnt/mnt/Nextcloud`
- `Nextcloud/Nextcloud` → `/mnt/mnt/Nextcloud/Nextcloud`

So `/mnt/Nextcloud/Nextcloud` didn't exist → NFS share invalid → Pi mount denied → Nextcloud saw an empty data dir.
Exporting the pool to fix it is **blocked**, because the pool also holds TrueNAS system datasets (`Nextcloud/.system/samba4` at `/var/db/system/samba4`).

## Fix
### On TrueNAS (shell)
```bash
# 1. Inspect
zfs list -r -o name,mounted,mountpoint,canmount Nextcloud

# 2. Reset the mountpoint in place (no export needed). With altroot=/mnt this resolves to /mnt/Nextcloud
sudo zfs set mountpoint=/Nextcloud Nextcloud

# 3. Verify
zfs list -r -o name,mounted,mountpoint Nextcloud
ls -la /mnt/Nextcloud/Nextcloud
```
Expected: `Nextcloud` mounted at `/mnt/Nextcloud`, `Nextcloud/Nextcloud` at `/mnt/Nextcloud/Nextcloud`, and the Nextcloud data (`appdata_*`, user folders, `.ncdata`) visible inside.

### On TrueNAS (web UI)
1. **Shares → Unix (NFS) Shares → Add/Edit**: Path `/mnt/Nextcloud/Nextcloud`, **Read Only unchecked**, **Enabled checked** → Save (no more `[ENOENT]`).
2. **System → Services → NFS**: Running, **Start Automatically** ticked.

### On the Pi
```bash
sudo umount -f -l /mnt/nextcloud-data
sudo mount -a
mount | grep nextcloud-data                               # must show 192.168.1.226:/mnt/Nextcloud/Nextcloud … nfs4 (rw,…)
sudo -u '#33' ls -la /mnt/nextcloud-data/.ncdata          # uid 33 = www-data; must list the file
sudo -u '#33' touch /mnt/nextcloud-data/.writetest && echo WRITABLE && sudo -u '#33' rm /mnt/nextcloud-data/.writetest

# ALWAYS restart the pods after (re)mounting. A running container keeps
# seeing the empty local folder it started with, not the newly mounted share.
sudo k3s kubectl -n nextcloud rollout restart deployment/nextcloud deployment/nextcloud-cron
sudo k3s kubectl -n nextcloud rollout status deployment/nextcloud

# Verify from inside the pod (as www-data, because of root_squash)
sudo k3s kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/sh www-data -c 'ls -la /var/www/html/data | head'
```
Healthy result: `http://192.168.1.57:7580/status.php` returns JSON with `"installed":true,"maintenance":false`.

## Don'ts
- Don't create a new pool, "Add to pool", wipe, or replace disks. The data is intact on the existing pool.
- Don't run the Nextcloud installer against the empty mountpoint.
- `sudo ls` on the NFS mount can show *Permission denied* because of root squash. Test as uid 33 instead.

## Quick check from the dashboard
Homarr board `http://192.168.1.57:7575/boards/homelab`: the Nextcloud tile goes red, and the TrueNAS tile's pool list shows the pool's state. Beszel (`:8090`) shows whether TrueNAS itself is up.
