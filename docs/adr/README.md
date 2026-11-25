# Architecture Decision Records

Short records of *why* the lab is built the way it is, in the [Michael Nygard format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-casaos-on-raspberry-pi.md) | Run all apps as Docker containers managed by CasaOS on a Raspberry Pi | Superseded by 0004 |
| [0002](0002-nextcloud-data-on-truenas-nfs.md) | Store Nextcloud user data on TrueNAS ZFS, mounted over NFS | Accepted |
| [0003](0003-tailscale-for-remote-access.md) | Tailscale for remote access instead of a public reverse proxy | Accepted (supersedes NPM) |
| [0004](0004-migrate-to-k3s.md) | Migrate from CasaOS/Docker Compose to a two-node K3s cluster | Accepted (supersedes 0001) |
