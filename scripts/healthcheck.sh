#!/usr/bin/env bash
# healthcheck.sh: one-shot health report for the whole homelab.
#
# Run from any machine on the LAN (or over Tailscale):
#   ./scripts/healthcheck.sh            # human-readable table
#   ./scripts/healthcheck.sh --quiet    # only failures; exit code = number of failures
#
# Checks HTTP endpoints of every service, DNS resolution through Pi-hole, and
# Nextcloud's status.php (which is the first thing to break when the NFS data
# share is missing, see incidents/2026-11-17-nextcloud-zfs-mountpoint.md).
set -uo pipefail

PI_HOST="${PI_HOST:-192.168.1.57}"
NAS_HOST="${NAS_HOST:-192.168.1.226}"
TIMEOUT="${TIMEOUT:-5}"
QUIET=false
[[ "${1:-}" == "--quiet" ]] && QUIET=true

failures=0

report() { # name status detail
  local name="$1" status="$2" detail="$3"
  if [[ "$status" == "FAIL" ]]; then failures=$((failures + 1)); fi
  if [[ "$QUIET" == false || "$status" != "OK" ]]; then
    printf '%-16s %-5s %s\n' "$name" "$status" "$detail"
  fi
}

check_http() { # name url [expected-substring]
  local name="$1" url="$2" expect="${3:-}" body code
  body="$(curl --noproxy "*" -fsS -m "$TIMEOUT" -w '\n%{http_code}' "$url" 2>/dev/null)" || {
    report "$name" "FAIL" "$url unreachable"
    return
  }
  code="${body##*$'\n'}"
  body="${body%$'\n'*}"
  if [[ -n "$expect" && "$body" != *"$expect"* ]]; then
    report "$name" "FAIL" "$url returned $code but not '$expect'"
  else
    report "$name" "OK" "$url ($code)"
  fi
}

check_dns() {
  if ! command -v dig >/dev/null 2>&1; then
    report "pihole-dns" "SKIP" "dig not installed"
    return
  fi
  if dig +short +time="$TIMEOUT" +tries=1 @"$PI_HOST" github.com | grep -qE '^[0-9.]+$'; then
    report "pihole-dns" "OK" "@$PI_HOST resolves github.com"
  else
    report "pihole-dns" "FAIL" "@$PI_HOST did not resolve github.com"
  fi
}

[[ "$QUIET" == false ]] && printf '%-16s %-5s %s\n' "SERVICE" "STATE" "DETAIL"

check_http "nextcloud"      "http://$PI_HOST:7580/status.php" '"maintenance":false'
check_http "homarr"         "http://$PI_HOST:7575/"
check_http "pihole-web"     "http://$PI_HOST:8080/admin/"
check_dns
check_http "homeassistant"  "http://$PI_HOST:8123/"
check_http "beszel"         "http://$PI_HOST:8090/"
check_http "dozzle"         "http://$PI_HOST:8888/"
check_http "composetoolbox" "http://$PI_HOST:3002/"
check_http "truenas"        "http://$NAS_HOST/"

exit "$failures"
