#!/bin/bash
#
# tests/sdr-assign-test.sh -- regression test for per-device assignment
# (scripts/sdr-assign, scripts/adapters/*, scripts/handoff/rx888,
# scripts/service_toggle, scripts/device-inventory.sh).
#
# Runs entirely in a temporary sandbox: fake sysfs devices (RTL-SDR,
# HackRF, RX-888), and fake sudo, systemctl, fuser and fx3_cmd on PATH. No
# root, no hardware and no real service is touched. Config paths are
# redirected with the scripts' own override variables (SDR_SYSFS_USB,
# SDR_ASSIGNMENTS, KA9Q_CONFIG_DIR, RTLTCP_ENV, OWRX_SETTINGS).
#
# Usage: tests/sdr-assign-test.sh        exit 0 = all checks passed

set -u
REPO="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
H="$(mktemp -d)"
trap 'rm -rf "$H"' EXIT
PASS=0; FAIL=0

check()
{
    local what="$1"; shift
    if "$@" >/dev/null 2>&1; then PASS=$((PASS + 1)); echo "  ok   $what"
    else FAIL=$((FAIL + 1)); echo "  FAIL $what"; fi
}
unit_is()   { [[ "$(cat "$H/units/$1" 2>/dev/null)" == "$2" ]]; }
record_is() { grep -qx "$1" "$H/assignments"; }
no_record() { ! grep -q " $1 " "$H/assignments" 2>/dev/null; }
owrx_on()   { python3 -c "import json,sys; d=json.load(open('$H/owrx.json')); sys.exit(0 if any(v['type']=='$1' and v.get('enabled',True) for v in d['sdrs'].values()) else 1)"; }
owrx_off()  { ! owrx_on "$1"; }

### Sandbox ---------------------------------------------------------------
mkdir -p "$H/bin" "$H/units" "$H/sys" "$H/radio" "$H/default"
mkdev() { local d="$H/sys/$1"; mkdir -p "$d"; echo "$2" >"$d/idVendor"; echo "$3" >"$d/idProduct"; echo "$4" >"$d/busnum"; echo "$5" >"$d/devnum"; echo "$6" >"$d/serial"; }
mkdev 1-3 0bda 2838 1 5 00000101
mkdev 3-2 1d50 6089 3 2 0000000000000000a06063c82b6f0f1b
HACKRF=0000000000000000a06063c82b6f0f1b
# One physical USB 3 socket: port 4 on SuperSpeed bus 4, with its USB 2
# peer, port 4 on bus 3. The RX-888 sits on bus 4 with firmware loaded and
# reappears on bus 3 in its (USB 2) bootloader -- as on real hardware.
for b in 3 4; do mkdir -p "$H/sys/usb$b/$b-0:1.0/usb$b-port4"; done
echo 480 >"$H/sys/usb3/speed"; echo 5000 >"$H/sys/usb4/speed"
ln -s ../../../usb3/3-0:1.0/usb3-port4 "$H/sys/usb4/4-0:1.0/usb4-port4/peer"
ln -s ../../../usb4/4-0:1.0/usb4-port4 "$H/sys/usb3/3-0:1.0/usb3-port4/peer"
rx888_firmware()   { rm -rf "$H/sys/3-4" "$H/sys/4-4"; mkdev 4-4 04b4 00f1 4 2 0009090703432E0F; }
rx888_bootloader() { rm -rf "$H/sys/3-4" "$H/sys/4-4"; mkdev 3-4 04b4 00f3 3 8 0000000004BE; }
rx888_firmware
RX=port:3-4

cat >"$H/bin/sudo" <<'EOF'
#!/bin/bash
case "$1" in -v) exit 0 ;; -n) shift; [ "$1" = true ] && exit 0 ;; esac
exec "$@"
EOF
cat >"$H/bin/fuser" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$H/bin/fx3_cmd" <<'EOF'
#!/bin/bash
# RESETFX3: the device drops off USB 3 and re-enumerates on the USB 2 peer.
if [ "$1" = reset ] && [ -d "$HARNESS/sys/4-4" ]; then
    rm -rf "$HARNESS/sys/4-4"; d="$HARNESS/sys/3-4"; mkdir -p "$d"
    echo 04b4 >"$d/idVendor"; echo 00f3 >"$d/idProduct"; echo 3 >"$d/busnum"; echo 8 >"$d/devnum"; echo 0000000004BE >"$d/serial"
fi
exit 0
EOF
cat >"$H/bin/systemctl" <<'EOF'
#!/bin/bash
# State per unit file: "<enabled|disabled|masked> <active|inactive>"
U=$HARNESS/units; q=0; now=0; args=()
for a in "$@"; do case $a in --quiet) q=1;; --now) now=1;; --no-legend|--plain|--no-pager|--full) ;; *) args+=("$a");; esac; done
cmd=${args[0]}; unit=${args[1]:-}; f=$U/$unit
e=disabled; a=inactive; [ -f "$f" ] && read -r e a <"$f"
put() { echo "$1 $2" >"$f"; }
case $cmd in
  cat) [ -f "$f" ] && exit 0; t="${unit%%@*}@.service"; [ "$t" != "$unit" ] && [ -f "$U/$t" ] && exit 0; exit 1 ;;
  is-enabled) [ $q = 1 ] || echo "$e"; [ "$e" = enabled ] ;;
  is-active)  [ $q = 1 ] || echo "$a"; [ "$a" = active ] ;;
  enable)  [ $now = 1 ] && a=active; put enabled "$a" ;;
  disable) [ $now = 1 ] && a=inactive; put disabled "$a" ;;
  start) put "$e" active ;;
  stop)  put "$e" inactive ;;
  mask)   put masked "$a" ;;
  unmask) put disabled "$a" ;;
  list-unit-files) [ -f "$f" ] && echo "$unit x"; exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$H"/bin/*

for u in radiod@.service rtltcp.service rx888_boot.service sdrangelsrv.service; do echo "disabled inactive" >"$H/units/$u"; done
echo "enabled active" >"$H/units/openwebrx.service"
for m in hackrf-aprs rx888-wwv rtlsdr-simplex; do
    sed -e 's/##TTL##/1/' -e 's/##CENTER_HZ##/144640000/' -e '/##IFACE##/d' -e '/##SERIAL##/d' \
        "$REPO/config/radiod@$m.conf" >"$H/radio/radiod@$m.conf"
done
# OpenWebRX+ starts out using the HackRF and the RX-888, unpinned.
cat >"$H/owrx.json" <<'EOF'
{"version": 8, "sdrs": {
  "a": {"name": "HackRF", "type": "hackrf", "profiles": {"p1": {"name": "2m", "center_freq": 145000000, "samp_rate": 2400000, "start_freq": 144390000, "start_mod": "nfm"}}},
  "b": {"name": "RX-888", "type": "sddc_soapy", "profiles": {"p2": {"name": "WWV", "center_freq": 11000000, "samp_rate": 32000000, "start_freq": 10000000, "start_mod": "am"}}}
}}
EOF

export HARNESS="$H" PATH="$H/bin:$PATH" SDR_SYSFS_USB="$H/sys" SDR_ASSIGNMENTS="$H/assignments" \
       KA9Q_CONFIG_DIR="$H/radio" RTLTCP_ENV="$H/default/rtltcp" OWRX_SETTINGS="$H/owrx.json"
A="$REPO/scripts/sdr-assign"

### Scenarios -------------------------------------------------------------
echo "1. HackRF from OpenWebRX+ to radiod (first run adopts existing claims)"
"$A" -y hackrf radiod >/dev/null 2>&1
check "record: hackrf -> radiod hackrf-aprs" record_is "hackrf $HACKRF radiod hackrf-aprs"
check "record: rx888 adopted by openwebrx"   record_is "rx888 $RX openwebrx -"
check "radiod@hackrf-aprs running"           unit_is radiod@hackrf-aprs.service "enabled active"
check "mission pinned to HackRF serial"      grep -qx "serial = $HACKRF" "$H/radio/radiod@hackrf-aprs.conf"
check "OpenWebRX+ HackRF entry disabled"     owrx_off hackrf
check "OpenWebRX+ still running for RX-888"  unit_is openwebrx.service "enabled active"

echo "2. RX-888 from OpenWebRX+ to radiod (firmware handoff)"
"$A" -y rx888 radiod:rx888-wwv >/dev/null 2>&1
check "RX-888 reset, now on USB 2 bus (3-4)" grep -qx 00f3 "$H/sys/3-4/idProduct"
check "record keeps the same RX-888 id"      record_is "rx888 $RX radiod rx888-wwv"
check "rx888_boot unmasked for radiod"       unit_is rx888_boot.service "disabled inactive"
check "radiod@rx888-wwv running"             unit_is radiod@rx888-wwv.service "enabled active"
check "OpenWebRX+ stopped (nothing left)"    unit_is openwebrx.service "disabled inactive"

echo "3. RTL-SDR to rtl_tcp, then to OpenWebRX+"
"$A" -y 00000101 rtltcp >/dev/null 2>&1
check "RTLTCP_SERIAL pinned"                 grep -qx "RTLTCP_SERIAL=00000101" "$H/default/rtltcp"
check "rtltcp running"                       unit_is rtltcp.service "enabled active"
"$A" -y rtlsdr openwebrx >/dev/null 2>&1
check "rtltcp stopped"                       unit_is rtltcp.service "disabled inactive"
check "OpenWebRX+ RTL-SDR entry created"     owrx_on rtl_sdr
check "OpenWebRX+ running"                   unit_is openwebrx.service "enabled active"

echo "4. RX-888 back to OpenWebRX+ (firmware loaded again)"
rx888_firmware
"$A" -y rx888 openwebrx >/dev/null 2>&1
check "rx888_boot masked for OpenWebRX+"     unit_is rx888_boot.service "masked inactive"
check "RX-888 reset to bootloader"           grep -qx 00f3 "$H/sys/3-4/idProduct"
check "radiod@rx888-wwv stopped"             unit_is radiod@rx888-wwv.service "disabled inactive"
check "record: rx888 -> openwebrx"           record_is "rx888 $RX openwebrx -"
check "one RX-888 in the record"             bash -c "[ \$(grep -c '^rx888 ' '$H/assignments') = 1 ]"
check "one RX-888 entry enabled in OpenWebRX+" python3 -c "import json,sys; d=json.load(open('$H/owrx.json')); sys.exit(0 if sum(1 for v in d['sdrs'].values() if v['type']=='sddc_soapy' and v.get('enabled',True))==1 else 1)"

echo "5. Whole-host guard (SDRangel server)"
check "refused without --force"              bash -c "! '$A' -y hackrf sdrangelsrv"
check "record unchanged"                     record_is "hackrf $HACKRF radiod hackrf-aprs"
"$A" -y --force hackrf sdrangelsrv >/dev/null 2>&1
check "--force assigns it"                   record_is "hackrf $HACKRF sdrangelsrv -"
check "others refused while it runs"         bash -c "! '$A' -y rtlsdr radiod:rtlsdr-simplex"
"$A" -y hackrf radiod >/dev/null 2>&1
check "moving its only device away is allowed" record_is "hackrf $HACKRF radiod hackrf-aprs"
check "sdrangelsrv stopped"                  unit_is sdrangelsrv.service "disabled inactive"

echo "5b. Failed handoff leaves the record truthful"
rx888_firmware
cat >"$H/bin/fx3_cmd" <<'EOF'
#!/bin/bash
exit 0
EOF
# fx3_cmd that does nothing: the RX-888 never leaves firmware mode.
RX888_HANDOFF_WAIT=1 "$A" -y rx888 radiod:rx888-wwv >/dev/null 2>&1; rc=$?
check "handoff failure is reported"          test "$rc" -ne 0
check "device recorded as unassigned"        bash -c "! grep -q '^rx888 ' '$H/assignments'"
check "previous owner was released"          python3 -c "import json,sys; d=json.load(open('$H/owrx.json')); sys.exit(1 if any(v['type']=='sddc_soapy' and v.get('enabled',True) for v in d['sdrs'].values()) else 0)"
rx888_bootloader

echo "5c. rx888_boot reloads firmware before the handoff sees the bootloader"
cat >"$H/bin/fx3_cmd" <<'EOF'
#!/bin/bash
# Reset, then straight back to firmware mode at a new USB address.
d="$HARNESS/sys/4-4"; [ "$1" = reset ] && [ -d "$d" ] && echo $(( $(cat "$d/devnum") + 1 )) >"$d/devnum"
exit 0
EOF
rx888_firmware
"$A" -y rx888 openwebrx >/dev/null 2>&1
RX888_HANDOFF_WAIT=2 "$A" -y rx888 radiod:rx888-wwv >/dev/null 2>&1; rc=$?
check "re-enumeration counts as a reset"     test "$rc" -eq 0
check "record: rx888 -> radiod"              record_is "rx888 $RX radiod rx888-wwv"

echo "6. Invalid requests"
check "rtltcp can't take an RX-888"          bash -c "! '$A' -y rx888 rtltcp"
check "unknown service rejected"             bash -c "! '$A' -y rx888 nosuchsvc"
check "unknown device rejected"              bash -c "! '$A' -y nosuchdev openwebrx"

echo "7. service_toggle wrapper"
"$REPO/scripts/service_toggle" -y off >/dev/null 2>&1
check "off: nothing assigned"                bash -c "! grep -v '^#' '$H/assignments' | grep -q ."
check "off: OpenWebRX+ stopped"              unit_is openwebrx.service "disabled inactive"
"$REPO/scripts/service_toggle" -y ka9q-radio >/dev/null 2>&1
check "ka9q-radio: all three missions"       bash -c "[ \$(grep -c ' radiod ' '$H/assignments') = 3 ]"
"$REPO/scripts/service_toggle" -y openwebrx >/dev/null 2>&1
check "openwebrx: all three to OpenWebRX+"   bash -c "[ \$(grep -c ' openwebrx ' '$H/assignments') = 3 ]"
check "openwebrx: missions stopped"          unit_is radiod@hackrf-aprs.service "disabled inactive"

echo "8. device-inventory"
"$REPO/scripts/device-inventory.sh" --json >"$H/inv.json" 2>/dev/null
check "JSON parses"                          python3 -c "import json; json.load(open('$H/inv.json'))"
check "JSON shows assignments"               python3 -c "import json,sys; d=json.load(open('$H/inv.json')); sys.exit(0 if all(x['assigned_service']=='openwebrx' for x in d['devices']) else 1)"
printf 'hackrf %s radiod hackrf-aprs\n' "$HACKRF" >"$H/assignments"
check "warns when config disagrees"          bash -c "'$REPO/scripts/device-inventory.sh' | grep -q \"openwebrx's config also claims\""

echo
echo "${PASS} passed, ${FAIL} failed"
(( FAIL == 0 ))
