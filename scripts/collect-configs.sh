#!/usr/bin/env bash
# collect-configs.sh: pull the live CasaOS app definitions + host facts from the Pi
# so they can be diffed against legacy/casaos-stacks/ in this repo (pre-K3s layout).
#
# Run on your workstation:
#   ./scripts/collect-configs.sh [user@host] [output-dir]
#
# The archive contains real secrets (compose env vars, `docker inspect` output).
# It is written OUTSIDE the repo by default, and *.tgz / export/ are git-ignored.
set -euo pipefail

TARGET="${1:-benipi@192.168.1.57}"
OUT="${2:-$HOME/homelab-export}"
mkdir -p "$OUT"

# -t: sudo needs a TTY for the password prompt.
# shellcheck disable=SC2016  # $(...) must expand on the remote side, not locally
ssh -t "$TARGET" 'sudo bash -c "
  set -e
  rm -rf /tmp/hl && mkdir -p /tmp/hl
  cp -r /var/lib/casaos/apps /tmp/hl/apps
  docker ps -a > /tmp/hl/docker-ps.txt
  docker inspect \$(docker ps -aq) > /tmp/hl/inspect.json
  docker network ls > /tmp/hl/networks.txt
  cp /etc/fstab /etc/os-release /tmp/hl/
  df -h > /tmp/hl/df.txt
  tar czf /tmp/hl.tgz -C /tmp hl && chown \$SUDO_USER /tmp/hl.tgz
  rm -rf /tmp/hl
"'
scp "$TARGET:/tmp/hl.tgz" "$OUT/hl-$(date +%F).tgz"
ssh "$TARGET" 'rm -f /tmp/hl.tgz'
echo "Saved to $OUT/hl-$(date +%F).tgz (contains secrets, do not commit)"
