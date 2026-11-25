# Runbook: safe shutdown / startup order (power cut, maintenance, NAS updates)

Nextcloud is the only service that depends on the NAS, so the order only matters for it. Everything else on the cluster is independent of the NAS.

**Rebooting a Pi:** reboot `raspi2` and `raspi1` one at a time, so one Pi-hole is always answering DNS. `raspi1` hosts the K3s control plane: while it's down, running pods on `raspi2` keep working, but nothing can be rescheduled.

## Planned shutdown
1. **raspi1:** `sudo k3s kubectl -n nextcloud scale deploy/nextcloud deploy/nextcloud-cron --replicas=0` (stop writers to the NFS share first)
2. **Pi:** `sudo umount /mnt/nextcloud-data`
3. **TrueNAS:** shut down / update / reboot
4. Pi-hole, Home Assistant and the rest stay up the whole time. After the NAS is back: mount, then scale both Deployments back to `1`

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
3. **raspi1**, (re)start Nextcloud so it binds the *real* share:
   ```bash
   sudo k3s kubectl -n nextcloud rollout restart deployment/nextcloud deployment/nextcloud-cron
   ```
4. Verify: `./scripts/healthcheck.sh` → all `OK`.

If the [`nextcloud-nfs-guard`](../scripts/nextcloud-nfs-guard.sh) timer is installed, steps 2–3 happen automatically within 5 minutes.

If step 1 shows `/mnt/mnt/...`, go to [nextcloud-down-after-truenas-restart.md](nextcloud-down-after-truenas-restart.md).
