# INC-003: Home Assistant Alexa integration dropping every ~30 minutes (router WAN DHCP renewal)

| | |
|---|---|
| **Date** | 2026-11-24 |
| **Severity** | SEV-3 (intermittent loss of Alexa control) |
| **Services affected** | Home Assistant `alexa_devices` integration (`aioamazondevices`), and potentially any outbound connection |
| **Status** | Resolved |

## Summary

Home Assistant's Alexa integration disconnected roughly every 30 minutes. It looked like an Amazon authentication or token-expiry problem, but the cause was the **main router renewing its WAN DHCP lease** from the ISP gateway (double NAT), which briefly broke outbound routing for the whole LAN. Giving the router a static WAN address stopped it.

## Environment

| | |
|---|---|
| HA host | `raspi1` (Raspberry Pi 5), Home Assistant in Docker, `network_mode: host` *(before the K3s migration)* |
| Main router | TP-Link Archer BE550, `192.168.1.1` |
| ISP gateway | CH7465ONE, `192.168.0.1`. **Double NAT**, bridge mode not available in its UI |

## Symptoms

HA logs showed `OSError 113` (`EHOSTUNREACH`, *No route to host*) and `OSError 101` (`ENETUNREACH`, *Network unreachable*) at about 30-minute intervals.

## Diagnosis: working outward from the container

Each layer was ruled out before moving one hop further out:

| Layer | Check | Result |
|---|---|---|
| Physical link | `dmesg -T \| grep -iE "link\|eth0\|wlan0\|carrier\|reset"` | No interface drops |
| IPv6 | `docker exec homeassistant curl -6 -I https://api.amazon.com` vs `curl -4` | No AAAA records; IPv4 fine. Not an IPv6 fallback issue |
| Container networking | `docker inspect -f '{{.HostConfig.NetworkMode}}' homeassistant` | `host`. No Docker NAT in the path |
| Host DHCP | `journalctl -u NetworkManager -u dhcpcd` | No lease drops or resets on `raspi1` |
| **Router** | Archer BE550 → *Advanced → System → System Log* | **DHCPC (WAN) renewal events at the exact timestamps of the HA errors** |

## Root cause

With double NAT, the Archer gets its WAN address by DHCP from the ISP gateway on `192.168.0.0/24`. Each lease renewal briefly took the WAN interface down and re-applied routes. Long-lived outbound connections (like the Alexa integration's) failed with *no route to host* and had to reconnect.

## Resolution

Set the Archer BE550's WAN connection from **dynamic IP to static IP** on the gateway's subnet, so no lease renewal happens any more.

## Lessons

- The error code said what was wrong: `EHOSTUNREACH` / `ENETUNREACH` point at **routing**, not authentication. Reading errno values first saves time.
- **Correlating timestamps across devices** found the cause: the HA log and the router log lined up to the minute.
- Rule out layers in order, nearest first: link → IP version → container → host → router.

## Action items

| # | Action | Type | Status |
|---|---|---|---|
| 1 | Static WAN IP on the Archer BE550 | prevent | Done |
| 2 | Reserve that IP on the ISP gateway (or shrink its DHCP pool) so nothing else can take it | prevent | Open |
| 3 | Revisit bridge mode on the CH7465ONE (often only the ISP can enable it) to remove double NAT | prevent | Open |
