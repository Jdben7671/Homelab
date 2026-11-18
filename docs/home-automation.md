# Home automation

Home Assistant (container, `ghcr.io/home-assistant/home-assistant:stable`, currently 2026.11.0) runs on `raspi1` and ties together:

| Integration | What it gives |
|---|---|
| **Philips Hue** | Control of every Hue light through the Hue bridge, scenes, automations |
| **Amazon Alexa** | Voice control of HA entities |
| **Apple TV** | Media state and control, usable as an automation trigger (e.g. dim the lights when playback starts) |

## Container design decisions

- **`network_mode: host`**: Hue and Apple TV are found through mDNS/SSDP multicast discovery, and multicast does not cross Docker's bridge NAT. With host networking HA sees the LAN exactly like a native install.
- **`privileged: true`**: grants access to host devices (Bluetooth/USB radios). Convenient, but it is the broadest permission in the lab, so it is listed in [security.md](security.md) with a plan to replace it with specific `devices:` entries.
- **Config on the Pi** (`/DATA/AppData/homeassistant/config`): HA's SQLite recorder database must not live on NFS.

## Why the container and not Home Assistant OS?

HA OS wants the whole machine. Running the container lets the same Pi also serve DNS, Nextcloud and monitoring. The cost is no Supervisor add-on store, which is fine because every "add-on" here is already its own container.
