#!/usr/bin/env bash
# pve-temp.sh - Read and display iDRAC temperatures in a human-readable way
#
# Usage:
#   pve-temp.sh              # show all temperature sensors
#   pve-temp.sh -w           # watch mode (refresh every 2s)
#
# Uses ipmitool against the iDRAC of the Dell PowerEdge host.

set -euo pipefail

IDRAC_IP="10.0.0.4"
IDRAC_USER="root"
IDRAC_PASS="calvin"

# ANSI colors
RED=$'\033[31m'; YELLOW=$'\033[33m'; GREEN=$'\033[32m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

ipmi() {
    ipmitool -I lanplus -H "$IDRAC_IP" -U "$IDRAC_USER" -P "$IDRAC_PASS" "$@"
}

color_for() {
    local temp=$1
    if (( temp >= 80 )); then  printf '%s' "$RED"
    elif (( temp >= 60 )); then printf '%s' "$YELLOW"
    else                       printf '%s' "$GREEN"
    fi
}

fetch_temps() {
    ipmi sensor list | awk -F'|' '
        {
            gsub(/^ +| +$/, "", $1)
            if ($1 == "Temp") {
                gsub(/^ +| +$/, "", $2)
                gsub(/^ +| +$/, "", $3); gsub(/^ +| +$/, "", $4)
                if ($2 ~ /[0-9]/) printf "%s|%s|%s|%s\n", "Temp", $2+0, $3, $4
            }
        }'
}

print_temps() {
    printf '%s%-30s %8s  %-12s  %s%s\n' "$BOLD" "Sensor" "Value" "Unit" "Status" "$RESET"
    printf '%s\n' "---------------------------------------------------------------"
    while IFS='|' read -r name val unit status; do
        [[ -z "$name" ]] && continue
        color="$(color_for "$val")"
        printf '%s%-30s %s%7.0f%s  %-12s  %s\n' "$RESET" "$name" "$color" "$val" "$RESET" "$unit" "$status"
    done < <(fetch_temps | sort -t'|' -k2,2nr)
}

case "${1:-}" in
    -w)
        clear
        while :; do
            tput cup 0 0
            printf '%s%s  %s  %s%s\n' "$BOLD" "iDRAC $IDRAC_IP" "$(date '+%H:%M:%S')" "(refresh 2s)" "$RESET"
            print_temps
            sleep 2
        done
        ;;
    "")
        print_temps
        ;;
    *)
        echo "Usage: $0 [-w]" >&2
        exit 1
        ;;
esac