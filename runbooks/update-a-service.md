# Runbook: updating a service safely

1. **Read the release notes** for the new version (breaking changes, DB migrations).
2. **Back up first** (minimum):
   ```bash
   sudo tar czf ~/backup-$(date +%F)-<app>.tgz /DATA/AppData/<app>
   # Nextcloud DB:
   sudo k3s kubectl -n nextcloud exec deploy/db-nextcloud -- sh -c 'pg_dump -U "$POSTGRES_USER" nextcloud' > ~/nextcloud-db-$(date +%F).sql
   ```
3. **Bump the version in this repo** (`k8s/<app>.yaml`: tag *and* digest) and open a PR, or merge the Renovate PR. CI validates the manifest.
4. **Pull-test first**: `sudo k3s crictl pull <image>`. If the image can't be pulled, stop here ([INC-005](../incidents/2026-11-25-nextcloud-image-removed-upstream.md)).
5. **Apply** on raspi1:
   ```bash
   sudo k3s kubectl apply -f k8s/<app>.yaml
   sudo k3s kubectl rollout status deployment/<app> [-n nextcloud]
   ```
6. **Verify** with `./scripts/healthcheck.sh` and the app's logs in Dozzle.
7. **Rollback** if needed: `sudo k3s kubectl rollout undo deployment/<app>`, restore the backup from step 2 if a migration ran.

### Service-specific notes
- **Nextcloud**: upgrade one *major* version at a time (34 → 35 → 36). Afterwards: `sudo k3s kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/sh www-data -c 'php occ upgrade && php occ db:add-missing-indices'`.
- **Postgres**: a *major* upgrade (14 → 16) needs dump and restore, not just a new image.
- **Pi-hole**: update `pihole-backup` (raspi2) first, check it answers, then `pihole-primary`. One resolver stays up the whole time.
