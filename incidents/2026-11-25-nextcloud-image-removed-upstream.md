# INC-005: Nextcloud `ImagePullBackOff`: pinned image tag removed from Docker Hub

| | |
|---|---|
| **Date** | 2026-11-25 (during the [K3s migration](../docs/migration-casaos-to-k3s.md)) |
| **Severity** | SEV-2 (Nextcloud could not start on the new platform) |
| **Services affected** | Nextcloud, Nextcloud cron |
| **Status** | Resolved (workaround). Root fix open |

## Summary

On K3s, the `nextcloud` and `nextcloud-cron` pods failed with **`ImagePullBackOff`: pull access denied, repository does not exist or may require authorization**. The image `bigbeartechworld/big-bear-nextcloud-with-smbclient:35.0.1` had been **removed upstream**. The only remaining copy was in the local Docker cache on `raspi1`, stored by digest only (`ddaca2031622…`, the same digest pinned in this repo's compose file). It was recovered by re-tagging and importing it into K3s's containerd.

## Root cause

Two things combined:

1. **K3s doesn't share Docker's image store.** K3s runs its own containerd, so every image has to be pulled again (or imported) even if Docker already has it.
2. **The upstream tag was gone.** It was a community wrapper image from a third-party publisher, not the official `nextcloud` image, and the tag had been deleted. The pinned digest in this repo recorded *exactly* what was running, but a digest can't bring back a deleted image.

## Resolution

```bash
# The local image had no tag left, only its ID
sudo docker tag ddaca2031622 bigbeartechworld/big-bear-nextcloud-with-smbclient:35.0.1
sudo docker save bigbeartechworld/big-bear-nextcloud-with-smbclient:35.0.1 | sudo k3s ctr images import -

# imagePullPolicy: IfNotPresent in both Deployments, then:
sudo k3s kubectl rollout restart deployment/nextcloud deployment/nextcloud-cron -n nextcloud
```

## Why this still matters

The 2.96 GB image now exists **only on `raspi1`'s microSD card**, inside K3s's containerd store. If that card dies, if someone runs `k3s crictl rmi --prune`, or if the pod is scheduled on `raspi2`, Nextcloud can't start, and there's nowhere to pull the image from.

## Lessons

- **Pin and mirror.** A digest makes deployments reproducible only while the registry still has the image.
- Prefer **official images** for stateful core services. Third-party wrapper images can disappear.
- Migrating runtimes (Docker → containerd) is a good moment to check that *every* image can still be pulled from scratch.

## Action items

| # | Action | Type | Status |
|---|---|---|---|
| 1 | Keep an off-node copy: `k3s ctr images export` to the NAS, or push to a registry I control (e.g. a `registry:2` on TrueNAS, or GHCR) | mitigate | Open |
| 2 | Plan a move to the official `nextcloud` image (same major version, same `config.php`, data dir unchanged) | prevent | Open |
| 3 | Don't run `docker image prune -a` on `raspi1` until action 1 is done | prevent | Done (documented) |
| 4 | Pull-test every manifest image from a clean node (`raspi2`) | detect | Open |
