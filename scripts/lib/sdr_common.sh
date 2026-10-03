#!/bin/bash

###
### SIGedge
###
### scripts/lib/sdr_common.sh
###
###
### 20261002-0000
###
### Shared helpers for per-device SDR ownership: device discovery,
### live holders, the assignment record, and service adapters. Sourced
### by scripts/sdr-assign, scripts/device-inventory.sh, the adapters in
### scripts/adapters/ and the handoff hooks in scripts/handoff/.
###
### Device identity: an SDR is identified by "<kind> <id>". The id is the
### USB serial number for every kind except the RX-888, whose serial
### changes with its firmware state (bootloader vs. loaded, and between
### firmware builds). An RX-888 is identified by its USB port path
### instead, e.g. "port:4-4", which survives the re-enumeration a
### firmware handoff causes, as long as it stays plugged into the same
### port.
###

SDR_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SDR_SCRIPTS_DIR="$(cd -- "${SDR_LIB_DIR}/.." && pwd)"
SDR_ADAPTER_DIR="${SDR_SCRIPTS_DIR}/adapters"
SDR_HANDOFF_DIR="${SDR_SCRIPTS_DIR}/handoff"

# Where device-to-service assignments are recorded. System state, not repo
# state: it lives in /etc so it survives a fresh clone of SIGedge.
SDR_ASSIGNMENTS="${SDR_ASSIGNMENTS:-/etc/sigedge/assignments}"

# sysfs root, overridable for testing.
SDR_SYSFS_USB="${SDR_SYSFS_USB:-/sys/bus/usb/devices}"

# Known VID:PID pairs -> kind / label. Kinds are what adapters and the
# assignment record use.
declare -gA SDR_KIND=(
    ["0bda:2838"]="rtlsdr"
    ["0bda:2832"]="rtlsdr"
    ["1d50:6089"]="hackrf"
    ["04b4:00f1"]="rx888"
    ["04b4:00f3"]="rx888"
)
declare -gA SDR_LABEL=(
    ["0bda:2838"]="RTL-SDR (RTL2838)"
    ["0bda:2832"]="RTL-SDR (RTL2832U)"
    ["1d50:6089"]="HackRF One"
    ["04b4:00f1"]="RX-888 MkII (firmware loaded)"
    ["04b4:00f3"]="RX-888 MkII (bootloader/DFU)"
)

# Every assignable service. Each has scripts/adapters/<name>.
# shellcheck disable=SC2034  # used by the scripts that source this file
SDR_SERVICES=(radiod openwebrx rtltcp sdrangelsrv soapysdrsrv)


sdr_msg()  { echo -e "${SIGEDGE_BANNER_COLOR:-} ##  $*${SIGEDGE_BANNER_RESET:-}"; }
sdr_err()  { echo -e "${SIGEDGE_BANNER_COLOR:-} ##  ERROR: $*${SIGEDGE_BANNER_RESET:-}" >&2; }

# Run a privileged command, or just print it under SDR_DRY_RUN=1.
sdr_sudo()
{
    if [[ "${SDR_DRY_RUN:-0}" == "1" ]]; then
        echo "  [dry-run] sudo $*"
        return 0
    fi
    sudo "$@"
}

# Write stdin to a root-owned file, keeping a timestamped backup of the old
# one. stdin is read completely before the file is touched, so a pipeline
# that reads the same file (awk ... "$f" | sdr_sudo_write "$f") is safe.
sdr_sudo_write()
{
    local file="$1" content
    content="$(cat; echo .)"; content="${content%.}"
    if [[ "${SDR_DRY_RUN:-0}" == "1" ]]; then
        echo "  [dry-run] write ${file}:"
        printf '%s' "$content" | sed 's/^/  [dry-run]   /'
        return 0
    fi
    sudo install -d -m 0755 "$(dirname "$file")" || return 1
    if [[ -f "$file" ]]; then
        sudo cp -p "$file" "${file}.$(date +%Y%m%d-%H%M%S.%N).bak" || return 1
    fi
    printf '%s' "$content" | sudo tee "$file" >/dev/null
}

sdr_unit_exists()  { systemctl cat "$1" >/dev/null 2>&1; }
sdr_unit_active()  { systemctl is-active --quiet "$1" 2>/dev/null; }
sdr_unit_enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }

sdr_unit_state()
{
    local unit="$1" e a
    sdr_unit_exists "$unit" || { echo "not-installed"; return; }
    e="$(systemctl is-enabled "$unit" 2>/dev/null)"
    a="$(systemctl is-active "$unit" 2>/dev/null)"
    echo "${e:-disabled}/${a:-inactive}"
}

sdr_unit_stop()
{
    local unit="$1"
    sdr_unit_exists "$unit" || return 0
    if sdr_unit_active "$unit" || sdr_unit_enabled "$unit"; then
        echo "  stopping and disabling ${unit}"
        sdr_sudo systemctl disable --now "$unit" || return 1
    fi
}

sdr_unit_start()
{
    local unit="$1"
    sdr_unit_exists "$unit" || { sdr_err "${unit} is not installed"; return 1; }
    echo "  enabling and starting ${unit}"
    sdr_sudo systemctl enable --now "$unit" || return 1
    if [[ "${SDR_DRY_RUN:-0}" != "1" ]] && ! sdr_unit_active "$unit"; then
        sdr_err "${unit} did not reach the active state"
        systemctl --no-pager --full status "$unit" 2>&1 | tail -15
        return 1
    fi
}


### ---------------------------------------------------------------------
### Discovery
### ---------------------------------------------------------------------

# One line per attached known SDR:
#   kind|vidpid|port|busnum|devnum|devnode|serial|id|label
# Read from sysfs only: no device is opened, no privileges needed.
sdr_scan()
{
    local d vid pid vidpid kind port bus dev serial id
    for d in "${SDR_SYSFS_USB}"/*; do
        [[ -f "$d/idVendor" && -f "$d/idProduct" ]] || continue
        vid="$(<"$d/idVendor")"; pid="$(<"$d/idProduct")"
        vidpid="${vid}:${pid}"
        kind="${SDR_KIND[$vidpid]:-}"
        [[ -n "$kind" ]] || continue
        port="$(basename "$d")"
        bus="$(<"$d/busnum")"; dev="$(<"$d/devnum")"
        serial=""
        [[ -r "$d/serial" ]] && serial="$(<"$d/serial")"
        if [[ "$kind" == "rx888" ]]; then
            id="port:${port}"
        else
            id="${serial}"
        fi
        printf '%s|%s|%s|%s|%s|/dev/bus/usb/%03d/%03d|%s|%s|%s\n' \
            "$kind" "$vidpid" "$port" "$bus" "$dev" "$bus" "$dev" \
            "$serial" "$id" "${SDR_LABEL[$vidpid]}"
    done
}

# Resolve a device spec to exactly one scan line. A spec is an id
# ("port:4-4", a serial), a serial alone, a port path, or a kind
# ("rx888") when exactly one of that kind is attached.
sdr_resolve()
{
    local spec="$1" line matches=() kind port serial id
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r kind _ port _ _ _ serial id _ <<<"$line"
        if [[ "$spec" == "$id" || "$spec" == "$serial" || "$spec" == "port:$port" \
              || "$spec" == "$port" || "$spec" == "$kind" ]]; then
            matches+=("$line")
        fi
    done < <(sdr_scan)

    if (( ${#matches[@]} == 0 )); then
        sdr_err "no attached SDR matches '${spec}' (see scripts/device-inventory.sh)"
        return 1
    fi
    if (( ${#matches[@]} > 1 )); then
        sdr_err "'${spec}' matches ${#matches[@]} devices; give a serial or port: instead"
        return 1
    fi
    printf '%s\n' "${matches[0]}"
}

sdr_count_kind()
{
    sdr_scan | awk -F'|' -v k="$1" '$1==k' | wc -l
}


### ---------------------------------------------------------------------
### Live holders -- ground truth, independent of any service's config
### ---------------------------------------------------------------------

# Processes holding a USB device node open, one per line: pid|comm|unit.
# Seeing another user's open file descriptors needs root, so fuser runs
# under `sudo -n` when not already root. Returns 2 if that isn't possible
# (the caller should report "unknown", not "free").
sdr_holders()
{
    local node="$1" pids pid comm unit
    [[ -e "$node" ]] || return 0
    if [[ $EUID -eq 0 ]]; then
        pids="$(fuser "$node" 2>/dev/null)"
    elif sudo -n true 2>/dev/null; then
        pids="$(sudo -n fuser "$node" 2>/dev/null)"
    else
        return 2
    fi
    for pid in $pids; do
        pid="${pid//[^0-9]/}"
        [[ -n "$pid" ]] || continue
        comm="$(cat "/proc/${pid}/comm" 2>/dev/null)"
        unit="$(awk -F/ '{print $NF}' "/proc/${pid}/cgroup" 2>/dev/null | head -1)"
        echo "${pid}|${comm:-?}|${unit:-?}"
    done
}

# Wait until nothing holds the device node (or it vanished), up to $2 s.
sdr_wait_free()
{
    local node="$1" timeout="${2:-15}" i out rc
    for (( i = 0; i < timeout; i++ )); do
        out="$(sdr_holders "$node")"; rc=$?
        (( rc == 2 )) && return 2
        [[ -z "$out" ]] && return 0
        sleep 1
    done
    return 1
}


### ---------------------------------------------------------------------
### Assignment record: /etc/sigedge/assignments
###
###   # kind  id                    service    instance
###   rx888   port:4-4              openwebrx  -
###   hackrf  000000000000...0f1b   radiod     hackrf-aprs
### ---------------------------------------------------------------------

sdr_assignment_get()
{
    local id="$1"
    [[ -r "$SDR_ASSIGNMENTS" ]] || return 1
    awk -v id="$id" '!/^[[:space:]]*#/ && NF>=3 && $2==id {print $3, ($4==""?"-":$4); found=1; exit} END {exit !found}' \
        "$SDR_ASSIGNMENTS"
}

sdr_assignment_list()
{
    [[ -r "$SDR_ASSIGNMENTS" ]] || return 0
    awk '!/^[[:space:]]*#/ && NF>=3 {print $1, $2, $3, ($4==""?"-":$4)}' "$SDR_ASSIGNMENTS"
}

# Devices currently assigned to a service: "kind id instance" lines.
sdr_assignments_for()
{
    local svc="$1"
    sdr_assignment_list | awk -v s="$svc" '$3==s {print $1, $2, $4}'
}

# Set (service != none) or clear (service == none) one device's assignment.
sdr_assignment_set()
{
    local kind="$1" id="$2" svc="$3" inst="${4:--}"
    {
        echo "# SIGedge device assignments -- managed by scripts/sdr-assign"
        echo "# kind  id  service  instance"
        sdr_assignment_list | awk -v id="$id" '$2!=id'
        [[ "$svc" != "none" ]] && echo "${kind} ${id} ${svc} ${inst}"
    } | awk '!seen[$0]++' | sdr_sudo_write "$SDR_ASSIGNMENTS"
}


### ---------------------------------------------------------------------
### Adapters
###
### scripts/adapters/<service> is sourced into a subshell and must define:
###   adapter_kinds          device kinds it can drive (space-separated)
###   adapter_whole_host     exit 0 if it opens every device it can see
###                          (no per-device selection), 1 otherwise
###   adapter_installed      exit 0 if the service is installed
###   adapter_units          systemd units it runs
###   adapter_claims         lines "kind id instance" it is configured to
###                          use (id "*" = any device of that kind)
###   adapter_acquire KIND ID INSTANCE
###   adapter_release KIND ID INSTANCE
### ---------------------------------------------------------------------

sdr_service_alias()
{
    case "$1" in
        ka9q-radio|ka9q ) echo "radiod" ;;
        rtltcpsrv )       echo "rtltcp" ;;
        * )               echo "$1" ;;
    esac
}

# sdr_adapter SERVICE FUNCTION [ARGS...] -- call one adapter function in a
# subshell, so adapters can't leak state into the caller.
sdr_adapter()
{
    local svc="$1" fn="$2"; shift 2
    local file="${SDR_ADAPTER_DIR}/${svc}"
    [[ -f "$file" ]] || { sdr_err "no adapter for service '${svc}'"; return 1; }
    (
        # shellcheck source=/dev/null
        source "$file" || exit 1
        "$fn" "$@"
    )
}

# Run the device-type handoff hook, if the kind has one.
sdr_handoff()
{
    local kind="$1"; shift
    local hook="${SDR_HANDOFF_DIR}/${kind}"
    [[ -x "$hook" ]] || return 0
    "$hook" "$@"
}
