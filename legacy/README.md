# Legacy: CasaOS / Docker Compose (until 2026-11-25)

Before the [migration to K3s](../docs/migration-casaos-to-k3s.md), every service ran as a Docker Compose project managed by CasaOS on `raspi1`. These are the sanitized versions of those live configs. They're kept because:

- they document exactly what was migrated (mounts, env, ports), and the K3s manifests reproduce them 1:1,
- INC-001 and INC-002 happened on this setup,
- they're a working rollback path (`docker compose up -d` with the same `/DATA/AppData` directories).

CI still validates them, so they stay correct.

| Stack | Became on K3s |
|---|---|
| `pihole` | `pihole-primary` (raspi1) + `pihole-backup` (raspi2) |
| `homeassistant` | `homeassistant-primary` (raspi1) + `homeassistant-backup` (raspi2, cold standby) |
| `nextcloud` | namespace `nextcloud`: `nextcloud`, `nextcloud-cron`, `db-nextcloud`, `redis-nextcloud` |
| `dozzle` | `dozzle` in Kubernetes mode |
| `homarr`, `beszel` | same names, `hostNetwork` |
| `_retired/n8n` | re-enabled as `n8n` |
| `_retired/nginx-proxy-manager` | still retired |
