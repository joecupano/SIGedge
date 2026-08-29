#!/bin/bash
# ==============================================================================
# Title:        ka9q-radio-config-gen.sh
# Description:  Interactive wizard that generates a radiod@<name>.conf file
#               for ka9q-radio (https://github.com/ka9q/ka9q-radio), covering
#               every SDR front end radiod supports: RTL-SDR, HackRF, RX-888
#               MkII, Airspy R2/Mini, Airspy HF+, SDRplay, BladeRF, RigExpert
#               Fobos, HydraSDR, and the legacy AMSAT-UK FUNcube Dongle.
#
#               Field names, defaults and ranges below are taken from the
#               project's own docs/SDR/*.md pages and its config/defaults and
#               config/examples sample files, not guessed. Where upstream
#               documentation is incomplete for a device (sdrplay, hackrf),
#               the wizard says so and falls back to a free-form "extra
#               lines" prompt instead of inventing field names.
#
# Usage:        ./ka9q-radio-config-gen.sh [-n NAME] [-d DEVICE] [-o DIR]
#                                           [--install] [--list-devices]
# ==============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
OUT_DIR="/etc/radio"
INSTALL=0
PRESET_NAME=""
DEVICE_ARG=""

DEVICES=(rtlsdr hackrf rx888 airspy airspyhf sdrplay bladerf fobos hydrasdr funcube)
declare -A DEVICE_DESC=(
  [rtlsdr]="RTL-SDR dongle (DVB-T tuner, ~24MHz-1.7GHz, ~2.5Msps)"
  [hackrf]="HackRF One (1MHz-6GHz, half-duplex, ~20Msps)"
  [rx888]="RX-888 MkII (direct sampling HF, 10kHz-64MHz, USB3)"
  [airspy]="Airspy R2 / Mini (24MHz-1.7GHz VHF/UHF, 10Msps complex)"
  [airspyhf]="Airspy HF+ (9kHz-31MHz HF and 64-260MHz VHF)"
  [sdrplay]="SDRplay RSP family"
  [bladerf]="BladeRF (300MHz-3.8GHz, 12-bit 40Msps)"
  [fobos]="RigExpert Fobos (100kHz-6GHz, 14-bit, up to 80Msps)"
  [hydrasdr]="HydraSDR RFone (24MHz-1.8GHz+, ~20Msps)"
  [funcube]="AMSAT-UK FUNcube Dongle (legacy, untested upstream)"
)

# ------------------------------------------------------------------ helpers -

die() { echo "[-] $*" >&2; exit 1; }
info() { echo "[+] $*"; }

# Called when a `read` hits EOF (stdin closed / input exhausted) inside a
# validation loop that would otherwise spin forever on a permanently blank
# reply. This may run inside a command-substitution subshell, where a plain
# `exit` would only end the subshell -- so signal the actual script process
# ($$ still refers to it even from inside $(...)) and exit either way.
abort_on_eof() {
  echo >&2
  echo "[-] Input ended unexpectedly (stdin closed). Aborting." >&2
  kill -TERM "$$" 2>/dev/null
  exit 1
}

# ask "prompt" "default" -> echoes chosen value
ask() {
  local prompt="$1" default="${2:-}" reply
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " reply || abort_on_eof
    echo "${reply:-$default}"
  else
    read -r -p "$prompt: " reply || abort_on_eof
    echo "$reply"
  fi
}

ask_yn() {
  local prompt="$1" default="${2:-n}" reply
  while true; do
    read -r -p "$prompt [y/n] (default: $default): " reply || abort_on_eof
    reply="${reply:-$default}"
    case "$reply" in
      y|Y|yes) echo "yes"; return ;;
      n|N|no) echo "no"; return ;;
      *) echo "    Please answer y or n." >&2 ;;
    esac
  done
}

# ask_num "prompt" "default" "min" "max" -> validated float/int string
ask_num() {
  local prompt="$1" default="$2" min="${3:-}" max="${4:-}" reply
  while true; do
    reply="$(ask "$prompt" "$default")"
    [ -z "$reply" ] && { echo ""; return; }
    if ! [[ "$reply" =~ ^-?[0-9]*\.?[0-9]+$ ]]; then
      echo "    Not a number, try again." >&2
      continue
    fi
    if [ -n "$min" ] && awk -v a="$reply" -v b="$min" 'BEGIN{exit !(a<b)}'; then
      echo "    Must be >= $min." >&2
      continue
    fi
    if [ -n "$max" ] && awk -v a="$reply" -v b="$max" 'BEGIN{exit !(a>b)}'; then
      echo "    Must be <= $max." >&2
      continue
    fi
    echo "$reply"
    return
  done
}

# Convert a human frequency ("14074000", "14.074M", "88.3M", "500k") to Hz.
to_hz() {
  local input="$1" num suf
  input="$(echo "$input" | tr -d '[:space:]')"
  if [[ "$input" =~ ^([0-9]*\.?[0-9]+)([kKmMgG]?)$ ]]; then
    num="${BASH_REMATCH[1]}"
    suf="${BASH_REMATCH[2]}"
    case "$suf" in
      k|K) awk -v n="$num" 'BEGIN{printf "%.0f", n*1000}' ;;
      m|M) awk -v n="$num" 'BEGIN{printf "%.0f", n*1000000}' ;;
      g|G) awk -v n="$num" 'BEGIN{printf "%.0f", n*1000000000}' ;;
      *)   awk -v n="$num" 'BEGIN{printf "%.0f", n}' ;;
    esac
    return 0
  fi
  return 1
}

# mDNS "description" fields must be <=63 chars, no '/' or control chars.
validate_desc() {
  local d="$1"
  [ "${#d}" -le 63 ] || { echo "    Too long (max 63 chars)." >&2; return 1; }
  [[ "$d" != *"/"* ]] || { echo "    Must not contain '/'." >&2; return 1; }
  [[ "$d" =~ ^[[:print:]]*$ ]] || { echo "    Must not contain control characters." >&2; return 1; }
  return 0
}

ask_desc() {
  local prompt="$1" default="$2" reply
  while true; do
    reply="$(ask "$prompt" "$default")"
    if validate_desc "$reply"; then echo "$reply"; return; fi
  done
}

# Free-form escape hatch: repeatedly ask for "key = value" lines.
ask_extra_lines() {
  local -n _out=$1
  local line
  echo "    (Optional) Add any extra 'key = value' lines this driver version" >&2
  echo "    supports but the wizard doesn't ask about by name. Blank to stop." >&2
  while true; do
    read -r -p "    extra line (blank to finish): " line || abort_on_eof
    [ -z "$line" ] && break
    _out+=("$line")
  done
}

PRESETS_HELP='Presets (from presets.conf): pm/npm=narrow FM voice, fm/nfm=narrow FM data,
  wfm=broadcast FM stereo, am=envelope AM, sam=coherent AM, ame=AM USB-only,
  iq=raw I/Q, cwu/cwl=CW on USB/LSB, usb/lsb=SSB voice, dsb=DSB-SC,
  amsq=AM w/ carrier squelch, wspr=USB no AGC, nam=flat AM, spectrum=experimental'

# --------------------------------------------------------------------- args -

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [-n NAME] [-d DEVICE] [-o DIR] [--install] [--list-devices]

  -n, --name NAME       Instance name -> writes radiod@NAME.conf
  -d, --device DEVICE   Skip the device menu (one of: ${DEVICES[*]})
  -o, --output DIR      Directory to write the file into (default: $OUT_DIR)
      --install         After generating, install to /etc/radio with sudo,
                         run 'systemctl daemon-reload', and offer to enable it
      --list-devices    Print supported device types and exit
  -h, --help            This help

Everything else (frequencies, gains, channels, ...) is gathered interactively.
Reference: https://github.com/ka9q/ka9q-radio
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--name) PRESET_NAME="$2"; shift 2 ;;
    -d|--device) DEVICE_ARG="$2"; shift 2 ;;
    -o|--output) OUT_DIR="$2"; shift 2 ;;
    --install) INSTALL=1; shift ;;
    --list-devices)
      for d in "${DEVICES[@]}"; do printf '%-10s %s\n' "$d" "${DEVICE_DESC[$d]}"; done
      exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (see --help)" ;;
  esac
done

command -v awk >/dev/null || die "awk is required"

# ------------------------------------------------------------- instance name -

echo "===================================================================="
echo " ka9q-radio config generator  (https://github.com/ka9q/ka9q-radio)"
echo "===================================================================="

if [ -n "$PRESET_NAME" ]; then
  NAME="$PRESET_NAME"
else
  while true; do
    NAME="$(ask "Instance name (e.g. rx888, 2m, hf-wspr)" "")"
    [[ "$NAME" =~ ^[A-Za-z0-9_-]+$ ]] && [ -n "$NAME" ] && break
    echo "    Use only letters, digits, '-' and '_'." >&2
  done
fi
CONF_FILE="radiod@${NAME}.conf"

# --------------------------------------------------------------- device menu -

if [ -n "$DEVICE_ARG" ]; then
  DEVICE="$DEVICE_ARG"
  [[ " ${DEVICES[*]} " == *" $DEVICE "* ]] || die "Unknown device '$DEVICE'. See --list-devices."
else
  echo
  echo "Select the SDR front end:"
  i=1
  for d in "${DEVICES[@]}"; do
    printf '  %2d) %-9s %s\n' "$i" "$d" "${DEVICE_DESC[$d]}"
    i=$((i+1))
  done
  while true; do
    sel="$(ask "Choice" "")"
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#DEVICES[@]}" ]; then
      DEVICE="${DEVICES[$((sel-1))]}"
      break
    fi
    echo "    Enter a number 1-${#DEVICES[@]}." >&2
  done
fi
info "Device: $DEVICE (${DEVICE_DESC[$DEVICE]})"

# ----------------------------------------------------------- [global] fields -

echo
echo "-- [global] section --"
STATUS="$(ask "Status multicast DNS name" "${NAME}.local")"
DATA_DEFAULT="$(ask "Default output data multicast DNS name (blank = each channel sets its own)" "${NAME}-pcm.local")"
DESCRIPTION="$(ask_desc "Front-end description (advertised via mDNS, <=63 chars, no '/')" "$NAME SDR")"
IFACE="$(ask "Network interface for multicast traffic (blank = default route)" "")"
TTL="$(ask_num "Multicast TTL (0 = stay on this LAN segment)" "0" "0" "255")"

echo
echo "$PRESETS_HELP"
GLOBAL_MODE="$(ask "Default demodulator preset for [global] (blank = set per-channel)" "")"

ADVANCED="$(ask_yn "Configure advanced [global] tuning (blocktime/overlap/fft-threads/encoding/...)" "n")"
declare -a GLOBAL_EXTRA=()
if [ "$ADVANCED" = "yes" ]; then
  BLOCKTIME="$(ask "blocktime ms (Opus-legal: 2.5,5,10,20,40,60,80,100,120)" "20")"
  OVERLAP="$(ask_num "overlap (FFT block overlap fraction, 1/N)" "5" "1" "")"
  FFT_THREADS="$(ask_num "fft-threads" "2" "0" "")"
  ENCODING="$(ask "Output encoding (opus, s16le, s16be, f32le, ...)" "opus")"
  [ -n "$BLOCKTIME" ] && GLOBAL_EXTRA+=("blocktime = $BLOCKTIME")
  [ -n "$OVERLAP" ] && GLOBAL_EXTRA+=("overlap = $OVERLAP")
  [ -n "$FFT_THREADS" ] && GLOBAL_EXTRA+=("fft-threads = $FFT_THREADS")
  [ -n "$ENCODING" ] && GLOBAL_EXTRA+=("encoding = $ENCODING")
  ask_extra_lines GLOBAL_EXTRA
fi

# --------------------------------------------------------- device-specific --

declare -a HW=()   # lines inside the [<device-section>] block

case "$DEVICE" in
  rtlsdr)
    SERIAL="$(ask "serial (blank = first device found; see rtl_eeprom)" "")"
    SAMPRATE_HZ="$(to_hz "$(ask "samprate (Hz or e.g. 2.4M)" "1800000")")" || SAMPRATE_HZ=1800000
    DIRECT="$(ask_num "direct_sampling (0=off, 1=I input, 2=Q input)" "0" "0" "2")"
    AGC="$(ask_yn "agc (hardware AGC)" "n")"
    BIAS="$(ask_yn "bias (bias-tee power for preamp)" "n")"
    GAIN="$(ask_num "gain dB (manual RF gain)" "0.0" "" "")"
    HW+=("device = rtlsdr" "serial = $SERIAL" "samprate = $SAMPRATE_HZ" \
         "direct_sampling = $DIRECT" "agc = $AGC" "bias = $BIAS" "gain = $GAIN")
    ;;
  hackrf)
    echo "    Note: upstream docs/SDR/hackrf.md only confirms device/serial/samprate;"
    echo "    other gain knobs vary by driver version -- use 'extra lines' below if needed."
    SERIAL="$(ask "serial (blank = first device found)" "")"
    SAMPRATE_HZ="$(to_hz "$(ask "samprate (Hz, up to ~20M)" "5000000")")" || SAMPRATE_HZ=5000000
    HW+=("device = hackrf" "serial = $SERIAL" "samprate = $SAMPRATE_HZ")
    ask_extra_lines HW
    ;;
  rx888)
    SERIAL="$(ask "serial (blank = first device found)" "")"
    SAMPRATE_HZ="$(to_hz "$(ask "samprate (Hz; default 64.8M, max 129.6M)" "64800000")")" || SAMPRATE_HZ=64800000
    GAIN="$(ask_num "gain dB (AD8370 analog VGA; aim for -20 to -25 dBFS at the A/D)" "10.0" "" "")"
    ATT="$(ask_num "att dB (PE4312 attenuator, 0-31.5 in 0.5 steps)" "0.0" "0" "31.5")"
    CAL="$(ask "calibrate (clock error fraction, e.g. -1e-6; blank = 0, experimental)" "0")"
    FIRMWARE="$(ask "firmware image (relative to /usr/local/share/ka9q-radio)" "SDDC_FX3.img")"
    QDEPTH="$(ask_num "queuedepth (USB transfer buffers)" "16" "1" "")"
    REQSIZE="$(ask_num "reqsize (buffer size, x16KB)" "32" "1" "")"
    DITHER="$(ask_yn "dither (LTC2208 dither)" "n")"
    RAND="$(ask_yn "rand (LTC2208 output randomization)" "n")"
    HW+=("device = rx888" "serial = $SERIAL" "samprate = $SAMPRATE_HZ" "gain = $GAIN" \
         "att = $ATT" "calibrate = $CAL" "firmware = $FIRMWARE" \
         "queuedepth = $QDEPTH" "reqsize = $REQSIZE" "dither = $DITHER" "rand = $RAND")
    ;;
  airspy)
    SERIAL="$(ask "serial, hex (blank = first device found; see airspy_info)" "")"
    SAMPRATE_HZ="$(to_hz "$(ask "samprate (Hz; default = highest advertised, usually 20M)" "20000000")")" || SAMPRATE_HZ=20000000
    LINEARITY="$(ask_yn "linearity (use linearity gain table instead of sensitivity table)" "n")"
    LNA_AGC="$(ask_yn "lna-agc (hardware LNA AGC; software AGC usually better)" "n")"
    MIXER_AGC="$(ask_yn "mixer-agc (hardware mixer AGC; software AGC usually better)" "n")"
    BIAS="$(ask_yn "bias (bias-tee power)" "n")"
    AGC_HI="$(ask_num "agc-high-threshold dBFS" "-10" "" "")"
    AGC_LO="$(ask_num "agc-low-threshold dBFS" "-40" "" "")"
    HW+=("device = airspy" "serial = $SERIAL" "samprate = $SAMPRATE_HZ" \
         "linearity = $LINEARITY" "lna-agc = $LNA_AGC" "mixer-agc = $MIXER_AGC" \
         "bias = $BIAS" "agc-high-threshold = $AGC_HI" "agc-low-threshold = $AGC_LO")
    if [ "$(ask_yn "Manually set lna-gain/mixer-gain/vga-gain/gainstep instead of AGC" "n")" = "yes" ]; then
      HW+=("lna-gain = $(ask_num "lna-gain (0-14, -1=auto)" "-1" "" "")")
      HW+=("mixer-gain = $(ask_num "mixer-gain (0-15, -1=auto)" "-1" "" "")")
      HW+=("vga-gain = $(ask_num "vga-gain (0-15, -1=auto)" "-1" "" "")")
      HW+=("gainstep = $(ask_num "gainstep (0-21, -1=auto)" "-1" "-1" "21")")
    fi
    ;;
  airspyhf)
    SERIAL="$(ask "serial, hex (blank = first device found; see airspyhf_info)" "")"
    echo "    Valid samprates: 912k 768k 456k 384k 256k 192k"
    echo "    (912k is the driver default but has been reported to drop USB data)"
    SAMPRATE_IN="$(ask "samprate" "768k")"
    SAMPRATE_HZ="$(to_hz "$SAMPRATE_IN")" || SAMPRATE_HZ=768000
    HF_AGC="$(ask_yn "hf-agc" "y")"
    HF_ATT="$(ask_yn "hf-att" "n")"
    HF_LNA="$(ask_yn "hf-lna" "n")"
    AGC_THRESH="$(ask_yn "agc-thresh" "n")"
    LIB_DSP="$(ask_yn "lib-dsp (library-corrected freq offset / I-Q imbalance)" "y")"
    HW+=("device = airspyhf" "serial = $SERIAL" "samprate = $SAMPRATE_HZ" \
         "hf-agc = $HF_AGC" "hf-att = $HF_ATT" "hf-lna = $HF_LNA" \
         "agc-thresh = $AGC_THRESH" "lib-dsp = $LIB_DSP")
    ;;
  sdrplay)
    echo "    Note: upstream docs/SDR/sdrplay.md is a stub; fields below come from"
    echo "    the project's own config/examples/radiod@sdrplay-generic.conf."
    SERIAL="$(ask "serial (blank = first device found)" "")"
    ANTENNA="$(ask "antenna (e.g. 'Antenna A', 'Antenna B', 'Antenna C' -- RSP-model dependent)" "")"
    SAMPRATE_HZ="$(to_hz "$(ask "samprate (Hz)" "2000000")")" || SAMPRATE_HZ=2000000
    LNA_STATE="$(ask_num "lna-state (RSP-model dependent index, e.g. 0-9)" "2" "0" "")"
    IF_AGC="$(ask_yn "if-agc" "y")"
    OVERLOAD="$(ask_num "overload-gr-interval (seconds)" "30" "0" "")"
    HW+=("device = sdrplay" "serial = $SERIAL")
    [ -n "$ANTENNA" ] && HW+=("antenna = $ANTENNA")
    HW+=("samprate = $SAMPRATE_HZ" "lna-state = $LNA_STATE" "if-agc = $IF_AGC" \
         "overload-gr-interval = $OVERLOAD")
    ask_extra_lines HW
    ;;
  bladerf)
    SERIAL="$(ask "serial (blank = first device found)" "")"
    SAMPRATE_HZ="$(to_hz "$(ask "samprate (Hz)" "12000000")")" || SAMPRATE_HZ=12000000
    BANDWIDTH="$(ask "bandwidth Hz (blank = 80% of samprate)" "")"
    GAIN="$(ask "gain (blank = automatic gain control)" "")"
    BIAS="$(ask_yn "bias (bias-tee power)" "n")"
    LINEARITY="$(ask_yn "linearity (linearity vs sensitivity gain table)" "y")"
    LNA_AGC="$(ask_yn "lna-agc" "n")"
    MIXER_AGC="$(ask_yn "mixer-agc" "n")"
    HW+=("device = bladerf" "serial = $SERIAL" "samprate = $SAMPRATE_HZ")
    [ -n "$BANDWIDTH" ] && HW+=("bandwidth = $BANDWIDTH")
    [ -n "$GAIN" ] && HW+=("gain = $GAIN")
    HW+=("bias = $BIAS" "linearity = $LINEARITY" "lna-agc = $LNA_AGC" "mixer-agc = $MIXER_AGC")
    ;;
  fobos)
    SERIAL="$(ask "serial (blank = first device found)" "")"
    SAMPRATE_HZ="$(to_hz "$(ask "samprate (Hz; default = highest advertised, usually 80M)" "80000000")")" || SAMPRATE_HZ=80000000
    CLK_SRC="$(ask_num "clk_source (0=internal, 1=external CLKIN, untested)" "0" "0" "1")"
    DIRECT="$(ask_yn "direct_sampling (HF1/HF2 direct sampling instead of RF input)" "n")"
    HF_INPUT="$(ask_num "hf_input in direct sampling mode (0=I/Q, 1=HF1, 2=HF2)" "0" "0" "2")"
    LNA_GAIN="$(ask_num "lna_gain (0/1=0dB, 2=+16dB, 3=+33dB; ignored in direct sampling)" "0" "0" "3")"
    VGA_GAIN="$(ask_num "vga_gain (0-62 dB in 2dB steps; ignored in direct sampling)" "0" "0" "62")"
    HW+=("device = fobos" "serial = $SERIAL" "samprate = $SAMPRATE_HZ" \
         "clk_source = $CLK_SRC" "direct_sampling = $DIRECT" "hf_input = $HF_INPUT" \
         "lna_gain = $LNA_GAIN" "vga_gain = $VGA_GAIN")
    ;;
  hydrasdr)
    SERIAL="$(ask "serial (blank = first device found)" "")"
    SAMPRATE_HZ="$(to_hz "$(ask "samprate (Hz; default = highest advertised, ~20M)" "20000000")")" || SAMPRATE_HZ=20000000
    LINEARITY="$(ask_yn "linearity (linearity vs sensitivity gain table)" "n")"
    LNA_AGC="$(ask_yn "lna-agc" "y")"
    MIXER_AGC="$(ask_yn "mixer-agc" "y")"
    AGC_HI="$(ask_num "agc-high-threshold dBFS" "-20" "" "")"
    AGC_LO="$(ask_num "agc-low-threshold dBFS" "-30" "" "")"
    HW+=("device = hydrasdr" "serial = $SERIAL" "samprate = $SAMPRATE_HZ" \
         "linearity = $LINEARITY" "lna-agc = $LNA_AGC" "mixer-agc = $MIXER_AGC" \
         "agc-high-threshold = $AGC_HI" "agc-low-threshold = $AGC_LO")
    ;;
  funcube)
    echo "    Note: upstream docs call the FUNcube driver 'very old, untested'."
    NUMBER="$(ask_num "number (device index)" "0" "0" "")"
    HW+=("device = funcube" "number = $NUMBER")
    ;;
  *) die "Internal error: unhandled device $DEVICE" ;;
esac

# ----------------------------------------------------------------- channels --

echo
echo "-- Receiver channels --"
echo "Each channel group becomes its own [SectionName] block: a shared mode"
echo "and output stream, tuned to one or more frequencies."
echo "$PRESETS_HELP"

declare -a CHANNEL_BLOCKS=()   # each entry: "SectionName\nline1\nline2\n..."

while true; do
  ADD="$(ask_yn "Add a receiver channel group" "y")"
  [ "$ADD" = "no" ] && break

  while true; do
    CHNAME="$(ask "  Section name (e.g. FM, WSPR, TWOMETER)" "")"
    [[ "$CHNAME" =~ ^[A-Za-z0-9_-]+$ ]] && [ -n "$CHNAME" ] && break
    echo "    Use only letters, digits, '-' and '_'." >&2
  done

  CHMODE="$(ask "  mode/preset (blank = use [global] default: '${GLOBAL_MODE:-none set}')" "")"
  CHDATA="$(ask "  data multicast DNS name (blank = use [global] default: '${DATA_DEFAULT:-none set}')" "")"

  FREQ_IN="$(ask "  Frequency/frequencies (comma-separated, e.g. 14074000,7074000 or 88.3M)" "")"
  declare -a FREQ_HZ=()
  IFS=',' read -ra RAW_FREQS <<< "$FREQ_IN"
  for f in "${RAW_FREQS[@]}"; do
    f="$(echo "$f" | tr -d '[:space:]')"
    [ -z "$f" ] && continue
    hz="$(to_hz "$f")" || { echo "    Skipping unparseable frequency '$f'." >&2; continue; }
    FREQ_HZ+=("$hz")
  done

  CHANNELS_N="$(ask "  channels (1=mono, 2=stereo; blank = mode default)" "")"
  DISABLE="$(ask_yn "  Start this group disabled (disable = y)" "n")"

  BLOCK="[$CHNAME]"
  [ -n "$CHMODE" ] && BLOCK+=$'\n'"mode = $CHMODE"
  [ -n "$CHDATA" ] && BLOCK+=$'\n'"data = $CHDATA"
  if [ "${#FREQ_HZ[@]}" -eq 1 ]; then
    BLOCK+=$'\n'"freq = ${FREQ_HZ[0]}"
  elif [ "${#FREQ_HZ[@]}" -gt 1 ]; then
    joined="$(printf '%s ' "${FREQ_HZ[@]}")"
    BLOCK+=$'\n'"freq = \"${joined% }\""
  fi
  [ -n "$CHANNELS_N" ] && BLOCK+=$'\n'"channels = $CHANNELS_N"
  [ "$DISABLE" = "yes" ] && BLOCK+=$'\n'"disable = y"

  declare -a CHEXTRA=()
  ask_extra_lines CHEXTRA
  for l in "${CHEXTRA[@]}"; do BLOCK+=$'\n'"$l"; done
  unset CHEXTRA FREQ_HZ

  CHANNEL_BLOCKS+=("$BLOCK")
done

# ------------------------------------------------------------------- render --

render() {
  echo "# Generated by $SCRIPT_NAME on $(date -Is)"
  echo "# ka9q-radio config for instance '$NAME' -- https://github.com/ka9q/ka9q-radio"
  echo "# Sections in this file are concatenated in order and interpreted as one"
  echo "# radiod configuration. See docs/ka9q-radio.md and docs/SDR/${DEVICE}.md"
  echo "# upstream for the authoritative field list."
  echo
  echo "[global]"
  echo "hardware = $DEVICE"
  echo "status = $STATUS"
  [ -n "$DATA_DEFAULT" ] && echo "data = $DATA_DEFAULT"
  echo "description = \"$DESCRIPTION\""
  [ -n "$IFACE" ] && echo "iface = $IFACE"
  echo "ttl = $TTL"
  [ -n "$GLOBAL_MODE" ] && echo "mode = $GLOBAL_MODE"
  for l in "${GLOBAL_EXTRA[@]:-}"; do [ -n "$l" ] && echo "$l"; done
  echo
  echo "[$DEVICE]"
  for l in "${HW[@]}"; do
    # Drop only our own "key = " lines left with an empty value (unset
    # optional field). Anything else -- comments, free-form extra lines --
    # is emitted verbatim even if it has no "key = value" shape.
    if [[ "$l" =~ ^[^=]+=[[:space:]]*$ ]]; then
      continue
    fi
    echo "$l"
  done
  for block in "${CHANNEL_BLOCKS[@]:-}"; do
    [ -z "$block" ] && continue
    echo
    echo "$block"
  done
}

OUTPUT="$(render)"

echo
echo "===================================================================="
echo "Preview: $CONF_FILE"
echo "===================================================================="
echo "$OUTPUT"
echo "===================================================================="

SAVE="$(ask_yn "Save this file" "y")"
[ "$SAVE" = "no" ] && { info "Discarded, nothing written."; exit 0; }

if [ "$INSTALL" -eq 1 ]; then
  DEST="/etc/radio/$CONF_FILE"
  info "Installing to $DEST (requires sudo)..."
  sudo mkdir -p /etc/radio
  printf '%s\n' "$OUTPUT" | sudo tee "$DEST" > /dev/null
  sudo systemctl daemon-reload
  info "Wrote $DEST"
  if [ "$(ask_yn "Enable and start radiod@$NAME now" "n")" = "yes" ]; then
    sudo systemctl enable --now "radiod@${NAME}"
    info "radiod@${NAME} enabled and started. Check: systemctl status radiod@${NAME}"
  else
    echo "    Later: sudo systemctl enable --now radiod@${NAME}"
  fi
else
  mkdir -p "$OUT_DIR" 2>/dev/null || true
  DEST="$OUT_DIR/$CONF_FILE"
  if printf '%s\n' "$OUTPUT" > "$DEST" 2>/dev/null; then
    info "Wrote $DEST"
  else
    info "No write permission for $OUT_DIR -- writing to /etc/radio via sudo instead."
    sudo mkdir -p /etc/radio
    printf '%s\n' "$OUTPUT" | sudo tee "/etc/radio/$CONF_FILE" > /dev/null
    DEST="/etc/radio/$CONF_FILE"
    info "Wrote $DEST"
  fi
  echo "    To activate: sudo systemctl daemon-reload && sudo systemctl enable --now radiod@${NAME}"
fi
