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
#   - OpenWebRX+'s live systemd enabled/active state, and the devices
#     enabled in its own /var/lib/openwebrx/settings.json (read through
#     scripts/adapters/openwebrx)
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
# On top of those config-level claims it shows, per device:
#   - its assignment in /etc/sigedge/assignments (scripts/sdr-assign)
#   - who actually holds the USB device open right now -- process and
#     systemd unit, via fuser on /dev/bus/usb/<bus>/<dev>. That's the
#     ground truth whichever driver a service uses. Seeing other users'
#     processes needs root: run with sudo, or with a cached sudo
#     credential, otherwise this column shows "?".
# and warns when they disagree (held by a unit other than the assigned
# owner, another service's config also claiming the device, ka9q-radio's
# rx888_boot firmware loader left active for an RX-888 assigned
# elsewhere, ka9q-radio's udev autostart enabled).
#
# This tool answers "what's attached, who owns it, and is that true right
# now" -- it does not change anything. Use scripts/sdr-assign to move a
# device between services; see README.md's device-ownership section for
# the underlying one-owner-per-device policy.
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

INVENTORY_HOME="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=lib/sdr_common.sh
source "${INVENTORY_HOME}/scripts/lib/sdr_common.sh"

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

# Known devices (VID:PID -> kind and label) live in lib/sdr_common.sh
# (SDR_KIND, SDR_LABEL), shared with scripts/sdr-assign.


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
DEV_KIND=(); DEV_ID=(); DEV_PORT=(); DEV_NODE=(); DEV_ASSIGNED=(); DEV_HELD=(); DEV_HELD_UNITS=()
HOLDERS_KNOWN=1
while IFS='|' read -r kind vidpid port bus dev node serial id label; do
    [[ -n "$kind" ]] || continue
    DEV_VIDPID+=("$vidpid")
    DEV_LABEL+=("$label")
    DEV_BUSDEV+=("$(printf '%03d:%03d' "$bus" "$dev")")
    DEV_SERIAL+=("$serial")
    DEV_KIND+=("$kind"); DEV_ID+=("$id"); DEV_PORT+=("$port"); DEV_NODE+=("$node")
    DEV_ASSIGNED+=("$(sdr_assignment_get "$id" 2>/dev/null)")

    holders="$(sdr_holders "$node")"; rc=$?
    if (( rc == 2 )); then
        HOLDERS_KNOWN=0
        DEV_HELD+=("?"); DEV_HELD_UNITS+=("")
    elif [[ -z "$holders" ]]; then
        DEV_HELD+=("-"); DEV_HELD_UNITS+=("")
    else
        DEV_HELD+=("$(echo "$holders" | awk -F'|' '{printf "%s%s(%s)", (NR>1?", ":""), $3, $2}')")
        DEV_HELD_UNITS+=("$(echo "$holders" | awk -F'|' '{print $3}' | sort -u | paste -sd' ')")
    fi

    ATTACHED_COUNT[$kind]=$(( ${ATTACHED_COUNT[$kind]:-0} + 1 ))
    [[ -n "$serial" ]] && ATTACHED_SERIALS[$kind]="${ATTACHED_SERIALS[$kind]:-} $serial"
done < <(sdr_scan)

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
### Ownership warnings: assignment vs. live holders vs. config claims
### ---------------------------------------------------------------------

# Units that legitimately hold a device for an assigned service.
expected_units()
{
    local svc="$1" inst="$2"
    case "$svc" in
        radiod )      echo "radiod@${inst}.service rx888_boot.service" ;;
        openwebrx )   echo "openwebrx.service" ;;
        rtltcp )      echo "rtltcp.service" ;;
        sdrangelsrv ) echo "sdrangelsrv.service" ;;
        soapysdrsrv ) echo "soapysdrsrv.service" ;;
    esac
}

# Config claims from every installed service: "service kind id instance".
CLAIMS=()
for svc in "${SDR_SERVICES[@]}"; do
    sdr_adapter "$svc" adapter_installed 2>/dev/null || continue
    while read -r ck cid ci; do
        [[ -n "$ck" ]] && CLAIMS+=("$svc $ck $cid ${ci:--}")
    done < <(sdr_adapter "$svc" adapter_claims 2>/dev/null)
done

WARNINGS=()
DEV_FLAG=()
for i in "${!DEV_ID[@]}"; do
    flag=""
    read -r a_svc a_inst <<<"${DEV_ASSIGNED[$i]:-}"
    if [[ -n "${a_svc:-}" && -n "${DEV_HELD_UNITS[$i]}" ]]; then
        exp=" $(expected_units "$a_svc" "${a_inst:--}") "
        for u in ${DEV_HELD_UNITS[$i]}; do
            if [[ "$exp" != *" $u "* ]]; then
                WARNINGS+=("${DEV_LABEL[$i]} (${DEV_ID[$i]}) is assigned to ${a_svc} but held by ${u}")
                flag="!"
            fi
        done
    fi
    for c in "${CLAIMS[@]}"; do
        read -r c_svc c_kind c_id c_inst <<<"$c"
        [[ "$c_kind" == "${DEV_KIND[$i]}" ]] || continue
        [[ "$c_id" == "*" || "$c_id" == "${DEV_ID[$i]}" || "$c_id" == "${DEV_SERIAL[$i]}" ]] || continue
        [[ "$c_svc" == "${a_svc:-}" ]] && continue
        if [[ -n "${a_svc:-}" ]]; then
            WARNINGS+=("${DEV_LABEL[$i]} (${DEV_ID[$i]}) is assigned to ${a_svc}, but ${c_svc}$([[ "$c_inst" != "-" ]] && echo " ${c_inst}")'s config also claims it")
            flag="!"
        fi
    done
    if [[ "${DEV_KIND[$i]}" == "rx888" && -n "${a_svc:-}" && "$a_svc" != "radiod" ]] && \
       systemctl list-unit-files rx888_boot.service --no-legend 2>/dev/null | grep -q . && \
       [[ "$(systemctl is-enabled rx888_boot.service 2>/dev/null)" != "masked" ]]; then
        WARNINGS+=("rx888_boot.service is not masked: ka9q-radio will load its firmware into the RX-888 assigned to ${a_svc} (fix: scripts/sdr-assign rx888 ${a_svc} again, or systemctl mask rx888_boot.service)")
        flag="!"
    fi
    DEV_FLAG+=("$flag")
done
[[ -f /etc/radio/enable-udev-autostart ]] && \
    WARNINGS+=("/etc/radio/enable-udev-autostart exists: ka9q-radio starts its own ka9q-radio@ instance for SDRs as they're plugged in, outside SIGedge's assignments")


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
        read -r a_svc a_inst <<<"${DEV_ASSIGNED[$i]:-}"
        held="null"
        if [[ "${DEV_HELD[$i]}" != "?" ]]; then
            held="[$(for u in ${DEV_HELD_UNITS[$i]}; do printf '"%s",' "$(json_escape "$u")"; done | sed 's/,$//')]"
        fi
        printf '    {"kind": "%s", "id": %s, "vidpid": "%s", "label": "%s", "port": "%s", "bus_device": "%s", "serial": %s, "assigned_service": %s, "assigned_instance": %s, "held_by_units": %s}%s\n' \
            "$(json_escape "${DEV_KIND[$i]}")" \
            "$(json_str_or_null "${DEV_ID[$i]}")" \
            "$(json_escape "${DEV_VIDPID[$i]}")" \
            "$(json_escape "${DEV_LABEL[$i]}")" \
            "$(json_escape "${DEV_PORT[$i]}")" \
            "$(json_escape "${DEV_BUSDEV[$i]}")" \
            "$(json_str_or_null "${DEV_SERIAL[$i]}")" \
            "$(json_str_or_null "${a_svc:-}")" \
            "$(json_str_or_null "$([[ "${a_inst:--}" != "-" ]] && echo "$a_inst")")" \
            "$held" \
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

    printf '  "conflict": %s,\n' "$([[ "$ANY_RADIOD_ACTIVE" -eq 1 && "$OPENWEBRX_ACTIVE" -eq 1 ]] && echo true || echo false)"
    echo '  "warnings": ['
    for i in "${!WARNINGS[@]}"; do
        printf '    "%s"%s\n' "$(json_escape "${WARNINGS[$i]}")" "$([[ $i -lt $((${#WARNINGS[@]} - 1)) ]] && echo ',')"
    done
    echo '  ]'

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

    local i a
    printf '%-31s %-36s %-26s %s\n' "DEVICE" "ID" "ASSIGNED TO" "HELD BY (live)"
    for i in "${!DEV_VIDPID[@]}"; do
        a="${DEV_ASSIGNED[$i]:-(unassigned)}"
        printf '%-31s %-36s %-26s %s%s\n' \
            "${DEV_LABEL[$i]}" "${DEV_ID[$i]:-<no serial>}" "${a% -}" "${DEV_HELD[$i]}" \
            "$([[ -n "${DEV_FLAG[$i]}" ]] && echo '   <-- see warnings')"
    done

    if (( ! HOLDERS_KNOWN )); then
        echo
        echo "HELD BY shows '?' without root; run with sudo to see which process holds each device."
    fi
    if (( ${#WARNINGS[@]} )); then
        echo
        printf 'WARNING: %s\n' "${WARNINGS[@]}"
    fi
    if [[ "$ANY_RADIOD_ACTIVE" -eq 1 && "$OPENWEBRX_ACTIVE" -eq 1 ]]; then
        echo
        echo "Note: radiod and OpenWebRX+ are both running. That's fine when each owns different"
        echo "devices (see ASSIGNED TO / HELD BY); move a device with scripts/sdr-assign."
    fi

    echo
    echo "Move a device: scripts/sdr-assign <id|kind> <service>. --detail for every claim source, --json for tooling."
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
            echo "    ID:     ${DEV_ID[$i]:-<none: not assignable>}  (port ${DEV_PORT[$i]})"
            echo "    Assigned to: ${DEV_ASSIGNED[$i]:-(unassigned)}" | sed 's/ -$//'
            echo "    Held by:     ${DEV_HELD[$i]}$([[ "${DEV_HELD[$i]}" == "?" ]] && echo '  (needs root to see)')"
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
        local c c_svc c_kind c_id shown=0
        for c in "${CLAIMS[@]}"; do
            read -r c_svc c_kind c_id _ <<<"$c"
            [[ "$c_svc" == "openwebrx" ]] || continue
            echo "      -> enabled device: ${c_kind} $([[ "$c_id" == "*" ]] && echo "(any -- not pinned)" || echo "$c_id")"
            shown=1
        done
        (( shown )) || echo "      -> no enabled devices (or the service is disabled)"
    fi
    echo

    if [[ "$ANY_RADIOD_ACTIVE" -eq 1 && "$OPENWEBRX_ACTIVE" -eq 1 ]]; then
        echo "  Note: a radiod@ mission and OpenWebRX+ are both active. That's only a conflict if"
        echo "  they use the same device -- check the per-device Assigned to / Held by lines above."
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

    echo "== Warnings =="
    if (( ${#WARNINGS[@]} )); then
        printf '  %s\n' "${WARNINGS[@]}"
    else
        echo "  (none)"
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
    echo "radiod@<mission>.conf can exist and still be disabled/inactive. 'Held by' is the live"
    echo "truth: the process that has the USB device open right now (OpenWebRX+ only opens a"
    echo "device while someone is listening). Use scripts/sdr-assign to move a device between"
    echo "services; it releases the old owner, checks the device is free, runs the device's"
    echo "handoff, then starts the new owner."
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
