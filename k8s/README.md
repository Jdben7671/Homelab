# K3s manifests

The live manifests from `raspi1` (`~/k3s/`), sanitized: every password and key is read from a Kubernetes Secret instead of being written inline. Everything else is exactly what's deployed.

| File | Workload(s) | Node | Access |
|---|---|---|---|
| [`pihole-primary.yaml`](pihole-primary.yaml) | `pihole-primary` | raspi1 | DNS `:53`, web `:8080` |
| [`pihole-backup.yaml`](pihole-backup.yaml) | `pihole-backup` | raspi2 | DNS `:53`, web `:8080` |
| [`homeassistant-primary.yaml`](homeassistant-primary.yaml) | `homeassistant-primary` | raspi1 | `:8123` |
| [`homeassistant-standby.yaml`](homeassistant-standby.yaml) | `homeassistant-backup` (`replicas: 0`) | raspi2 | `:8123` when failed over |
| [`esphome.yaml`](esphome.yaml) | `esphome` | raspi1 | `:6052` |
| [`nextcloud.yaml`](nextcloud.yaml) | namespace `nextcloud`: `nextcloud`, `nextcloud-cron`, `db-nextcloud`, `redis-nextcloud` | raspi1 | `:7580` |
| [`dozzle.yaml`](dozzle.yaml) | `dozzle` + ServiceAccount + ClusterRole | raspi1 | `:8888` |
| [`homarr.yaml`](homarr.yaml) | `homarr` | raspi1 | `:7575` |
| [`beszel.yaml`](beszel.yaml) | `beszel` | raspi1 | `:8090` |
| [`n8n.yaml`](n8n.yaml) | `n8n` | raspi1 | `:5678` |
| [`secrets.example.yaml`](secrets.example.yaml) | Secret templates | | |

## Patterns used

- **`nodeSelector: kubernetes.io/hostname`** on every workload. Storage is `hostPath`, so each pod has to run where its data is.
- **`hostNetwork: true`** + `dnsPolicy: ClusterFirstWithHostNet` for LAN-facing apps (DNS, mDNS/SSDP discovery, stable IP:port).
- **`strategy: Recreate`** for anything with state, so two pods never touch the same data directory during a rollout.
- **ClusterIP Services named after the old Docker hostnames** (`db-nextcloud`, `redis-nextcloud`).
- **Least privilege where possible:** Home Assistant gets `NET_ADMIN`/`NET_RAW` instead of `privileged`, and Dozzle gets a read-only ClusterRole instead of the Docker socket.

## Deploying

```bash
# 1. Secrets first (see secrets.example.yaml for the exact commands)
# 2. Pull-test images that come from a registry (INC-005)
sudo k3s crictl pull pihole/pihole:2026.07.2
# 3. Apply
sudo k3s kubectl apply -f k8s/
sudo k3s kubectl get pods -A -o wide
```

`kubectl apply -f k8s/` also applies `secrets.example.yaml`, which would overwrite real Secrets with `CHANGE_ME`. Apply files individually, or move the example out of the way first.

CI validates every manifest against the Kubernetes API schemas with [kubeconform](https://github.com/yannh/kubeconform).
