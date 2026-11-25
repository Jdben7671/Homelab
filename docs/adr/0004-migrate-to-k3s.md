# ADR-0004: Migrate from CasaOS/Docker Compose to a two-node K3s cluster

**Status:** Accepted (2026-11-25). Supersedes [ADR-0001](0001-casaos-on-raspberry-pi.md).

## Context

Everything ran on one Raspberry Pi under CasaOS. That worked, but:

- **One node = one failure domain.** If `raspi1` went down, the whole house lost DNS (Pi-hole) and the smart home (Home Assistant) at once.
- **No failover path.** A second machine (a Raspberry Pi 4, 2 GB) was available, but CasaOS has no notion of more than one host.
- **GUI-driven state.** CasaOS generates and owns the compose files, so the deployed state and the repo drift apart.
- Kubernetes is the industry-standard way to describe and schedule workloads, and running it on real hardware is worth the learning.

## Decision

- **K3s** (lightweight, single binary, ARM-friendly) on two nodes:
  - `raspi1` (Pi 5, 8 GB): control plane + primary worker. Runs everything stateful.
  - `raspi2` (Pi 4, 2 GB): worker for **redundancy** (second Pi-hole) and **cold standby** (Home Assistant at `replicas: 0`).
- Workloads are pinned with `nodeSelector` and use `hostPath` volumes on the **existing** `/DATA/AppData` directories. No data copied, no new storage layer.
- `hostNetwork: true` for LAN-facing services (DNS, HA discovery, dashboards) so ports and IPs stay as they were.
- Nextcloud gets its own namespace, with ClusterIP Services named after the old container hostnames.

### Alternatives considered

| Option | Why not |
|---|---|
| Stay on CasaOS, add a second CasaOS box | Two unrelated hosts, no shared scheduling, manual failover |
| Docker Swarm | Easier, but little industry relevance and limited ecosystem |
| Full Kubernetes (kubeadm) | Too heavy for a 2 GB Pi 4 control/worker split |
| Longhorn / distributed storage | Needs 3+ nodes and RAM the Pi 4 doesn't have. NFS from TrueNAS already covers bulk data |

## Consequences

- **Pro:** DNS survives the loss of either node (two Pi-holes).
- **Pro:** Home Assistant has a tested recovery path. It was used for real during the migration ([INC-004](../../incidents/2026-11-25-casaos-uninstall-deleted-ha-config.md)).
- **Pro:** Declarative manifests and `kubectl` replace GUI state. Dozzle uses Kubernetes RBAC instead of the Docker socket.
- **Con:** `hostPath` + `nodeSelector` means most workloads **can't** move between nodes automatically. This is a placement-managed cluster, not a self-healing one. Accepted: the second node lacks the RAM to take over the big workloads anyway.
- **Con:** K3s uses its own containerd, so images had to be pulled again or imported. One image was no longer available upstream ([INC-005](../../incidents/2026-11-25-nextcloud-image-removed-upstream.md)).
- **Con:** A single control plane on `raspi1` is still a single point of failure for the API (running pods keep working, but nothing can be rescheduled).
- **Con:** More moving parts than Compose: RBAC, CoreDNS, image import, and node pinning to keep in mind.
