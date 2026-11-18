# ADR-0002: Nextcloud user data on TrueNAS ZFS, mounted over NFS

**Status:** Accepted

## Context

Nextcloud's user files grow without bound and are the most valuable data in the lab. The Pi's 128 GB microSD card is small, wears out, and has no redundancy or checksumming. Earlier, data lived on a USB disk attached directly to the Pi (a commented-out `/media/photos` line remains in `/etc/fstab`).

## Decision

- A dedicated **TrueNAS SCALE** box (HP EliteDesk G4 mini) owns storage on a ZFS pool.
- The dataset `Nextcloud/Nextcloud` is exported over **NFSv4.2** and mounted on the Pi at `/mnt/nextcloud-data` with `bg,nofail,noatime`.
- That mount is bind-mounted into the container as `/var/www/html/data`. The app code, Postgres and Redis stay on the Pi.

## Consequences

- ➕ ZFS checksums, scrubs, snapshots and room to grow (900 GB pool), independent of the Pi.
- ➕ The Pi can be reinstalled without touching user data.
- ➖ **A cross-host dependency.** Nextcloud now breaks when the NAS reboots, when the share path changes, or when Docker starts before the mount. All of these happened, see [INC-001](../../incidents/2026-11-17-nextcloud-zfs-mountpoint.md) and [INC-002](../../incidents/2026-11-17-nextcloud-stale-bind-mount.md).
- ➖ UID mapping matters: files must be owned by uid 33 (`www-data`), and root on the Pi is squashed.
- Mitigations: a runbook, the boot-order doc, and [`nextcloud-nfs-guard.sh`](../../scripts/nextcloud-nfs-guard.sh).
