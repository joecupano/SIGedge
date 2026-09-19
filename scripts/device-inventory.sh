#!/usr/bin/env bash
#
# scripts/device-inventory.sh
#
# The one place to answer "what SDR/RF hardware is attached, what already
# claims it, and is that claim actually live right now" -- combines what
# used to be two separate views (this script's own USB/config scan, plus
# scripts/service_toggle's `status` action) into one. Lists attached
# SDR/RF USB devices (RTL-SDR, HackRF, Ubertooth, RX-888) with their real
# USB serial numbers, side by side with:
#   - radiod's per-mission `serial =` line (scripts/cfg_ka9q-radio's
#     RTLSDR_SERIAL/HACKRF_SERIAL/RX888_SERIAL) plus each mission's live
#     systemd enabled/active state, cross-matched against what's actually
#     plugged in right now
#   - OpenWebRX's live systemd enabled/active state (it's a single
#     service, not per-mission, and its own device selection lives in
#     /var/lib/openwebrx/settings.json via its web UI, not a SIGedge
#     config -- out of scope to parse here)
#   - Kismet's rtl433-sn-<serial> / ubertooth<N> source= lines in
#     kismet_site.conf, cross-matched the same way where a serial is given
# and flags the one conflict that actually matters: a radiod mission and
# OpenWebRX both active at once, which means two owners for what may be
# the same physical SDR (see README.md's device-ownership section --
# "an SDR must have exactly one active owner").
#
# Read-only and non-invasive throughout: `lsusb -v` reads standard USB
# descriptors without claiming the device, and `systemctl is-enabled` /
# `is-active` are plain state queries -- none of this needs or takes sudo,
# and none of it opens a device the way rtl_eeprom/rtl_test/hackrf_info
# would (which could fail or, worse, contend with a real owner).
#
# This tool answers "what's attached, what claims it, and is that claim
# live" -- it does not resolve conflicts or switch anything itself. Use
# scripts/service_toggle to actually switch a device between radiod and
# OpenWebRX; see README.md's device-ownership section for the underlying
# one-owner-per-device policy.
#
# Usage: ./scripts/device-inventory.sh
#   No arguments, no sudo required.

set -uo pipefail

KA9Q_CONFIG_DIR="${KA9Q_CONFIG_DIR:-/etc/radio}"
OPENWEBRX_UNIT="openwebrx.service"

# Known VID:PID pairs. RX-888 has two: 00f1 once firmware is loaded,
# 00f3 while still sitting in Cypress FX3 DFU/bootloader mode (see
# README.md/KA9Q-DEPLOYMENT.md's DFU-mode gotcha) -- shown as a distinct,
# flagged state since a device stuck there needs a firmware upload
# before radiod/rx888_stream can use it, not a serial pin.
declare -A DEVICE_LABELS=(
    ["0bda:2838"]="RTL-SDR (RTL2838)"
    ["0bda:2832"]="RTL-SDR (RTL2832U)"
    ["1d50:6089"]="HackRF One"
    ["1d50:6002"]="Ubertooth One"
    ["04b4:00f1"]="RX-888 MkII (firmware loaded)"
    ["04b4:00f3"]="RX-888 MkII (DFU mode -- needs firmware upload)"
)

# Groups the VID:PID table above into the coarser "kind" that radiod's
# `hardware =` value and Kismet's source= prefix both use, so an attached
# unit can be cross-matched against a claimed serial regardless of which
# exact VID:PID (loaded vs DFU, RTL2838 vs RTL2832U) it currently shows.
declare -A DEVICE_KIND=(
    ["0bda:2838"]="rtlsdr"
    ["0bda:2832"]="rtlsdr"
    ["1d50:6089"]="hackrf"
    ["1d50:6002"]="ubertooth"
    ["04b4:00f1"]="rx888"
    ["04b4:00f3"]="rx888"
)

# Populated by the USB scan below, then consulted by the claims section:
# how many units of each kind are attached, and which serials (of the
# ones that expose one) were seen.
declare -A ATTACHED_COUNT=()
declare -A ATTACHED_SERIALS=()

serial_attached()
{
    local kind="$1" serial="$2"
    [[ -z "$serial" ]] && return 1
    local list=" ${ATTACHED_SERIALS[$kind]:-} "
    [[ "$list" == *" $serial "* ]]
}

# enabled/active state of a systemd unit -- never sudo, matches
# scripts/service_toggle's own is-enabled/is-active convention.
unit_state()
{
    local unit="$1"
    if ! systemctl cat "$unit" >/dev/null 2>&1; then
        echo "not installed"
        return
    fi
    local enabled active
    enabled="$(systemctl is-enabled "$unit" 2>/dev/null)"
    [[ -z "$enabled" ]] && enabled="disabled"
    active="$(systemctl is-active "$unit" 2>/dev/null)"
    [[ -z "$active" ]] && active="inactive"
    echo "enabled=$enabled active=$active"
}

unit_is_active()
{
    systemctl is-active --quiet "$1" 2>/dev/null
}

echo "== Attached SDR/RF devices =="
echo

FOUND_ANY=0
for vidpid in "${!DEVICE_LABELS[@]}"; do
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        FOUND_ANY=1
        busdev="$(echo "$line" | sed -n 's/^Bus \([0-9]*\) Device \([0-9]*\):.*/\1:\2/p')"
        label="${DEVICE_LABELS[$vidpid]}"

        serial="$(lsusb -v -s "$busdev" 2>/dev/null \
            | awk '/iSerial/ {for (i=3; i<=NF; i++) printf "%s ", $i; print ""}' \
            | sed 's/[[:space:]]*$//')"

        echo "  [$vidpid] $label"
        echo "    USB:    Bus $busdev"
        echo "    Serial: ${serial:-<none exposed>}"
        echo

        kind="${DEVICE_KIND[$vidpid]:-}"
        if [[ -n "$kind" ]]; then
            ATTACHED_COUNT[$kind]=$(( ${ATTACHED_COUNT[$kind]:-0} + 1 ))
            [[ -n "$serial" ]] && ATTACHED_SERIALS[$kind]="${ATTACHED_SERIALS[$kind]:-} $serial"
        fi
    done < <(lsusb -d "$vidpid" 2>/dev/null)
done

if [[ "$FOUND_ANY" -eq 0 ]]; then
    echo "  (none of the known SDR/RF device types found attached)"
    echo
fi

echo "== Existing SIGedge claims =="
echo

echo "-- radiod missions (${KA9Q_CONFIG_DIR}/radiod@*.conf) --"
shopt -s nullglob
RADIOD_CONFS=("${KA9Q_CONFIG_DIR}"/radiod@*.conf)
shopt -u nullglob

ANY_RADIOD_ACTIVE=0

if [[ ${#RADIOD_CONFS[@]} -eq 0 ]]; then
    echo "  (none found)"
else
    for conf in "${RADIOD_CONFS[@]}"; do
        mission="$(basename "$conf")"
        mission="${mission#radiod@}"
        mission="${mission%.conf}"
        unit="radiod@${mission}.service"

        hw="$(grep -m1 -E '^\s*hardware\s*=' "$conf" 2>/dev/null | sed -E 's/.*=\s*//')"
        serial="$(grep -m1 -E '^\s*serial\s*=' "$conf" 2>/dev/null | sed -E 's/.*=\s*//')"
        kind="$(echo "${hw:-}" | tr '[:upper:]' '[:lower:]')"
        state="$(unit_state "$unit")"

        echo "  $(basename "$conf"): hardware=${hw:-?} serial=${serial:-<unpinned>} $state"

        unit_is_active "$unit" && ANY_RADIOD_ACTIVE=1

        if [[ -n "$serial" ]]; then
            if serial_attached "$kind" "$serial"; then
                echo "      -> serial $serial is currently attached"
            else
                echo "      -> serial $serial is NOT currently attached -- this mission will fail to open its device"
            fi
        else
            count="${ATTACHED_COUNT[$kind]:-0}"
            if [[ "$count" -gt 1 ]]; then
                echo "      -> unpinned with $count attached $kind device(s) -- auto-detect may grab the wrong one; pin by serial"
            elif [[ "$count" -eq 1 ]]; then
                echo "      -> unpinned; 1 attached $kind device will be used"
            else
                echo "      -> unpinned; no $kind device currently attached"
            fi
        fi
    done
fi
echo

echo "-- OpenWebRX ($OPENWEBRX_UNIT) --"
openwebrx_state="$(unit_state "$OPENWEBRX_UNIT")"
echo "  $openwebrx_state"
if [[ "$openwebrx_state" != "not installed" ]]; then
    echo "      -> device selection lives in /var/lib/openwebrx/settings.json (web UI), not shown here"
fi
OPENWEBRX_ACTIVE=0
unit_is_active "$OPENWEBRX_UNIT" && OPENWEBRX_ACTIVE=1
echo

if [[ "$ANY_RADIOD_ACTIVE" -eq 1 && "$OPENWEBRX_ACTIVE" -eq 1 ]]; then
    echo "  ** CONFLICT: at least one radiod@ mission AND OpenWebRX are both active at once. **"
    echo "  ** An SDR must have exactly one active owner -- pick a side with                  **"
    echo "  ** 'scripts/service_toggle ka9q-radio|openwebrx|off'.                              **"
    echo
fi

echo "-- Kismet (/usr/local/etc/kismet_site.conf) --"
if [[ -f /usr/local/etc/kismet_site.conf ]]; then
    sources="$(grep -E '^source=' /usr/local/etc/kismet_site.conf 2>/dev/null)"
    if [[ -z "$sources" ]]; then
        echo "  (no active source= lines)"
    else
        while IFS= read -r src; do
            [[ -z "$src" ]] && continue
            echo "  $src"
            if [[ "$src" =~ ^source=rtl433-sn-([^:]+) ]]; then
                serial="${BASH_REMATCH[1]}"
                if serial_attached "rtlsdr" "$serial"; then
                    echo "      -> serial $serial is currently attached"
                else
                    echo "      -> serial $serial is NOT currently attached -- this source will fail to open its device"
                fi
            elif [[ "$src" =~ ^source=ubertooth[0-9]+ ]]; then
                count="${ATTACHED_COUNT[ubertooth]:-0}"
                echo "      -> selects by index, not serial; $count Ubertooth device(s) currently attached"
            fi
        done <<< "$sources"
    fi
else
    echo "  (kismet_site.conf not installed on this host)"
fi
echo

echo "== Reading this =="
echo "An 'unpinned' radiod mission or a Kismet source with no serial/index constraint"
echo "will grab whichever matching device it finds first."
echo ""
echo "This is fine with exactly ONE unit of that device type attached but a real collision"
echo "risk with more than one of that device attached."
echo ""
echo "Pin by serial"
echo "(radiod: RTLSDR_SERIAL= to scripts/cfg_ka9q-radio; Kismet: rtl433-sn-<serial> in kismet_site.conf)"
echo "whenever two always-on consumers need the same device type."
echo ""
echo "enabled=/active= reflects live systemd state, not just what's configured -- a mission's"
echo "radiod@<mission>.conf can exist and still be disabled/inactive. Use scripts/service_toggle"
echo "to switch a device between radiod and OpenWebRX; it always stops+disables the side being"
echo "left before starting the other."
echo ""
echo "See README.md's device-ownership section and this script's own header comment."
