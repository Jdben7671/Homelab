# ADR-0001: Docker + CasaOS on a Raspberry Pi as the application host

**Status:** Accepted

## Context

The lab needs to run around 10 always-on services (DNS, file sync, smart home, dashboards, monitoring) at home, 24/7, with low power draw and low noise. Services should be easy to add, try out and remove.

## Decision

- A **Raspberry Pi 5 (8 GB)** running Debian 13 is the single application host.
- Every service runs as a **Docker Compose project**.
- **CasaOS** is the management layer: app store (including the BigBearCasaOS community store), web UI for installs, updates and logs.
- Compose files are exported from CasaOS, cleaned up, and version-controlled in [`stacks/`](../../stacks). This makes the repo the readable source of truth for what is deployed.

## Consequences

- ➕ A few watts, silent, cheap to replace.
- ➕ One-click installs make experimenting fast (n8n and Nginx Proxy Manager were tried and retired this way).
- ➖ CasaOS-generated compose files are noisy (UI metadata, memory limits set to total RAM) and use random project names (Homarr's project was `optimistic_kaity`). The cleaned versions in this repo fix that.
- ➖ CasaOS doesn't stop you from installing two apps on the same port or `container_name` (see TD-5). The port table in [networking.md](../networking.md) is the guard rail.
- ➖ Single host = single point of failure for DNS. Pi-hole stays dependency-free to limit the blast radius.
