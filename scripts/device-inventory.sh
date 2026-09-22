#!/usr/bin/env bash
#
# scripts/device-inventory.sh
#
# The one place to answer "what SDR/RF hardware is attached, what already
# claims it, and is that claim actually live right now". Lists attached
# SDR/RF USB devices (RTL-SDR, HackRF, RX-888) with their real USB serial
# numbers, side by side with:
#   - radiod's per-mission `serial =` line (scripts/cfg_ka9q-radio's
#     RTLSDR_SERIAL/HACKRF_SERIAL/RX888_SERIAL) plus each mission's live
#     systemd enabled/active state, cross-matched against what's actually
#     plugged in right now
#   - OpenWebRX's live systemd enabled/active state (it's a single
#     service, not per-mission, and its own device selection lives in
#     /var/lib/openwebrx/settings.json via its web UI, not a SIGedge
#     config -- out of scope to parse here)
#   - RTL-TCP server's RTLTCP_SERIAL override (see config/rtltcp.service),
#     cross-matched the same way
# and flags the one conflict that can be confirmed: a radiod mission and
# OpenWebRX both active at once, which means two owners for what may be
# the same physical SDR (see README.md's device-ownership section --
# "an SDR must have exactly one active owner").
#
# SDRangel server and SoapySDR Server are reported only as "active or
# not" -- neither has a SIGedge-visible, per-device serial pin today
# (SDRangel server only accepts device config post-boot via its own REST
# API; SoapySDR Server has no server-side device filter at all, upstream,
# and always serves every Soapy-visible device on the host). Don't read
# either as inactive-therefore-free: it only means this script found no
# *evidence* of a claim, not that none exists.
#
# Read-only and non-invasive throughout: `lsusb -v` reads standard USB
# descriptors without claiming the device, and `systemctl is-enabled` /
# `is-active` are plain state queries -- none of this needs or takes sudo,
# and none of it opens a device the way rtl_eeprom/rtl_test/hackrf_info
# would (which could fail or, worse, contend with a real owner).
#
# This tool answers "what's attached, what claims it, and is that claim
# live" -- it does not resolve conflicts or assign/switch anything itself.
# Use scripts/service_toggle to actually switch a device between radiod
# and OpenWebRX; see README.md's device-ownership section for the
# underlying one-owner-per-device policy.
#
# Usage: ./scripts/device-inventory.sh [--detail|--json]
#   No sudo required either way.
#   (no args) Concise default: one line per attached SDR -- which service
#            (if any) it's pinned to by serial, and whether that service
#            is enabled. This is the quick "what's plugged in, who owns
#            it" answer; see --detail for everything this script knows.
#   --detail Full diagnostic output: every claim source (radiod per
#            mission, OpenWebRX, RTL-TCP, the unverified SDRangel/SoapySDR
#            servers), live enabled/active state, unpinned-device
#            warnings, and the conflict check. This was the only, default
#            output before --detail existed.
#   --json   Emit the detailed data as structured JSON instead of text,
#            for other tooling to consume.

set -uo pipefail

JSON_OUT=0
DETAIL_OUT=0
case "${1:-}" in
    --json ) JSON_OUT=1 ;;
    --detail ) DETAIL_OUT=1 ;;
    -h|--help )
        echo "Usage: $0 [--detail|--json]"
        exit 0
        ;;
    "" ) ;;
    * )
        echo "Unrecognized argument: $1" >&2
        echo "Usage: $0 [--detail|--json]" >&2
        exit 1
        ;;
esac

KA9Q_CONFIG_DIR="${KA9Q_CONFIG_DIR:-/etc/radio}"
OPENWEBRX_UNIT="openwebrx.service"
SDRANGELSRV_UNIT="sdrangelsrv.service"
SOAPYSDRSRV_UNIT="soapysdrsrv.service"
RTLTCP_UNIT="rtltcp.service"

# RTL-TCP server's device pin, if any -- see config/rtltcp.service's
# EnvironmentFile=.
RTLTCP_ENV_FILE="/etc/default/rtltcp"

# Known VID:PID pairs. RX-888 has two: 00f1 once firmware is loaded,
# 00f3 while still sitting in Cypress FX3 DFU/bootloader mode (see
# README.md/KA9Q-DEPLOYMENT.md's DFU-mode gotcha) -- shown as a distinct,
# flagged state since a device stuck there needs a firmware upload
# before radiod/rx888_stream can use it, not a serial pin.
declare -A DEVICE_LABELS=(
    ["0bda:2838"]="RTL-SDR (RTL2838)"
    ["0bda:2832"]="RTL-SDR (RTL2832U)"
    ["1d50:6089"]="HackRF One"
    ["04b4:00f1"]="RX-888 MkII (firmware loaded)"
    ["04b4:00f3"]="RX-888 MkII (DFU mode -- needs firmware upload)"
)

# Groups the VID:PID table above into the coarser "kind" that radiod's
# `hardware =` value and RTL-TCP's serial claims both refer to, so an
# attached unit can be cross-matched against a claimed serial regardless
# of which exact VID:PID (loaded vs DFU, RTL2838 vs RTL2832U) it currently
# shows.
declare -A DEVICE_KIND=(
    ["0bda:2838"]="rtlsdr"
    ["0bda:2832"]="rtlsdr"
    ["1d50:6089"]="hackrf"
    ["04b4:00f1"]="rx888"
    ["04b4:00f3"]="rx888"
)


### ---------------------------------------------------------------------
### Helpers
### ---------------------------------------------------------------------

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

unit_installed() { systemctl cat "$1" >/dev/null 2>&1; }

unit_enabled_str()
{
    local unit="$1" e
    unit_installed "$unit" || { echo "not installed"; return; }
    e="$(systemctl is-enabled "$unit" 2>/dev/null)"
    echo "${e:-disabled}"
}

unit_active_str()
{
    local unit="$1" a
    unit_installed "$unit" || { echo "not installed"; return; }
    a="$(systemctl is-active "$unit" 2>/dev/null)"
    echo "${a:-inactive}"
}

unit_is_active() { systemctl is-active --quiet "$1" 2>/dev/null; }

# Human-readable "enabled=X active=Y" (or "not installed") for one unit.
unit_state_text()
{
    local unit="$1"
    if ! unit_installed "$unit"; then
        echo "not installed"
        return
    fi
    echo "enabled=$(unit_enabled_str "$unit") active=$(unit_active_str "$unit")"
}


### ---------------------------------------------------------------------
### Detection pass -- collected once into parallel arrays, consumed below
### by whichever output format was asked for.
### ---------------------------------------------------------------------

DEV_VIDPID=(); DEV_LABEL=(); DEV_BUSDEV=(); DEV_SERIAL=()
for vidpid in "${!DEVICE_LABELS[@]}"; do
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        busdev="$(echo "$line" | sed -n 's/^Bus \([0-9]*\) Device \([0-9]*\):.*/\1:\2/p')"
        serial="$(lsusb -v -s "$busdev" 2>/dev/null \
            | awk '/iSerial/ {for (i=3; i<=NF; i++) printf "%s ", $i; print ""}' \
            | sed 's/[[:space:]]*$//')"

        DEV_VIDPID+=("$vidpid")
        DEV_LABEL+=("${DEVICE_LABELS[$vidpid]}")
        DEV_BUSDEV+=("$busdev")
        DEV_SERIAL+=("$serial")

        kind="${DEVICE_KIND[$vidpid]:-}"
        if [[ -n "$kind" ]]; then
            ATTACHED_COUNT[$kind]=$(( ${ATTACHED_COUNT[$kind]:-0} + 1 ))
            [[ -n "$serial" ]] && ATTACHED_SERIALS[$kind]="${ATTACHED_SERIALS[$kind]:-} $serial"
        fi
    done < <(lsusb -d "$vidpid" 2>/dev/null)
done

shopt -s nullglob
RADIOD_CONFS=("${KA9Q_CONFIG_DIR}"/radiod@*.conf)
shopt -u nullglob

RADIOD_MISSION=(); RADIOD_HW=(); RADIOD_SERIAL=(); RADIOD_ENABLED=(); RADIOD_ACTIVE=(); RADIOD_ATTACHED=()
ANY_RADIOD_ACTIVE=0
for conf in "${RADIOD_CONFS[@]}"; do
    mission="$(basename "$conf")"
    mission="${mission#radiod@}"
    mission="${mission%.conf}"
    unit="radiod@${mission}.service"

    hw="$(grep -m1 -E '^\s*hardware\s*=' "$conf" 2>/dev/null | sed -E 's/.*=\s*//')"
    serial="$(grep -m1 -E '^\s*serial\s*=' "$conf" 2>/dev/null | sed -E 's/.*=\s*//')"
    kind="$(echo "${hw:-}" | tr '[:upper:]' '[:lower:]')"

    RADIOD_MISSION+=("$(basename "$conf")")
    RADIOD_HW+=("$hw")
    RADIOD_SERIAL+=("$serial")
    RADIOD_ENABLED+=("$(unit_enabled_str "$unit")")
    RADIOD_ACTIVE+=("$(unit_active_str "$unit")")
    if [[ -n "$serial" ]] && serial_attached "$kind" "$serial"; then
        RADIOD_ATTACHED+=("yes")
    elif [[ -n "$serial" ]]; then
        RADIOD_ATTACHED+=("no")
    else
        RADIOD_ATTACHED+=("")
    fi

    unit_is_active "$unit" && ANY_RADIOD_ACTIVE=1
done

OPENWEBRX_ENABLED="$(unit_enabled_str "$OPENWEBRX_UNIT")"
OPENWEBRX_ACTIVE_STR="$(unit_active_str "$OPENWEBRX_UNIT")"
OPENWEBRX_ACTIVE=0
unit_is_active "$OPENWEBRX_UNIT" && OPENWEBRX_ACTIVE=1

SDRANGELSRV_ACTIVE_STR="$(unit_active_str "$SDRANGELSRV_UNIT")"
SOAPYSDRSRV_ACTIVE_STR="$(unit_active_str "$SOAPYSDRSRV_UNIT")"

RTLTCP_SERIAL=""
if [[ -f "$RTLTCP_ENV_FILE" ]]; then
    RTLTCP_SERIAL="$(grep -m1 -E '^\s*RTLTCP_SERIAL\s*=' "$RTLTCP_ENV_FILE" 2>/dev/null | sed -E 's/.*=\s*//')"
fi
RTLTCP_ATTACHED=""
if [[ -n "$RTLTCP_SERIAL" ]]; then
    serial_attached "rtlsdr" "$RTLTCP_SERIAL" && RTLTCP_ATTACHED="yes" || RTLTCP_ATTACHED="no"
fi
RTLTCP_ENABLED="$(unit_enabled_str "$RTLTCP_UNIT")"
RTLTCP_ACTIVE_STR="$(unit_active_str "$RTLTCP_UNIT")"


### ---------------------------------------------------------------------
### JSON output
### ---------------------------------------------------------------------

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

json_str_or_null() {
    # Empty string -> JSON null (used throughout for "no serial exposed" /
    # "unpinned" / "no hardware= line" / "not cross-matched" rather than
    # an empty-string sentinel a consumer might mistake for a real value).
    if [[ -z "$1" ]]; then
        printf 'null'
    else
        printf '"%s"' "$(json_escape "$1")"
    fi
}

json_bool() {
    [[ "$1" == "active" || "$1" == "yes" ]] && printf 'true' || printf 'false'
}

print_json() {
    echo "{"

    echo '  "devices": ['
    for i in "${!DEV_VIDPID[@]}"; do
        printf '    {"vidpid": "%s", "label": "%s", "bus_device": "%s", "serial": %s}%s\n' \
            "$(json_escape "${DEV_VIDPID[$i]}")" \
            "$(json_escape "${DEV_LABEL[$i]}")" \
            "$(json_escape "${DEV_BUSDEV[$i]}")" \
            "$(json_str_or_null "${DEV_SERIAL[$i]}")" \
            "$([[ $i -lt $((${#DEV_VIDPID[@]} - 1)) ]] && echo ',')"
    done
    echo '  ],'

    echo '  "claims": {'

    echo '    "radiod": ['
    for i in "${!RADIOD_MISSION[@]}"; do
        printf '      {"mission": "%s", "hardware": %s, "serial": %s, "enabled": "%s", "active": "%s", "serial_attached": %s}%s\n' \
            "$(json_escape "${RADIOD_MISSION[$i]}")" \
            "$(json_str_or_null "${RADIOD_HW[$i]}")" \
            "$(json_str_or_null "${RADIOD_SERIAL[$i]}")" \
            "$(json_escape "${RADIOD_ENABLED[$i]}")" \
            "$(json_escape "${RADIOD_ACTIVE[$i]}")" \
            "$(json_str_or_null "${RADIOD_ATTACHED[$i]}")" \
            "$([[ $i -lt $((${#RADIOD_MISSION[@]} - 1)) ]] && echo ',')"
    done
    echo '    ],'

    printf '    "openwebrx": {"enabled": "%s", "active": "%s"},\n' \
        "$(json_escape "$OPENWEBRX_ENABLED")" "$(json_escape "$OPENWEBRX_ACTIVE_STR")"

    printf '    "rtltcp": {"env_file": "%s", "serial": %s, "serial_attached": %s, "enabled": "%s", "active": "%s"},\n' \
        "$(json_escape "$RTLTCP_ENV_FILE")" "$(json_str_or_null "$RTLTCP_SERIAL")" "$(json_str_or_null "$RTLTCP_ATTACHED")" \
        "$(json_escape "$RTLTCP_ENABLED")" "$(json_escape "$RTLTCP_ACTIVE_STR")"

    echo '    "unverified_device_services": {'
    printf '      "sdrangelsrv": %s,\n' "$(json_bool "$SDRANGELSRV_ACTIVE_STR")"
    printf '      "soapysdrsrv": %s\n' "$(json_bool "$SOAPYSDRSRV_ACTIVE_STR")"
    echo '    }'

    echo '  },'

    printf '  "conflict": %s\n' "$([[ "$ANY_RADIOD_ACTIVE" -eq 1 && "$OPENWEBRX_ACTIVE" -eq 1 ]] && echo true || echo false)"

    echo '}'
}

if [[ "$JSON_OUT" -eq 1 ]]; then
    print_json
    exit 0
fi


### ---------------------------------------------------------------------
### Concise output (default) -- one line per attached SDR: which service
### it's pinned to by serial, and whether that service is enabled. Only
### radiod and RTL-TCP can ever be shown here, because they're the only
### two claim sources that pin a *specific* serial -- OpenWebRX is a
### single whole-host service with no per-device pin (its own device
### selection lives in /var/lib/openwebrx/settings.json, see this
### script's header comment), so it's reported once, separately, rather
### than guessed onto a device row. SDRangel/SoapySDR Server have no
### per-device claim at all and are --detail-only.
### ---------------------------------------------------------------------

print_concise() {
    if [[ ${#DEV_VIDPID[@]} -eq 0 ]]; then
        echo "No SDR/RF devices attached."
        return
    fi

    local i j vidpid kind serial service enabled mission

    printf '%-34s %-34s %-26s %s\n' "DEVICE" "SERIAL" "SERVICE" "ENABLED"
    for i in "${!DEV_VIDPID[@]}"; do
        vidpid="${DEV_VIDPID[$i]}"
        kind="${DEVICE_KIND[$vidpid]:-}"
        serial="${DEV_SERIAL[$i]}"
        service="-"
        enabled="-"

        if [[ -n "$serial" ]]; then
            for j in "${!RADIOD_MISSION[@]}"; do
                if [[ "$(echo "${RADIOD_HW[$j]:-}" | tr '[:upper:]' '[:lower:]')" == "$kind" \
                    && "${RADIOD_SERIAL[$j]}" == "$serial" ]]; then
                    mission="${RADIOD_MISSION[$j]#radiod@}"
                    mission="${mission%.conf}"
                    service="radiod@${mission}"
                    enabled="${RADIOD_ENABLED[$j]}"
                    break
                fi
            done

            if [[ "$service" == "-" && "$kind" == "rtlsdr" && "$serial" == "$RTLTCP_SERIAL" ]]; then
                service="rtltcp"
                enabled="$RTLTCP_ENABLED"
            fi
        fi

        printf '%-34s %-34s %-26s %s\n' \
            "${DEV_LABEL[$i]}" "${serial:-<none exposed>}" "$service" "$enabled"
    done

    echo
    echo "OpenWebRX ($OPENWEBRX_UNIT): enabled=$OPENWEBRX_ENABLED"
    echo "  (whole-host, no per-device pin -- device selection is in /var/lib/openwebrx/settings.json)"

    if [[ "$ANY_RADIOD_ACTIVE" -eq 1 && "$OPENWEBRX_ACTIVE" -eq 1 ]]; then
        echo
        echo "** CONFLICT: a radiod@ mission and OpenWebRX are both active at once -- an SDR must"
        echo "** have exactly one active owner. Pick a side: scripts/service_toggle ka9q-radio|openwebrx|off"
    fi

    echo
    echo "Pass --detail for the full diagnostic report, --json for machine-readable output."
}


### ---------------------------------------------------------------------
### Detailed output (--detail) -- everything this script knows: every
### claim source, live enabled/active state, unpinned-device warnings,
### and the conflict check. This was the only, default output before
### --detail existed.
### ---------------------------------------------------------------------

print_detail() {
    echo "== Attached SDR/RF devices =="
    echo

    if [[ ${#DEV_VIDPID[@]} -eq 0 ]]; then
        echo "  (none of the known SDR/RF device types found attached)"
        echo
    else
        for i in "${!DEV_VIDPID[@]}"; do
            echo "  [${DEV_VIDPID[$i]}] ${DEV_LABEL[$i]}"
            echo "    USB:    Bus ${DEV_BUSDEV[$i]}"
            echo "    Serial: ${DEV_SERIAL[$i]:-<none exposed>}"
            echo
        done
    fi

    echo "== Existing SIGedge claims =="
    echo

    echo "-- radiod missions (${KA9Q_CONFIG_DIR}/radiod@*.conf) --"
    if [[ ${#RADIOD_MISSION[@]} -eq 0 ]]; then
        echo "  (none found)"
    else
        for i in "${!RADIOD_MISSION[@]}"; do
            echo "  ${RADIOD_MISSION[$i]}: hardware=${RADIOD_HW[$i]:-?} serial=${RADIOD_SERIAL[$i]:-<unpinned>} enabled=${RADIOD_ENABLED[$i]} active=${RADIOD_ACTIVE[$i]}"

            kind="$(echo "${RADIOD_HW[$i]:-}" | tr '[:upper:]' '[:lower:]')"
            if [[ -n "${RADIOD_SERIAL[$i]}" ]]; then
                if [[ "${RADIOD_ATTACHED[$i]}" == "yes" ]]; then
                    echo "      -> serial ${RADIOD_SERIAL[$i]} is currently attached"
                else
                    echo "      -> serial ${RADIOD_SERIAL[$i]} is NOT currently attached -- this mission will fail to open its device"
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
    if [[ "$OPENWEBRX_ENABLED" == "not installed" ]]; then
        echo "  not installed"
    else
        echo "  enabled=$OPENWEBRX_ENABLED active=$OPENWEBRX_ACTIVE_STR"
        echo "      -> device selection lives in /var/lib/openwebrx/settings.json (web UI), not shown here"
    fi
    echo

    if [[ "$ANY_RADIOD_ACTIVE" -eq 1 && "$OPENWEBRX_ACTIVE" -eq 1 ]]; then
        echo "  ** CONFLICT: at least one radiod@ mission AND OpenWebRX are both active at once. **"
        echo "  ** An SDR must have exactly one active owner -- pick a side with                  **"
        echo "  ** 'scripts/service_toggle ka9q-radio|openwebrx|off'.                              **"
        echo
    fi

    echo "-- SDRangel server / SoapySDR Server (unverified) --"
    echo "  $SDRANGELSRV_UNIT:  $SDRANGELSRV_ACTIVE_STR"
    echo "  $SOAPYSDRSRV_UNIT:  $SOAPYSDRSRV_ACTIVE_STR"
    echo "  (active/inactive only -- neither exposes a SIGedge-visible per-device claim;"
    echo "   'inactive' does NOT mean a device is free if one of these is stopped-but-"
    echo "   still-configured against it. See this script's own header comment.)"
    echo

    echo "-- RTL-TCP server ($RTLTCP_UNIT, $RTLTCP_ENV_FILE) --"
    if [[ "$RTLTCP_ENABLED" == "not installed" ]]; then
        echo "  not installed"
    else
        echo "  enabled=$RTLTCP_ENABLED active=$RTLTCP_ACTIVE_STR"
        if [[ -n "$RTLTCP_SERIAL" ]]; then
            echo "  RTLTCP_SERIAL=$RTLTCP_SERIAL"
            if [[ "$RTLTCP_ATTACHED" == "yes" ]]; then
                echo "      -> serial $RTLTCP_SERIAL is currently attached"
            else
                echo "      -> serial $RTLTCP_SERIAL is NOT currently attached -- rtl_tcp will fail to open its device"
            fi
        else
            echo "  (unpinned -- auto-detects whichever unit it finds)"
        fi
    fi
    echo

    echo "== Reading this =="
    echo "An 'unpinned' radiod mission or RTL-TCP server with no serial constraint will"
    echo "grab whichever matching device it finds first."
    echo ""
    echo "This is fine with exactly ONE unit of that device type attached but a real collision"
    echo "risk with more than one of that device attached."
    echo ""
    echo "Pin by serial"
    echo "(radiod: RTLSDR_SERIAL= to scripts/cfg_ka9q-radio; RTL-TCP: RTLTCP_SERIAL= in"
    echo "$RTLTCP_ENV_FILE)"
    echo "whenever two always-on consumers need the same device type."
    echo ""
    echo "enabled=/active= reflects live systemd state, not just what's configured -- a mission's"
    echo "radiod@<mission>.conf can exist and still be disabled/inactive. Use scripts/service_toggle"
    echo "to switch a device between radiod and OpenWebRX; it always stops+disables the side being"
    echo "left before starting the other."
    echo ""
    echo "Pass --json for a machine-readable version of everything above, or omit both flags for"
    echo "the concise per-device summary."
    echo ""
    echo "See README.md's device-ownership section and this script's own header comment."
}

if [[ "$DETAIL_OUT" -eq 1 ]]; then
    print_detail
else
    print_concise
fi
