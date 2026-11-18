# INC-001: Nextcloud down after TrueNAS restart (ZFS mountpoint resolved to `/mnt/mnt/...`)

| | |
|---|---|
| **Date** | 2026-11-17 |
| **Severity** | SEV-2 (Nextcloud fully unavailable; no data loss) |
| **Services affected** | Nextcloud (web, sync clients) |
| **Status** | Resolved |
| **Runbook** | [`runbooks/nextcloud-down-after-truenas-restart.md`](../runbooks/nextcloud-down-after-truenas-restart.md) |

## Summary

After TrueNAS rebooted, Nextcloud returned HTTP 503 *"Your data directory is invalid"*. The ZFS pool's `mountpoint` property was set to `/mnt/Nextcloud`. TrueNAS imports pools with `altroot=/mnt`, so the dataset was actually mounted at `/mnt/mnt/Nextcloud/Nextcloud`. The NFS share pointed at a path that no longer existed, the Pi's NFS mount was refused, and Nextcloud saw an empty data directory. Fixed in place with `zfs set mountpoint=/Nextcloud Nextcloud`, without exporting the pool or touching any data.

## Impact

- Nextcloud web UI and sync clients unavailable until the fix.
- **No data loss**: the pool was `ONLINE` throughout. The main risk was making things worse by "fixing" the wrong layer (re-creating the pool, or running the Nextcloud installer against the empty directory).

## Detection

The Nextcloud tile on the **Homarr** dashboard went red. **Beszel** showed TrueNAS was up, which ruled out "the NAS is simply off".

## Timeline / diagnosis

Each step peeled back one layer, from the app down to the filesystem:

| # | Layer | Observation | Conclusion |
|---|---|---|---|
| 1 | App | `GET :7580/status.php` → **503** *"data directory is invalid… ensure there is a file called .ncdata"* | Nextcloud can't see its data. Storage problem, not an app problem |
| 2 | Pi filesystem | `sudo ls /mnt/nextcloud-data/.ncdata` → *Permission denied*, later *No such file or directory* | The NFS mount is broken or missing (the first error was a root_squash red herring, see INC-002) |
| 3 | NFS client | `sudo mount -a` → **`mount.nfs: access denied by server while mounting 192.168.1.226:/mnt/Nextcloud/Nextcloud`** | The server is refusing the export, so look at TrueNAS |
| 4 | NFS server | TrueNAS showed the dataset as *not shared*. Re-saving the share failed: **`[ENOENT] Path /mnt/Nextcloud/Nextcloud not found`**, yet the pool was `ONLINE` | The data exists but isn't where the share expects it |
| 5 | ZFS | `zfs list -r -o name,mounted,mountpoint Nextcloud` → mounted at **`/mnt/mnt/Nextcloud`** | Root cause found |
| 6 | Fix attempt | Export/re-import pool to reset it → **blocked**: pool holds TrueNAS system dataset (`Nextcloud/.system`) | Needed an in-place fix |
| 7 | Fix | `zfs set mountpoint=/Nextcloud Nextcloud` | Dataset back at `/mnt/Nextcloud/Nextcloud` |
| 8 | Recovery | Re-enabled NFS share, remounted on Pi, **restarted Nextcloud containers** | `status.php` → `"installed":true,"maintenance":false` |

## Root cause

TrueNAS SCALE imports every pool with `altroot=/mnt` and **prepends** it to each dataset's `mountpoint`. The pool's `mountpoint` had been set to the *absolute* path `/mnt/Nextcloud`, giving:

```
mountpoint=/mnt/Nextcloud   +  altroot=/mnt   →  /mnt/mnt/Nextcloud
Nextcloud/Nextcloud (inherits)                →  /mnt/mnt/Nextcloud/Nextcloud
```

The wrong value only took effect on the next import, which is why things broke **after a reboot** and not when it was set.

## Resolution

```bash
# TrueNAS
sudo zfs set mountpoint=/Nextcloud Nextcloud      # relative to altroot → /mnt/Nextcloud
zfs list -r -o name,mounted,mountpoint Nextcloud  # verify
# UI: re-save NFS share (path /mnt/Nextcloud/Nextcloud), NFS service "Start Automatically"

# Pi
sudo umount -f -l /mnt/nextcloud-data && sudo mount -a
sudo docker restart nextcloud big-bear-nextcloud-cron-1
```

## What went well

- Layered monitoring narrowed the search fast: dashboard → host metrics → app status → mount → share → ZFS.
- Diagnosis went from the app layer downward and **never wrote to the data**: no new pool, no disk replacement, no re-running the Nextcloud installer.

## What didn't

- The misconfiguration sat unnoticed until a reboot. There was no check that the dataset was mounted where the share expected it.
- The obvious fix (export and re-import the pool) was unavailable because the system dataset shares the data pool.
- Recovery needed one more step that wasn't obvious: restarting the containers (→ INC-002).

## Action items

| # | Action | Type | Status |
|---|---|---|---|
| 1 | Write the runbook with exact commands and *don'ts* | mitigate | Done |
| 2 | Enable *Start Automatically* on the TrueNAS NFS service | prevent | Done |
| 3 | `nextcloud-nfs-guard` timer to auto-remount + restart containers | mitigate | Written ([script](../scripts/nextcloud-nfs-guard.sh)), deploy pending |
| 4 | Move TrueNAS system dataset off the data pool (TD-1) | prevent | Open |
| 5 | Alert (not only dashboard) when `status.php` ≠ 200 | detect | Open |
| 6 | Document safe boot order of NAS → Pi | mitigate | [Done](../runbooks/boot-order.md) |
