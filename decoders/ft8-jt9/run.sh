#!/bin/bash

###
### SIGedge
###
### decoders/ft8-jt9/run.sh
###
### Wraps ka9q-radio-tools' own jt-decoded -- unlike every other bridge in
### decoders/, this is NOT a pcmrecord|sox|<tool> pipe. jt-decoded is a
### native ka9q-radio client: it joins the channel's multicast group
### itself and manages its own short-lived .wav captures, handing each one
### to WSJT-X's jt9 (or, for WSPR, presumably wsprd -- see MODE_FLAG below)
### for decode. This script only supplies sane defaults and a place to
### document what upstream's man page doesn't (see README.md).
###
### Usage (from `jt-decoded` with no/bad args):
###   jt-decoded [-L locale] [-v] [-k] [-d recording_dir]
###              [-x <PATH_TO_JT9>] [-4|-8|-w] PCM_multicast_address
###

set -euo pipefail

DATA_GROUP="${FT8_DATA_GROUP:?Set FT8_DATA_GROUP to the radiod channel multicast data address -- see README.md; no reference mission demodulates USB today, same gap as freedv-hf/radiosonde-rs41}"

# -4 FT4, -8 FT8, -w WSPR -- see README.md's "What -4/-8/-w actually do"
# for why this is inference from the usage line, not a confirmed fact.
# FT8 (-8) is the best-understood and most commonly run 24/7 of the three.
MODE_FLAG="${FT8_MODE_FLAG:--8}"

# Where jt-decoded stores its working .wav captures. Persists across runs
# unless -k (below) says otherwise; put it somewhere with room to spare if
# left running unattended for a while.
RECORDING_DIR="${FT8_RECORDING_DIR:-$HOME/ft8-jt9-recordings}"

JT9_PATH="${FT8_JT9_PATH:-$(command -v jt9 || true)}"

# 1 = pass -k (keep decoded .wav files instead of deleting them -- useful
# while you're still confirming this actually decodes anything; verbose
# inference, see README.md). 0 = omit -k, the default once it's working.
KEEP_WAV="${FT8_KEEP_WAV:-1}"

if ! command -v jt-decoded >/dev/null 2>&1; then
    echo "ERROR: jt-decoded not found -- install ka9q-radio-tools (packages/pkg_ka9q-radio)" >&2
    exit 1
fi

if [[ -z "$JT9_PATH" ]]; then
    echo "ERROR: jt9 not found -- install wsjtx (provides /usr/bin/jt9)" >&2
    exit 1
fi

mkdir -p "$RECORDING_DIR"

args=(-d "$RECORDING_DIR" -x "$JT9_PATH" "$MODE_FLAG")
[[ "$KEEP_WAV" == "1" ]] && args+=(-k)
args+=("$DATA_GROUP")

echo "jt-decoded ${args[*]}" >&2
exec jt-decoded "${args[@]}"
