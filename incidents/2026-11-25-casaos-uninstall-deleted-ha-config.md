# INC-004: Home Assistant dashboards lost after CasaOS "Uninstall" (restored from standby)

| | |
|---|---|
| **Date** | 2026-11-25 (during the [K3s migration](../docs/migration-casaos-to-k3s.md)) |
| **Severity** | SEV-2 (Home Assistant config deleted; fully recovered, no lasting data loss) |
| **Services affected** | Home Assistant |
| **Status** | Resolved |

## Summary

After Home Assistant had moved to K3s (reading its config from the **same** host directory the old Docker container used), the legacy app was removed through the **CasaOS web UI's Uninstall button**. CasaOS's cleanup deleted the entire `/DATA/AppData/homeassistant` tree, which the new Kubernetes pod was still using. HA came back with a blank default dashboard. The full config was restored within minutes from the cold-standby copy on `raspi2`, which had been replicated the night before.

## Impact

- All dashboards, integrations and entity settings (`.storage/`) disappeared from the live instance.
- Automations and devices unavailable until the restore.
- **No permanent loss.** The nightly replica held everything except the recorder history database, which is excluded from replication on purpose.

## Detection

HA loaded an unconfigured default dashboard shortly after the cleanup. On the host:

```bash
ls /DATA/AppData/homeassistant/config/.storage/lovelace*
# No such file or directory
```

## Root cause

The migration reused data **in place**: the K3s `hostPath` volume points at the directory CasaOS created for its app. CasaOS still treated that directory as *its* app data, and "Uninstall" removes the app's data directory along with the container. Two systems believed they owned the same path, and the old one deleted it.

## Resolution

```bash
# stop HA so nothing writes to a half-restored config
sudo k3s kubectl scale deployment/homeassistant-primary --replicas=0

sudo mkdir -p /DATA/AppData/homeassistant/config
sudo rsync -avz beni@192.168.1.126:/opt/homeassistant-k3s/config/ /DATA/AppData/homeassistant/config/

sudo k3s kubectl scale deployment/homeassistant-primary --replicas=1
```

## What went well

- The **cold standby built a few hours earlier in the same migration** became the backup that saved it. Replication had been running before the risky step.
- Scaling to 0 before restoring prevented HA from writing a fresh default config over the restore.

## What didn't

- The cleanup was done through a GUI whose side effects weren't known.
- No fresh on-disk backup was taken right before the cleanup. The attempt to `/tmp` had failed because `/tmp` is a RAM-backed tmpfs (see the [migration doc](../docs/migration-casaos-to-k3s.md#problems-hit-along-the-way)).
- If the 02:00 sync had run *after* the deletion, `rsync --delete` would have mirrored the empty directory to the standby. **A replica is not a backup.**

## Action items

| # | Action | Type | Status |
|---|---|---|---|
| 1 | Remove legacy containers only with `docker rm`, never the CasaOS uninstaller. Applied to every remaining app | prevent | Done |
| 2 | Safety backups go to disk (`/var/backups/...`), excluding build caches | prevent | Done |
| 3 | Make the HA sync keep dated snapshots instead of a single mirror (`rsync --link-dest` or `restic`), so a deletion can't propagate | prevent | Open |
| 4 | Skip the sync if the source looks empty (e.g. `.storage/core.config_entries` missing) | prevent | Open |
| 5 | Uninstall CasaOS itself once nothing depends on it | prevent | Open |
