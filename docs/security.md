# Security

## Current controls

| Area | Control |
|---|---|
| Exposure | No services published to the internet. Remote access only through Tailscale (WireGuard, device-authenticated) |
| Secrets in Git | None. Manifests in [`k8s/`](../k8s/) read credentials from Kubernetes Secrets ([template](../k8s/secrets.example.yaml)). CI runs **gitleaks** over the full history on every push |
| Credentials | The defaults inherited from CasaOS one-click installs (shared admin/Pi-hole password, default Postgres login) were **rotated** after the migration |
| Network isolation | Postgres and Redis are ClusterIP-only in the `nextcloud` namespace. Never published on a node port |
| Least privilege: Home Assistant | Was `privileged` under Docker. On K3s it gets only `NET_ADMIN` + `NET_RAW` and a read-only `/run/dbus` mount for Bluetooth |
| Least privilege: Dozzle | Was mounting the Docker socket (root-equivalent). Now a dedicated ServiceAccount with a **read-only ClusterRole** (`get`/`list`/`watch` on pods, logs, nodes, namespaces) |
| NFS | `root_squash`. Data owned by the app UID (33), not root |
| Supply chain | Pi-hole, Postgres, Redis, Beszel and ESPHome pinned to versions. Renovate proposes updates as PRs. CI validates every manifest with kubeconform |

## Known risks (accepted for now, tracked)

| Risk | Why it exists | Mitigation plan |
|---|---|---|
| ESPHome runs `privileged` | Simplest way to reach `/dev/ttyUSB0` for flashing | Use the device plugin pattern or `securityContext` with only the needed device + `dialout` group |
| Homarr still mounts the **host Docker socket** | Carried over from CasaOS | Remove the mount (Docker no longer runs the apps), or use Homarr's Kubernetes integration |
| `hostNetwork` on most pods | Needed for DNS, mDNS/SSDP and stable ports | Bypasses NetworkPolicies, so isolation relies on the host firewall. Move dashboards (Homarr, Dozzle, Beszel, n8n) behind Traefik Ingress |
| Services are plain HTTP on the LAN | No TLS since NPM was retired | Traefik is already running: add Ingresses with TLS (`tailscale cert` or an internal CA) |
| Root on raspi1 can SSH into raspi2 (as `beni`) with a passwordless key | Needed by the nightly Home Assistant rsync | Lock the key down in `authorized_keys` with `command="rrsync -wo /opt/homeassistant-k3s/config"`, `from="192.168.1.57"` and `restrict` |
| No resource requests/limits | Not set during migration | One runaway pod can starve Pi-hole on the same node. Add requests/limits, at least for Nextcloud, Postgres and n8n |
| `:latest` / `:stable` tags (Homarr, Dozzle, n8n, Home Assistant) | Convenience | Pin, let Renovate bump |
| Nextcloud image exists only on raspi1 | Upstream tag removed ([INC-005](../incidents/2026-11-25-nextcloud-image-removed-upstream.md)) | Mirror to a registry under my control |
| K3s API (`:6443`) reachable from the whole LAN | K3s default | Firewall it to the two nodes + admin machine |
| NFS export reachable from any LAN host unless restricted | NFS (sys auth) trusts the client's claimed UID | Set the share's *Authorized Hosts* to `192.168.1.57` only |
| Postgres 14.2 / Redis 6.2 are older minor versions | Pinned at install time | Upgrade within the major version first, then plan a major upgrade with `pg_dump` |
