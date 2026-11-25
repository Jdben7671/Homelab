#!/usr/bin/env bash
# nextcloud-nfs-guard.sh: self-healing check for the Nextcloud NFS data mount (K3s).
#
# Runs on raspi1 as root (via scripts/systemd/nextcloud-nfs-guard.timer).
#
# Problem it solves (INC-001 / INC-002):
#   1. TrueNAS reboots -> the NFS share disappears or comes back late.
#   2. Even after the share is re-mounted on the host, an already-running
#      Nextcloud pod keeps seeing the *empty local directory* its hostPath
#      volume bound at start, and reports "Your data directory is invalid".
#
# What it does, in order:
#   a) Host mount missing      -> `mount` it (fstab entry), log, continue.
#   b) Host mount still broken -> log + exit 1 (do NOT restart Nextcloud onto an
#                                 empty directory).
#   c) Host OK but the pod can't see .ncdata -> rollout restart nextcloud + cron.
#   d) Everything OK           -> exit 0 silently.
set -euo pipefail

MOUNTPOINT="${MOUNTPOINT:-/mnt/nextcloud-data}"
NAMESPACE="${NAMESPACE:-nextcloud}"
read -r -a DEPLOYMENTS <<< "${DEPLOYMENTS:-nextcloud nextcloud-cron}"
read -r -a KUBECTL <<< "${KUBECTL:-k3s kubectl}"
WWW_UID=33   # www-data inside the Nextcloud image
TAG="nextcloud-nfs-guard"

log() { logger -t "$TAG" -- "$*"; echo "[$TAG] $*"; }
kc() { "${KUBECTL[@]}" -n "$NAMESPACE" "$@"; }

host_ok() {
  mountpoint -q "$MOUNTPOINT" &&
    # Test as uid 33: with root_squash, root gets "Permission denied" on NFS.
    timeout 10 sudo -u "#$WWW_UID" test -f "$MOUNTPOINT/.ncdata"
}

pod_ok() {
  timeout 20 "${KUBECTL[@]}" -n "$NAMESPACE" exec deploy/nextcloud -- \
    su -s /bin/sh www-data -c 'test -f /var/www/html/data/.ncdata'
}

# a) / b): host side
if ! host_ok; then
  log "NFS data share not healthy at $MOUNTPOINT, attempting mount"
  mount "$MOUNTPOINT" 2>&1 | logger -t "$TAG" || true
  sleep 3
  if ! host_ok; then
    log "still not mounted / .ncdata missing; is TrueNAS up and the NFS share enabled? Not touching pods."
    exit 1
  fi
  log "NFS share mounted"
fi

# c): pod side
ready="$(kc get deploy nextcloud -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
if [[ -z "$ready" || "$ready" == "0" ]]; then
  log "nextcloud deployment has no ready pod; leaving it to Kubernetes"
  exit 0
fi

if ! pod_ok; then
  log "pod does not see .ncdata (stale hostPath bind), restarting: ${DEPLOYMENTS[*]}"
  for d in "${DEPLOYMENTS[@]}"; do kc rollout restart "deployment/$d" >/dev/null; done
  kc rollout status deployment/nextcloud --timeout=180s >/dev/null || true
  if pod_ok; then
    log "recovered: Nextcloud sees its data directory again"
  else
    log "restart did not help; manual investigation needed (see runbooks/)"
    exit 1
  fi
fi
