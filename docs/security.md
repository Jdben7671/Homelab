# Security

## Current controls

| Area | Control |
|---|---|
| Exposure | No services published to the internet. Remote access only through Tailscale (WireGuard, device-authenticated) |
| Secrets | Kept in per-stack `.env` files that are git-ignored. `.env.example` shows the required keys. CI runs **gitleaks** on every push |
| Network isolation | Postgres and Redis sit on Nextcloud's private bridge network with no host ports |
| Least privilege (Dozzle) | Container actions and web shell disabled (`DOZZLE_ENABLE_ACTIONS=false`, `DOZZLE_ENABLE_SHELL=false`), analytics off |
| Least privilege (Redis) | Runs as non-root `1000:1000` |
| NFS | `root_squash` keeps root on the client from acting as root on the NAS. Data is owned by the app UID (33), not root |
| Supply chain | Core images pinned by version **and** `sha256` digest (Nextcloud, Postgres, Redis, Pi-hole, Beszel). Renovate config proposes updates as PRs |

## Known risks (accepted for now, tracked)

| Risk | Why it exists | Mitigation plan |
|---|---|---|
| Home Assistant runs `privileged` | Easiest way to give it radio and device access | Replace with explicit `devices:` + `cap_add` |
| `docker.sock` mounted into Homarr and Dozzle | Needed to show container status / logs | Put a read-only [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) in front |
| Services are plain HTTP on the LAN | No reverse proxy since NPM was retired | Use Tailscale HTTPS certs (`tailscale cert`) or Caddy with internal TLS |
| Some apps reused a password and kept default DB credentials at install time | CasaOS one-click installs prefill them | Rotate all of them, use a password manager, and generate unique `.env` values per stack |
| NFS export reachable from any LAN host unless restricted | NFS (sys auth) trusts the client's claimed UID | Set the share's *Authorized Hosts* to `192.168.1.57` only |
| Postgres 14.2 / Redis 6.2 are older minor versions | Pinned at install time | Upgrade within the major version first, then plan a major upgrade with `pg_dump` |
