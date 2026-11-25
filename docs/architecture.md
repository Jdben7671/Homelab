# Architecture

Three machines, each with a clear job:

- **`raspi1`** (Raspberry Pi 5) is the K3s control plane and primary worker, and runs every stateful workload.
- **`raspi2`** (Raspberry Pi 4) is a K3s worker that provides **redundancy**: a second Pi-hole and a cold-standby Home Assistant.
- **`truenas`** owns bulk storage (ZFS) and shares it over NFS.

Until 2026-11-25 everything ran as Docker containers under CasaOS on `raspi1` alone. See the [migration write-up](migration-casaos-to-k3s.md) and [ADR-0004](adr/0004-migrate-to-k3s.md).

```mermaid
flowchart LR
  remote["Phone / laptop (away from home)"]

  subgraph LAN["Home LAN · 192.168.1.0/24"]
    clients["LAN clients"]

    subgraph K3S["K3s cluster"]
      subgraph PI1["raspi1 · Pi 5 8 GB · 192.168.1.57 · control plane"]
        ts["Tailscale (host)"]
        ph1["Pi-hole primary :53"]
        ha1["Home Assistant :8123"]
        esp["ESPHome :6052"]
        subgraph NS["namespace: nextcloud"]
          nc["Nextcloud :7580"]
          pg[("PostgreSQL 14")]
          redis[("Redis 6.2")]
        end
        mon["Homarr · Beszel · Dozzle (k8s mode) · n8n"]
      end
      subgraph PI2["raspi2 · Pi 4 2 GB · 192.168.1.126 · worker"]
        ph2["Pi-hole backup :53"]
        ha2["Home Assistant standby (replicas: 0)"]
      end
    end

    subgraph NAS["truenas · HP EliteDesk G4 mini · TrueNAS SCALE · 192.168.1.226"]
      nfs["NFSv4.2 /mnt/Nextcloud/Nextcloud"]
      zfs[("ZFS pool 'Nextcloud' · 2 × USB HDD")]
    end

    iot["Philips Hue · Alexa · Apple TV · ESP32 boards"]
  end

  remote -- "WireGuard (Tailscale)" --> ts
  clients -- "DNS" --> ph1
  clients -- "DNS (secondary)" --> ph2
  nc --> pg
  nc --> redis
  nc -- "hostPath /mnt/nextcloud-data (NFS)" --> nfs
  nfs --> zfs
  ha1 --> iot
  ha1 -. "nightly rsync 02:00" .-> ha2
  mon -. "metrics" .-> NAS
```

## Hosts

| Host | Hardware | Role |
|---|---|---|
| `raspi1` · 192.168.1.57 | Raspberry Pi 5 (8 GB RAM), 128 GB microSD, Debian 13 | K3s server (control plane) + worker. Runs Nextcloud, Home Assistant, ESPHome, Pi-hole primary, monitoring. Tailscale on the host |
| `raspi2` · 192.168.1.126 | Raspberry Pi 4 (2 GB RAM) | K3s agent (worker). Pi-hole backup, Home Assistant cold standby |
| `truenas` · 192.168.1.226 | HP EliteDesk G4 mini, internal SSD + 2 external USB HDDs, TrueNAS SCALE | ZFS storage, NFS server, Beszel agent |

## Design principles

1. **Separate compute from storage.** Pods use `hostPath` volumes on the Pi for small app config (`/DATA/AppData`). Bulk user data lives on ZFS on the NAS.
2. **Redundancy where it's cheap and matters most.** DNS runs on *both* nodes, because if it's down the whole house is "offline". Home Assistant has a warm config copy on the second node.
3. **Placement over magic.** Workloads are pinned with `nodeSelector`. With `hostPath` storage and a 2 GB second node, automatic rescheduling would do more harm than good. Failover is a deliberate, documented `kubectl scale` ([runbook](../runbooks/home-assistant-failover.md)).
4. **Keep the edges stable.** `hostNetwork`/`hostPort` keep every service on the same IP:port it had before. Kubernetes Services reuse the old Docker hostnames (`db-nextcloud`, `redis-nextcloud`).
5. **Everything observable from one place.** Homarr for status, Beszel for host metrics, Dozzle for logs from every pod.
6. **No inbound ports from the internet.** Remote access goes over Tailscale ([ADR-0003](adr/0003-tailscale-for-remote-access.md)).
7. **Secrets never in Git.**

## Dependencies and boot order

```mermaid
flowchart TD
  A["TrueNAS boots"] --> B["ZFS pool imports"]
  B --> C["NFS service starts"]
  C --> D["raspi1 mounts /mnt/nextcloud-data"]
  D --> E["Nextcloud pods start"]
  F["raspi1 boots: K3s server"] --> G["Pi-hole primary, HA, ESPHome, monitoring"]
  F --> D
  H["raspi2 boots: K3s agent"] --> I["Pi-hole backup"]
  F -.-> H
```

Only Nextcloud depends on the NAS. See [`runbooks/boot-order.md`](../runbooks/boot-order.md).

Related: [storage](storage.md) · [networking](networking.md) · [monitoring](monitoring.md) · [security](security.md) · [migration](migration-casaos-to-k3s.md)
