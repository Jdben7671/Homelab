# Runbook: safe shutdown / startup order (power cut, maintenance, NAS updates)

Nextcloud is the only service that spans both hosts, so the order only matters for it. Everything else on the Pi is independent of the NAS.

## Planned shutdown
1. **Pi:** `sudo docker stop nextcloud big-bear-nextcloud-cron-1` (stop writers to the NFS share first)
2. **Pi:** `sudo umount /mnt/nextcloud-data`
3. **TrueNAS:** shut down / update / reboot
4. Pi-hole, Home Assistant and the rest stay up the whole time

## Startup (or after a power cut)
1. **TrueNAS** boots. Wait until the pool is `ONLINE` and the NFS service is running:
   ```bash
   zpool status Nextcloud
   zfs list -r -o name,mounted,mountpoint Nextcloud   # must be /mnt/Nextcloud/Nextcloud, NOT /mnt/mnt/...
   ```
2. **Pi**, mount and verify as uid 33:
   ```bash
   sudo mount -a && mount | grep nextcloud-data
   sudo -u '#33' test -f /mnt/nextcloud-data/.ncdata && echo OK
   ```
3. **Pi**, (re)start Nextcloud so it binds the *real* share:
   ```bash
   sudo docker restart nextcloud big-bear-nextcloud-cron-1
   ```
4. Verify: `./scripts/healthcheck.sh` → all `OK`.

If the [`nextcloud-nfs-guard`](../scripts/nextcloud-nfs-guard.sh) timer is installed, steps 2–3 happen automatically within 5 minutes.

If step 1 shows `/mnt/mnt/...`, go to [nextcloud-down-after-truenas-restart.md](nextcloud-down-after-truenas-restart.md).
