#!/usr/bin/env bash
#
# scripts/device-inventory.sh
#
# Lists attached SDR/RF USB devices (RTL-SDR, HackRF, Ubertooth, RX-888)
# with their real USB serial numbers, side by side with whatever SIGedge
# configs currently claim a device -- radiod's per-mission `serial = `
# line (scripts/cfg_ka9q-radio's RTLSDR_SERIAL/HACKRF_SERIAL/RX888_SERIAL)
# and Kismet's rtl433-sn-<serial> / ubertooth<N> source= lines in
# kismet_site.conf. Read-only and non-invasive throughout: `lsusb -v`
# reads standard USB descriptors without claiming the device, so this is
# safe to run alongside an already-running radiod/Kismet/direct-access
# owner -- unlike rtl_eeprom/rtl_test/hackrf_info, which open the device
# and would either fail or (worse) contend with a real owner.
#
# This tool answers "what's attached and what already claims it" -- it
# does not resolve conflicts or assign devices itself. See README.md's
# device-ownership section for the actual policy (one owner per device;
# pin by serial when more than one always-on consumer needs the same
# device type).
#
# Usage: ./scripts/device-inventory.sh
#   No arguments, no sudo required.

set -uo pipefail

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
    done < <(lsusb -d "$vidpid" 2>/dev/null)
done

if [[ "$FOUND_ANY" -eq 0 ]]; then
    echo "  (none of the known SDR/RF device types found attached)"
    echo
fi

echo "== Existing SIGedge claims =="
echo

echo "-- radiod missions (/etc/radio/radiod@*.conf) --"
shopt -s nullglob
RADIOD_CONFS=(/etc/radio/radiod@*.conf)
shopt -u nullglob
if [[ ${#RADIOD_CONFS[@]} -eq 0 ]]; then
    echo "  (none found)"
else
    for conf in "${RADIOD_CONFS[@]}"; do
        hw="$(grep -m1 -E '^\s*hardware\s*=' "$conf" 2>/dev/null | sed -E 's/.*=\s*//')"
        serial="$(grep -m1 -E '^\s*serial\s*=' "$conf" 2>/dev/null | sed -E 's/.*=\s*//')"
        echo "  $(basename "$conf"): hardware=${hw:-?} serial=${serial:-<unpinned -- auto-detects whichever unit it finds>}"
    done
fi
echo

echo "-- Kismet (/usr/local/etc/kismet_site.conf) --"
if [[ -f /usr/local/etc/kismet_site.conf ]]; then
    sources="$(grep -E '^source=' /usr/local/etc/kismet_site.conf 2>/dev/null)"
    if [[ -z "$sources" ]]; then
        echo "  (no active source= lines)"
    else
        echo "$sources" | sed 's/^/  /'
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
echo "See README.md's device-ownership section and this script's own header comment."
