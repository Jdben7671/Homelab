# Networking

## Addressing

| Host | IP | Notes |
|---|---|---|
| `raspi1` (Raspberry Pi) | 192.168.1.57 | Static. Everything depends on it: DNS, every app |
| `truenas` | 192.168.1.226 | Static. NFS server |

## Port map (`raspi1`)

| Port | Proto | Service | Status |
|---|---|---|---|
| 53 | tcp/udp | Pi-hole DNS | running |
| 8080 / 10443 | tcp | Pi-hole web UI (HTTP / HTTPS) | running |
| 7575 | tcp | Homarr dashboard | running |
| 7580 | tcp | Nextcloud | running |
| 8123 | tcp | Home Assistant (host network) | running |
| 8090 | tcp | Beszel hub | running |
| 8888 | tcp | Dozzle | running |
| 3002 | tcp | Compose Toolbox | running |
| 5678 | tcp | n8n | retired |
| 80 / 443 / 81 | tcp | Nginx Proxy Manager | retired |

On `truenas`: web UI on 80/443, NFS on 2049, Dozzle agent on 7007.

Keeping this table current is the cheapest way to avoid port collisions on a single Docker host. CasaOS will happily let you install two apps on the same port.

## DNS: Pi-hole

- Pi-hole runs in a bridged container and publishes port 53 on the Pi's LAN IP.
- LAN clients use `192.168.1.57` as their DNS server and get network-wide ad and tracker blocking.
- Per-client rate limiting is disabled (`RATE_LIMIT=0/0`) so busy clients are never answered with `REFUSED`.
- Pi-hole is the most critical service in the house. If it is down, "the internet is down" for every device. It therefore depends on nothing else: no NFS, no database.

## Remote access: Tailscale

- Tailscale is installed **on the Pi host**, not in a container. It keeps working while Docker restarts or upgrades, which is when remote access matters most.
- Remote devices reach all services over the encrypted WireGuard mesh using the Pi's Tailscale address.
- This replaced the earlier Nginx Proxy Manager setup, see [ADR-0003](adr/0003-tailscale-for-remote-access.md).

## Docker networks

Each CasaOS app gets its own bridge network (`big-bear-nextcloud_nextcloud_network`, `big-bear-pihole_pihole-network`, ...). Postgres and Redis are reachable **only** on the Nextcloud network and publish no ports on the host. Home Assistant uses `network_mode: host` for mDNS/SSDP discovery (see [home-automation.md](home-automation.md)).
