#!/usr/bin/env bash
# pve-fan-control.sh - Monitor iDRAC temperature and set Dell PowerEdge fan speed
#
# Reads the temperature from the iDRAC via ipmitool and adjusts the fan
# speed accordingly. Designed for Proxmox VE 8, usable standalone or via
# a systemd timer (see pve-fan-control.service / pve-fan-control.timer).
#
# Usage:
#   pve-fan-control.sh [run|status|auto]
#
#   run      - check temp, adjust fan, exit (default)
#   status   - print current temperature and fan speed
#   auto     - restore automatic thermal control
#
# See ../homelab/hardware.md for background on the raw IPMI commands.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (edit as needed)
# ---------------------------------------------------------------------------
IDRAC_IP="10.0.0.4"
IDRAC_USER="root"
IDRAC_PASS="calvin"

# Temperature -> fan speed (%) mapping, checked top-down (hottest first).
# Value is the hex byte used by `raw 0x30 0x30 0x02 0xff 0xXX`.
FAN_MAP=(
    "80:0x46"   # >80C   -> 70%  (0x46)
    "60:0x0f"   # >60C   -> 15%  (0x0f)
    "50:0x0a"   # >50C   -> 10%  (0x0a)
    "0:0x07"    # <=50C  -> 7%   (0x07)
)

# Sensor names to try, in order (case-sensitive as reported by iDRAC).
# State file storing the last applied fan hex so we only re-send on change.
STATE_FILE="${STATE_FILE:-/var/tmp/pve-fan-control.state}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
ipmi() {
    ipmitool -I lanplus -H "$IDRAC_IP" -U "$IDRAC_USER" -P "$IDRAC_PASS" "$@"
}

get_temp() {
    local name out temp max=0
    # Collect every CPU "Temp" sensor and return the maximum.
    while IFS= read -r temp; do
        if [[ "$temp" =~ ^-?[0-9]+$ ]] && (( temp > max )); then
            max=$temp
        fi
    done < <(ipmi sensor list 2>/dev/null | awk -F'|' '
        { gsub(/^ +| +$/, "", $1); gsub(/^ +| +$/, "", $2)
          if ($1 == "Temp" && $2 ~ /[0-9]/) print $2 + 0 }')
    if (( max > 0 )); then
        printf '%s' "$max"
        return 0
    fi
    return 1
}

fan_hex_for() {
    local temp=$1 limit hex
    for entry in "${FAN_MAP[@]}"; do
        limit="${entry%%:*}"
        hex="${entry##*:}"
        if (( temp > limit )); then
            printf '%s' "$hex"
            return 0
        fi
    done
}

apply_fan() {
    local hex=$1 current
    if [[ -f "$STATE_FILE" ]]; then
        current="$(cat "$STATE_FILE" 2>/dev/null || true)"
        if [[ "$current" == "$hex" ]]; then
            return 0
        fi
    fi
    ipmi raw 0x30 0x30 0x02 0xff "$hex"
    printf '%s' "$hex" > "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
cmd_run() {
    local temp hex
    if ! temp="$(get_temp)"; then
        echo "ERROR: could not read temperature from iDRAC" >&2
        return 1
    fi
    hex="$(fan_hex_for "$temp")"
    # Ensure manual mode is on before applying a speed.
    ipmi raw 0x30 0x30 0x01 0x00
    apply_fan "$hex"
    printf 'temp=%sC fan=%s%%\n' "$temp" "$(( 16#${hex#0x} ))"
}

cmd_status() {
    local temp hex
    if temp="$(get_temp)" 2>/dev/null; then
        printf 'temp: %sC\n' "$temp"
    else
        printf 'temp: <unreadable>\n'
    fi
    hex="$(cat "$STATE_FILE" 2>/dev/null || printf 'unknown')"
    printf 'fan hex: %s\n' "$hex"
}

cmd_auto() {
    ipmi raw 0x30 0x30 0x01 0x01
    rm -f "$STATE_FILE"
    printf 'Automatic thermal control restored.\n'
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
case "${1:-run}" in
    run)   cmd_run ;;
    status) cmd_status ;;
    auto)  cmd_auto ;;
    *) echo "Usage: $0 [run|status|auto]" >&2; exit 1 ;;
esac