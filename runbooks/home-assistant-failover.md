# Runbook: fail Home Assistant over to `raspi2` (and back)

Home Assistant runs on `raspi1` (`homeassistant-primary`). A **cold standby** (`homeassistant-backup`) sits on `raspi2` at `replicas: 0` with a config copy that `raspi1` rsyncs every night at 02:00.

**Never run both at once.** Two instances would fire every automation twice and fight over the Hue bridge.

## When to fail over
`raspi1` is down or unrecoverable for a while (SD card failure, hardware fault). For a quick reboot, just wait.

## Failover

```bash
# 1. Make sure the primary is really stopped (if the API on raspi1 still answers)
sudo k3s kubectl scale deployment/homeassistant-primary --replicas=0

# 2. Start the standby on raspi2
sudo k3s kubectl scale deployment/homeassistant-backup --replicas=1
sudo k3s kubectl get pods -o wide | grep homeassistant
```

Open `http://192.168.1.126:8123`. The config is from the last 02:00 sync. Recorder history (`home-assistant_v2.db`) is not replicated, so graphs start empty.

> **Caveat:** the K3s control plane runs on `raspi1`. If `raspi1` is completely dead, `kubectl` doesn't work. In that case run HA on `raspi2` directly as a stopgap:
> ```bash
> sudo docker run -d --name ha-emergency --network host --restart unless-stopped \
>   -v /opt/homeassistant-k3s/config:/config ghcr.io/home-assistant/home-assistant:stable
> ```
> (or with `nerdctl`/`ctr` if Docker isn't installed on raspi2.)

## Failback

```bash
# 1. Stop the standby
sudo k3s kubectl scale deployment/homeassistant-backup --replicas=0

# 2. Copy back any config changes made while on the standby (run on raspi1, as root)
sudo rsync -az beni@192.168.1.126:/opt/homeassistant-k3s/config/ /DATA/AppData/homeassistant/config/

# 3. Start the primary
sudo k3s kubectl scale deployment/homeassistant-primary --replicas=1
```

## Checks

- Replication is running: `sudo tail /var/log/ha-sync.log` on `raspi1` (empty = last run OK) and `ls -la /opt/homeassistant-k3s/config/.storage` on `raspi2` (recent timestamps).
- A replica is **not** a backup: `rsync --delete` would mirror a deletion. See [INC-004](../incidents/2026-11-25-casaos-uninstall-deleted-ha-config.md).
