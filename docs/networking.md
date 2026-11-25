# Networking

## Addressing

| Host | IP | Notes |
|---|---|---|
| Archer BE550 (main router) | 192.168.1.1 | Behind the ISP gateway (CH7465ONE, 192.168.0.1). **Double NAT.** WAN set to a static IP, see [INC-003](../incidents/2026-11-24-alexa-disconnects-wan-dhcp-renewal.md) |
| `raspi1` | 192.168.1.57 | K3s control plane. Pi-hole primary. Every app |
| `raspi2` | 192.168.1.126 | K3s worker. Pi-hole backup |
| `truenas` | 192.168.1.226 | NFS server |

## Port map

Most workloads use `hostNetwork: true`, so they listen directly on the node's IP. Nextcloud uses a `hostPort`.

| Node | Port | Service | Exposure |
|---|---|---|---|
| raspi1 | 53 tcp/udp | Pi-hole primary (DNS) | hostNetwork |
| raspi1 | 8080 | Pi-hole primary web UI (`/admin`) | hostNetwork |
| raspi1 + raspi2 | 80 / 443 | Traefik ingress (K3s default, via ServiceLB). No Ingress resources yet | ServiceLB |
| raspi1 | 7575 | Homarr | hostNetwork |
| raspi1 | 7580 | Nextcloud | hostPort → 80 |
| raspi1 | 8123 | Home Assistant | hostNetwork |
| raspi1 | 6052 | ESPHome | hostNetwork |
| raspi1 | 8090 | Beszel hub | hostNetwork |
| raspi1 | 8888 | Dozzle | hostNetwork |
| raspi1 | 5678 | n8n | hostNetwork |
| raspi1 | 6443 | K3s API server | host |
| raspi2 | 53 tcp/udp, 8080 | Pi-hole backup | hostNetwork |
| raspi2 | 8123 | Home Assistant standby (only when scaled up) | hostNetwork |
| cluster-internal | 5432, 6379 | `db-nextcloud`, `redis-nextcloud` | ClusterIP only, never published |

With `hostNetwork`, Kubernetes won't stop two pods from claiming the same port on a node. This table is the guard rail. It's also why the HA primary and standby must never run on the same node.

## DNS: two Pi-holes

- `pihole-primary` on `raspi1` and `pihole-backup` on `raspi2`, both answering on port 53 of their node.
- Clients get **both** as DNS servers, so DNS keeps working when either Pi reboots.
- The two instances have **separate config directories** (`/DATA/AppData/big-bear-pihole` on raspi1, `/opt/pihole-k3s` on raspi2). Keep the two blocklists and local DNS records in sync (Pi-hole Teleporter export/import, or a sync tool like `nebula-sync`). Otherwise the two resolvers give different answers.
- Pi-hole doesn't depend on NFS, the database, or the other node.

## Remote access: Tailscale

- Tailscale runs **on the `raspi1` host**, not in the cluster. It survives K3s restarts, which is when remote access matters most.
- **Open issue:** phones lose general internet while connected to the tailnet. The likely cause is that the tailnet's *global nameservers* are set to the LAN IPs of the Pi-holes (`192.168.1.57` / `.126`), which a phone on mobile data can't reach. Fixes, in order of preference:
  1. Use the Pi-holes' **Tailscale `100.x.y.z` addresses** as the tailnet's DNS servers, or
  2. Advertise `192.168.1.0/24` as a **subnet route** from `raspi1` (`tailscale up --advertise-routes=192.168.1.0/24`, approve it in the admin console), or
  3. Use `raspi1` as an **exit node** if all traffic should go through home.

## Cluster networking

- K3s defaults: flannel (VXLAN) pod network, CoreDNS, **Traefik + ServiceLB**. ServiceLB binds `:80`/`:443` on every node, which is why the Pi-holes' web UIs moved to `:8080` (`FTLCONF_webserver_port`). Traefik is the natural place to add HTTPS with proper hostnames later.
- Nextcloud's database and cache are reachable only through ClusterIP Services inside the `nextcloud` namespace. Named `db-nextcloud` and `redis-nextcloud` so the existing `config.php` resolved them unchanged after the move from Docker.
- Home Assistant, ESPHome and Pi-hole need `hostNetwork` for mDNS/SSDP discovery and broadcast-based protocols, which don't cross the pod network.
