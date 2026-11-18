# INC-002: Nextcloud "data directory not writable" after NFS remount (stale bind mount + root_squash)

| | |
|---|---|
| **Date** | 2026-11-17 (during recovery from [INC-001](2026-11-17-nextcloud-zfs-mountpoint.md)) |
| **Severity** | SEV-3 (prolonged an existing outage) |
| **Services affected** | Nextcloud |
| **Status** | Resolved |

## Summary

After the ZFS/NFS problem in INC-001 was fixed and the share was mounted again on the Pi, Nextcloud *still* reported **"data directory is invalid"** and **"not writable"**. The share was fine. The running containers had been started while `/mnt/nextcloud-data` was an empty local directory, and a container keeps the mount it started with. A misleading `Permission denied` from root on the NFS mount (root_squash) slowed diagnosis down.

## Two storage/permission traps

### 1. Bind mounts don't follow mounts created later

Docker bind-mounts `/mnt/nextcloud-data` into the container **when the container starts**. If the NFS share wasn't mounted yet (the NAS was rebooting, and the `bg,nofail` fstab options let the Pi continue booting), the container got the *empty mountpoint directory* underneath. When the NFS share is mounted on the host later, that does not reach into the running container's mount namespace (the default bind propagation is `rprivate`).

Result: the host shows the files and the container shows an empty folder.

```bash
ls /mnt/nextcloud-data/                                  # host: files are there
sudo docker exec -u 33 nextcloud ls /var/www/html/data   # container: empty
```

### 2. root_squash makes `sudo` lie to you

```bash
sudo ls /mnt/nextcloud-data/.ncdata   # Permission denied
```

This looks like a permissions bug, but it is NFS working as designed: root on the client is mapped to `nobody`. The data is owned by **uid 33** (`www-data` in the Nextcloud image), so tests must run as that UID:

```bash
sudo -u '#33' ls -la /mnt/nextcloud-data/.ncdata
sudo -u '#33' touch /mnt/nextcloud-data/.writetest && echo WRITABLE && sudo -u '#33' rm /mnt/nextcloud-data/.writetest
```

## Resolution

```bash
sudo docker restart nextcloud big-bear-nextcloud-cron-1
sudo docker exec -u 33 nextcloud ls -la /var/www/html/data | head   # .ncdata, appdata_*, users
```

## Lessons

- **Order matters across hosts:** storage first, then the containers that use it. After any remount, restart the consumers.
- **Test permissions as the application's UID**, never as root, on network filesystems.
- `bg,nofail` is the right choice for this Pi (DNS must boot even if the NAS is off), but it moves the ordering problem from boot time to runtime. Something has to handle that at runtime.

## Action items

| # | Action | Type | Status |
|---|---|---|---|
| 1 | Add "always restart containers after remount" + uid-33 checks to the runbook | mitigate | ✅ done |
| 2 | [`nextcloud-nfs-guard.sh`](../scripts/nextcloud-nfs-guard.sh): detect "host sees `.ncdata`, container doesn't" → restart containers. Refuse to restart if the host mount itself is missing | mitigate | 🟡 written, deploy pending |
| 3 | Considered: systemd `RequiresMountsFor=` on `docker.service`. **Rejected**, because it would stop *all* containers (including Pi-hole DNS) when the NAS is down | design | ✅ decided |
