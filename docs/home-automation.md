# Home automation

Home Assistant (`ghcr.io/home-assistant/home-assistant:stable`) runs as the `homeassistant-primary` Deployment on `raspi1`, with a **cold standby on `raspi2`** ([failover runbook](../runbooks/home-assistant-failover.md)). It ties together:

| Integration | What it gives |
|---|---|
| **Philips Hue** | Control of every Hue light through the Hue bridge, scenes, automations |
| **Amazon Alexa** | Voice control of HA entities |
| **Apple TV** | Media state and control, usable as an automation trigger (e.g. dim the lights when playback starts) |
| **Bluetooth (on-board `hci0`)** | Passive BLE scanning for Bluetooth sensors |
| **ESPHome** | Custom ESP32 devices, built and flashed over USB from the `esphome` pod (`:6052`) |

## Kubernetes design decisions

- **`hostNetwork: true`**: Hue and Apple TV are found through mDNS/SSDP multicast, which doesn't cross the pod network. With host networking HA sees the LAN like a native install.
- **Capabilities, not `privileged`**: under Docker HA ran `privileged`. On K3s it gets only **`NET_ADMIN` + `NET_RAW`** plus a `/run/dbus` mount, which is exactly what BlueZ needs to manage `hci0`. Without them HA reported *"Bluetooth adapter hci0 is operating in degraded mode"*. A smaller blast radius, same functionality.
- **`strategy: Recreate`**: never two HA pods against the same config, even during an update.
- **Standby at `replicas: 0`**: the `raspi2` copy uses no resources and can't double-fire automations. Config is rsynced nightly (recorder DB and logs excluded).
- **Config on local disk** (`/DATA/AppData/homeassistant/config`): HA's SQLite recorder must not live on NFS.

## ESPHome

`esphome/esphome:2026.10` on `raspi1` (config in `/DATA/AppData/esphome/config`), `hostNetwork` (for OTA updates and mDNS) and `privileged` with a `hostPath` for `/dev/ttyUSB0` to flash ESP32 boards over USB. The device volume has no `type: CharDevice` check, so the pod starts even when no board is plugged in. Its `.esphome` build cache is several GB: exclude it from backups (see the [migration notes](migration-casaos-to-k3s.md#problems-hit-along-the-way)).

## Why not Home Assistant OS?

HA OS wants the whole machine. Running it as a workload lets the same Pi also serve DNS, Nextcloud and monitoring. The cost is no Supervisor add-on store, which is fine because every "add-on" here is already its own workload.
