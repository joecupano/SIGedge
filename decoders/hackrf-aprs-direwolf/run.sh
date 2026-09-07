#!/bin/bash

###
### SIGedge
###
### decoders/hackrf-aprs-direwolf/run.sh
###
### Bridges radiod@hackrf-aprs's demodulated FM audio (APRS 144.390 MHz,
### data group 239.192.64.20 -- see NETWORKING.md's "Current static
### assignment" table) into direwolf for AX.25/APRS decoding.
###
### Pipeline:
###   pcmrecord --stdout --raw <data-group>  -- joins the multicast group
###   and writes raw 16-bit signed PCM to stdout instead of a .wav file
###   (see `man pcmrecord`; ka9q-radio-tools).
###     |
###   direwolf -c <conf> -n 1 -r <rate> -b 16 -t 0 -  -- decodes 1200 baud
###   AFSK from raw PCM on stdin (see `man direwolf`'s "-" stdin example,
###   the same pattern documented there for `rtl_fm | direwolf`).
###
### This script does not daemonize or restart itself -- that is
### hackrf-aprs-direwolf.service's job (Restart=on-failure). Run directly
### for a one-off test; install the unit for anything long-running.
###

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# 239.192.64.20 is radiod@hackrf-aprs's fixed data address (config/
# radiod@hackrf-aprs.conf, NETWORKING.md). Override only if that mission's
# template has been re-pointed at a different address.
DATA_GROUP="${HACKRF_APRS_DATA_GROUP:-239.192.64.20}"

# radiod does not publish a channel's actual output sample rate anywhere
# pcmrecord's raw mode can report at stream time -- verify it once before
# relying on this default:
#
#   pcmrecord "$DATA_GROUP"            # Ctrl-C after a few seconds
#   soxi *.wav                         # or: ffprobe / `file` on the .wav
#
# and set HACKRF_APRS_AUDIO_RATE to whatever that reports if it isn't
# 12000. Getting this wrong doesn't crash direwolf, it just quietly fails
# to decode anything, because AFSK tone detection is rate-dependent.
AUDIO_RATE="${HACKRF_APRS_AUDIO_RATE:-12000}"

DIREWOLF_CONF="${HACKRF_APRS_DIREWOLF_CONF:-$HERE/direwolf-aprs.conf}"

if ! command -v pcmrecord >/dev/null 2>&1; then
    echo "ERROR: pcmrecord not found -- install ka9q-radio-tools (packages/pkg_ka9q-radio)" >&2
    exit 1
fi

if ! command -v direwolf >/dev/null 2>&1; then
    echo "ERROR: direwolf not found -- install it (packages/pkg_direwolf / scripts/setup_decoders)" >&2
    exit 1
fi

echo "Bridging radiod data group $DATA_GROUP -> direwolf (rate=${AUDIO_RATE}, conf=$DIREWOLF_CONF)" >&2

exec pcmrecord --stdout --raw "$DATA_GROUP" \
    | direwolf -c "$DIREWOLF_CONF" -n 1 -r "$AUDIO_RATE" -b 16 -t 0 -
