# Incident reports

Blameless postmortems for every outage that took real effort to fix. Each one records what was seen, how it was diagnosed, the root cause, and the follow-up actions that stop it recurring. New ones start from [`TEMPLATE.md`](TEMPLATE.md).

| ID | Date | Title | Severity | Status |
|---|---|---|---|---|
| [INC-001](2026-11-17-nextcloud-zfs-mountpoint.md) | 2026-11-17 | Nextcloud down after TrueNAS restart: ZFS mountpoint resolved to `/mnt/mnt/...` | SEV-2 | Resolved |
| [INC-002](2026-11-17-nextcloud-stale-bind-mount.md) | 2026-11-17 | Nextcloud "data directory not writable" after NFS remount: stale bind mount + root_squash | SEV-3 | Resolved |

**Severity scale:** SEV-1 = whole house affected (DNS/network) · SEV-2 = a core service fully down · SEV-3 = degraded / slower recovery.
