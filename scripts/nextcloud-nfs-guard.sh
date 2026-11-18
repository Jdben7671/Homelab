#!/usr/bin/env bash
# nextcloud-nfs-guard.sh: self-healing check for the Nextcloud NFS data mount.
#
# Runs on raspi1 as root (via scripts/systemd/nextcloud-nfs-guard.timer).
#
# Problem it solves (INC-001 / INC-002):
#   1. TrueNAS reboots -> the NFS share disappears or comes back late.
#   2. Even after the share is re-mounted on the host, an already-running
#      Nextcloud container keeps seeing the *empty local directory* it was started
#      with, and reports "Your data directory is invalid".
#
# What it does, in order:
#   a) Host mount missing      -> `mount` it (fstab entry), log, continue.
#   b) Host mount still broken -> log + exit 1 (do NOT restart Nextcloud onto an
#                                 empty directory).
#   c) Host OK but container can't see .ncdata -> restart Nextcloud + cron.
#   d) Everything OK           -> exit 0 silently.
set -euo pipefail

MOUNTPOINT="${MOUNTPOINT:-/mnt/nextcloud-data}"
read -r -a CONTAINERS <<< "${CONTAINERS:-nextcloud big-bear-nextcloud-cron-1}"
WWW_UID=33   # www-data inside the Nextcloud image
TAG="nextcloud-nfs-guard"

log() { logger -t "$TAG" -- "$*"; echo "[$TAG] $*"; }

host_ok() {
  mountpoint -q "$MOUNTPOINT" &&
    # Test as uid 33: with root_squash, root gets "Permission denied" on NFS.
    timeout 10 sudo -u "#$WWW_UID" test -f "$MOUNTPOINT/.ncdata"
}

container_ok() {
  timeout 15 docker exec -u "$WWW_UID" nextcloud test -f /var/www/html/data/.ncdata
}

# a) / b): host side
if ! host_ok; then
  log "NFS data share not healthy at $MOUNTPOINT, attempting mount"
  mount "$MOUNTPOINT" 2>&1 | logger -t "$TAG" || true
  sleep 3
  if ! host_ok; then
    log "still not mounted / .ncdata missing; is TrueNAS up and the NFS share enabled? Not touching containers."
    exit 1
  fi
  log "NFS share mounted"
fi

# c): container side
if ! docker inspect -f '{{.State.Running}}' nextcloud 2>/dev/null | grep -q true; then
  log "nextcloud container not running; leaving it to Docker's restart policy"
  exit 0
fi

if ! container_ok; then
  log "container does not see .ncdata (stale bind mount), restarting: ${CONTAINERS[*]}"
  docker restart "${CONTAINERS[@]}" >/dev/null
  sleep 10
  if container_ok; then
    log "recovered: Nextcloud sees its data directory again"
  else
    log "restart did not help; manual investigation needed (see runbooks/)"
    exit 1
  fi
fi
