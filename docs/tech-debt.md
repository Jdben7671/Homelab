# Tech debt register

Found while auditing the live host against this repo. Each item is small. Writing them down is the point.

| # | Item | Impact | Fix |
|---|---|---|---|
| TD-1 | TrueNAS system dataset (`.system`) lives on the `Nextcloud` data pool | The pool can't be exported/re-imported cleanly (blocked the "export and re-import" fix during INC-001) | Move the system dataset to the boot pool: *System → Advanced → Storage* |
| TD-2 | ZFS pool on external **USB** HDDs | USB bridges can drop off the bus or hide SMART data, which ZFS dislikes | Move disks to SATA/internal when hardware allows. Until then, scrub regularly and watch `zpool status` |
| TD-3 | Pi-hole `TZ` is set to `CEST` on the live host | Not a valid tz-database name, so log timestamps can be off | Use `Europe/Budapest` (already done in this repo) |
| TD-4 | Pi-hole publishes `67/udp` (DHCP) | Unused port. DHCP in a bridged container can't see broadcasts anyway | Remove the port mapping |
| TD-5 | A second, stale Pi-hole app definition (`/var/lib/casaos/apps/pihole`, v2026.05.0) is still on disk | It uses the same `container_name` and port 53 as the live one, so starting it by mistake would conflict | Uninstall it in CasaOS |
| TD-6 | Homarr's data lives under `/data/appdata/homarr`, while every other app uses `/DATA/AppData` | Easy to miss in a backup of `/DATA/AppData` | Move it under `/DATA/AppData/homarr` and update the bind mount |
| TD-7 | `:latest` / `:stable` tags on Homarr, Dozzle, Home Assistant, Compose Toolbox | Unreproducible. An image pull can silently upgrade | Pin to the running versions (Dozzle v11.4.3, HA 2026.11.0) and let Renovate bump them |
| TD-8 | CasaOS app definitions set every container's memory limit to the Pi's total RAM | The limit does nothing | Set real limits (e.g. Postgres 512 MB, Redis 128 MB) |
| TD-9 | Root filesystem on microSD | SD cards wear out under constant writes (Postgres, HA recorder) | Boot the Pi 5 from NVMe/USB SSD |
| TD-10 | Leftover commented USB disk mount in `/etc/fstab` (`/media/photos`) | Clutter from before storage moved to TrueNAS | Delete the line |
