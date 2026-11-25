# Incident reports

Blameless postmortems for every outage that took real effort to fix. Each one records what was seen, how it was diagnosed, the root cause, and the follow-up actions that stop it recurring. New ones start from [`TEMPLATE.md`](TEMPLATE.md).

| ID | Date | Title | Severity | Status |
|---|---|---|---|---|
| [INC-001](2026-11-17-nextcloud-zfs-mountpoint.md) | 2026-11-17 | Nextcloud down after TrueNAS restart: ZFS mountpoint resolved to `/mnt/mnt/...` | SEV-2 | Resolved |
| [INC-002](2026-11-17-nextcloud-stale-bind-mount.md) | 2026-11-17 | Nextcloud "data directory not writable" after NFS remount: stale bind mount + root_squash | SEV-3 | Resolved |
| [INC-003](2026-11-24-alexa-disconnects-wan-dhcp-renewal.md) | 2026-11-24 | Alexa integration dropping every ~30 min: router WAN DHCP renewal behind double NAT | SEV-3 | Resolved |
| [INC-004](2026-11-25-casaos-uninstall-deleted-ha-config.md) | 2026-11-25 | Home Assistant config deleted by CasaOS "Uninstall", restored from the cold standby | SEV-2 | Resolved |
| [INC-005](2026-11-25-nextcloud-image-removed-upstream.md) | 2026-11-25 | Nextcloud `ImagePullBackOff`: pinned image tag removed from Docker Hub | SEV-2 | Mitigated |

**Severity scale:** SEV-1 = whole house affected (DNS/network) · SEV-2 = a core service fully down · SEV-3 = degraded / slower recovery.
