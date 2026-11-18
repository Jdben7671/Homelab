# Runbook: updating a service safely

1. **Read the release notes** for the new version (breaking changes, DB migrations).
2. **Back up first** (minimum):
   ```bash
   sudo tar czf ~/backup-$(date +%F)-<app>.tgz /DATA/AppData/<app>
   # Nextcloud DB:
   sudo docker exec db-nextcloud pg_dump -U "$POSTGRES_USER" nextcloud > ~/nextcloud-db-$(date +%F).sql
   ```
3. **Bump the version in this repo** (`stacks/<app>/compose.yaml`: tag *and* digest) and open a PR, or merge the Renovate PR. CI validates the compose file.
4. **Apply** on the Pi (CasaOS UI → app → settings, or):
   ```bash
   cd stacks/<app> && sudo docker compose pull && sudo docker compose up -d
   ```
5. **Verify** with `./scripts/healthcheck.sh` and the app's logs in Dozzle.
6. **Rollback** if needed: revert the commit, `docker compose up -d`, restore the backup from step 2 if a migration ran.

### Service-specific notes
- **Nextcloud**: upgrade one *major* version at a time (34 → 35 → 36). Afterwards: `sudo docker exec -u 33 nextcloud php occ upgrade` and `occ db:add-missing-indices`.
- **Postgres**: a *major* upgrade (14 → 16) needs dump and restore, not just a new image.
- **Pi-hole**: DNS for the whole house goes down during the restart. Do it when nobody is streaming or in a call.
