# Monitoring and observability

Three tools, each answering a different question:

| Question | Tool | Where |
|---|---|---|
| *Is every service up right now?* | **Homarr** board with status tiles for each app, plus the TrueNAS integration showing pool state | `:7575/boards/homelab` |
| *Is the hardware OK? CPU, RAM, disk, temperatures, history?* | **Beszel** hub on the Pi, agent on TrueNAS | `:8090` |
| *What is a container actually saying?* | **Dozzle** shows live logs for the Pi's containers and the NAS's containers (remote agent) | `:8888` |
| *Is it healthy from a client's point of view?* | [`scripts/healthcheck.sh`](../scripts/healthcheck.sh) does HTTP and DNS checks for every service, with a non-zero exit code on failure | CLI |

## How it played out in a real incident

During [INC-001](../incidents/2026-11-17-nextcloud-zfs-mountpoint.md):

1. The **Homarr** Nextcloud tile went red. That was detection.
2. **Beszel** showed TrueNAS itself was up, which ruled out "the NAS is off".
3. Nextcloud's `status.php` returned HTTP 503 *"data directory is invalid"*, which pointed at storage.
4. Mounting the share by hand surfaced `access denied by server`, which pointed at the NFS share and then at the ZFS mountpoint.

The layering paid off: each tool narrowed the problem down one level.

## Gaps / next steps

- Alerting: Beszel supports alerts (email/webhook). Wire them to a phone notification for: host down, disk > 85 %, Pi temperature > 75 °C.
- Run `healthcheck.sh --quiet` from cron and alert on a non-zero exit.
- ZFS scrub results and SMART data from the USB HDDs should feed an alert, not only a dashboard.
