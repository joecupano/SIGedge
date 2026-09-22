#!/bin/bash

###
### SIGedge
###
### decoders/freedv-hf/run.sh
###
### Bridges a radiod HF USB channel's demodulated audio into codec2's
### freedv_rx for FreeDV digital voice decoding.
###
### Unlike hackrf-aprs-direwolf, there is no existing SIGedge reference
### mission this rides on -- none of the three reference missions
### (rx888-wwv/hackrf-aprs/rtlsdr-simplex) demodulate USB, and FreeDV's
### calling frequency is an HF band choice, not something this project can
### default for you. You must create that channel yourself first --
### scripts/ka9q-radio-builder (see its README for why: cfg_ka9q-radio
### itself only ever regenerates the three fixed reference templates).
### 14.236 MHz USB is the commonly used international FreeDV calling
### frequency and a reasonable starting point on an RX-888/HF front end.
###
### Pipeline:
###   pcmrecord --stdout --raw <data-group>   -- radiod channel audio, at
###   whatever rate that channel actually outputs (CHANNEL_RATE below).
###     |
###   sox ... rate 8000                        -- freedv_rx's HF modem
###   modes expect 8000 Hz 16-bit signed mono input; resample to that
###   regardless of the channel's native rate.
###     |
###   freedv_rx <mode> - -                     -- decodes FreeDV to raw
###   8000 Hz 16-bit signed mono speech on stdout.
###     |
###   aplay / sox ...                          -- play or save the result
###   (AUDIO_OUT below).
###
### freedv_rx ships from codec2's own source build (packages/pkg_codec2
### build, drowe67/codec2 v1.20) -- NOT the Ubuntu-archive `codec2` apt
### package, which only provides c2enc/c2dec/fdmdv_*/fsk_mod and has no
### freedv_rx at all. Confirm before relying on this:
###
###   command -v freedv_rx || echo "run: source packages/pkg_codec2 build"
###

set -euo pipefail

DATA_GROUP="${FREEDV_DATA_GROUP:?Set FREEDV_DATA_GROUP to the radiod channel multicast data address -- see this bridge README; no default exists, unlike hackrf-aprs-direwolf}"

# radiod doesn't expose a channel's output rate on the raw stream itself --
# verify once with a plain (non-raw) capture before trusting this default:
#   pcmrecord "$DATA_GROUP"; soxi *.wav
CHANNEL_RATE="${FREEDV_CHANNEL_RATE:-12000}"

# One of codec2's FreeDV modes: 1600, 700C, 700D, 700E, 800XA, 2400A,
# 2400B, FSK_LDPC -- see `freedv_rx` run with no arguments for the current
# list and which one matches what's actually being transmitted.
MODE="${FREEDV_MODE:-1600}"

# "aplay" to listen live (requires a working ALSA output on this host),
# or a file path (e.g. /tmp/freedv-out.wav) to sox it to disk instead.
AUDIO_OUT="${FREEDV_AUDIO_OUT:-aplay}"

for bin in pcmrecord sox freedv_rx; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "ERROR: $bin not found in PATH" >&2
        exit 1
    fi
done

echo "Bridging radiod data group $DATA_GROUP (${CHANNEL_RATE} Hz) -> freedv_rx mode $MODE -> $AUDIO_OUT" >&2

decoded_pcm() {
    pcmrecord --stdout --raw "$DATA_GROUP" \
        | sox -t raw -r "$CHANNEL_RATE" -e signed -b 16 -c 1 - \
              -t raw -r 8000 -e signed -b 16 -c 1 - \
        | freedv_rx "$MODE" - -
}

if [[ "$AUDIO_OUT" == "aplay" ]]; then
    decoded_pcm | aplay -t raw -r 8000 -e signed -f S16_LE -c 1 -
else
    decoded_pcm | sox -t raw -r 8000 -e signed -b 16 -c 1 - "$AUDIO_OUT"
fi
