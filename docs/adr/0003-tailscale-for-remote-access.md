# ADR-0003: Tailscale for remote access instead of a public reverse proxy

**Status:** Accepted. Supersedes the Nginx Proxy Manager setup (`stacks/_retired/nginx-proxy-manager`).

## Context

Services like Nextcloud and Home Assistant are useful away from home. The classic approach is port-forwarding 80/443 to a reverse proxy (Nginx Proxy Manager was installed for this), which exposes every proxied app to the whole internet and requires keeping each app patched against internet-facing attacks.

## Decision

Install **Tailscale on the Pi host** (not in a container) and reach services over the tailnet. Nginx Proxy Manager is stopped and kept only as a reference config.

## Consequences

- ➕ Zero open inbound ports. The attack surface is Tailscale's authenticated WireGuard endpoint, not each web app.
- ➕ Works behind CGNAT, no dynamic DNS needed.
- ➕ Running on the host means remote access survives Docker restarts. You can SSH in to fix a broken container stack.
- ➖ Every client device needs the Tailscale app. Not suitable for sharing a Nextcloud link with someone outside the tailnet (Tailscale Funnel could cover that case).
- ➖ Services are plain HTTP inside the tunnel. `tailscale cert` can add HTTPS later.
