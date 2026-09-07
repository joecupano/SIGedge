#!/bin/bash

###
### SIGedge
###
### decoders/radiosonde-rs41/run.sh
###
### Bridges a radiod FM channel tuned to an active radiosonde into
### rs1729/RS's rs41dm_dft (packages/pkg_radiosonde) for telemetry decode.
###
### Same caveat as freedv-hf: no SIGedge reference mission demodulates
### 400-406 MHz, and which frequency actually has a sonde on it is a
### local/temporal fact (which launch site, which flight), not something
### this project can default -- see this bridge's README.
###
### Pipeline:
###   pcmrecord --stdout --raw <data-group>   -- radiod channel audio, at
###   whatever rate that channel actually outputs (CHANNEL_RATE below).
###     |
###   sox ... rate 48000                       -- the demod_dft tool
###   family (rs41dm_dft and siblings) expects 48000 Hz 16-bit signed mono
###   input, the long-standing convention in radiosonde decoding guides;
###   resample to that regardless of the channel's native rate.
###     |
###   rs41dm_dft                                -- prints one decoded
###   telemetry line per frame to stdout (position, altitude, etc.).
###
### RS_DECODER selects which of pkg_radiosonde's demod_dft binaries to
### run -- rs41dm_dft (Vaisala RS41, the current default; the most common
### sonde in service globally) is the default here. If dft_detect/
### rs_detect (also built by pkg_radiosonde) identifies a different type
### on your frequency, override RS_DECODER accordingly:
###   dfm09dm_dft (DFM06/DFM09), m10dm_dft (M10/M20), rs92dm_dft (RS92),
###   lms6dm_dft (LMS6).
###
### Note: this host already has a *different*, newer decoder set
### installed system-wide -- the `sonde-decoders` apt package (rs41mod,
### dfm09mod, m10mod, ...), from a more actively maintained auto_rx fork.
### This bridge targets pkg_radiosonde's own build specifically, per what
### was reviewed in packages/. See this bridge's README for the tradeoff.
###

set -euo pipefail

DATA_GROUP="${RS_DATA_GROUP:?Set RS_DATA_GROUP to the radiod channel's multicast data address (see this bridge's README -- no default exists, unlike hackrf-aprs-direwolf)}"

# Verify once with a plain (non-raw) capture before trusting this default
# -- see freedv-hf/README.md's identical caveat.
CHANNEL_RATE="${RS_CHANNEL_RATE:-12000}"

RS_DECODER="${RS_DECODER:-rs41dm_dft}"

# Where decoded telemetry lines go, in addition to stdout. Empty = stdout only.
LOG_FILE="${RS_LOG_FILE:-}"

for bin in pcmrecord sox "$RS_DECODER"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "ERROR: $bin not found in PATH -- install via: source packages/pkg_radiosonde install" >&2
        exit 1
    fi
done

echo "Bridging radiod data group $DATA_GROUP (${CHANNEL_RATE} Hz) -> $RS_DECODER" >&2

decoded() {
    # WAV on stdout, not headerless raw: the demod_dft tools take a
    # self-describing file (sample rate/format read from the WAV header)
    # rather than assuming a fixed raw layout -- the same convention every
    # rs1729/RS usage guide pipes rtl_fm/sox into. "-" as the positional
    # argument is that family's stdin convention; verify against your
    # actual build (see this bridge's README) if it doesn't behave as
    # expected.
    pcmrecord --stdout --raw "$DATA_GROUP" \
        | sox -t raw -r "$CHANNEL_RATE" -e signed -b 16 -c 1 - \
              -t wav -r 48000 -e signed -b 16 -c 1 - \
        | "$RS_DECODER" -
}

if [[ -n "$LOG_FILE" ]]; then
    decoded | tee -a "$LOG_FILE"
else
    decoded
fi
