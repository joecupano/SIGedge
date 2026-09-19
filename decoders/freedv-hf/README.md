# freedv-hf

Feeds a `radiod` HF USB channel's audio into `codec2`'s `freedv_rx` for
FreeDV digital voice decoding.

## How it's different from hackrf-aprs-direwolf

`hackrf-aprs-direwolf` rides an existing, already-configured reference
mission (`radiod@hackrf-aprs`, FM, APRS 144.390 MHz) — the channel it
needs already exists. **No SIGedge reference mission demodulates USB**,
and FreeDV's operating frequency is a real choice (which HF band, which
FreeDV mode is actually in use there), not something this project can
default the way `mode = fm` on 144.390 MHz APRS could. You have to create
that channel yourself before this bridge has anything to decode.

## Prerequisites

1. **A `radiod` channel demodulating USB on an HF frequency carrying
   FreeDV traffic.** Use `scripts/cfg_ka9q-radio_tui` to add one — it's
   the tool for missions beyond the three fixed reference templates (see
   [scripts/README.md](../../scripts/README.md) for
   why `cfg_ka9q-radio` itself can't do this). **14.236 MHz USB** is the
   commonly used international FreeDV calling frequency and a reasonable
   starting point on an HF-capable front end (RX-888); it's a convention,
   not a guarantee anyone is transmitting there when you listen.

2. **`freedv_rx` must actually be built.** The Ubuntu-archive `codec2`
   apt package (visible as just `codec2` in `dpkg -l` on a stock system)
   only ships `c2enc`/`c2dec`/`fdmdv_*`/`fsk_mod` — no `freedv_rx`. Build
   codec2 from source instead, which is what `packages/pkg_codec2`
   already does (drowe67/codec2 v1.20):

   ```bash
   source packages/pkg_codec2 build
   command -v freedv_rx   # should resolve; if not, the build above failed
   ```

3. **Confirm the channel's actual audio sample rate once** (same caveat
   as hackrf-aprs-direwolf — `radiod` doesn't expose it on the raw
   stream):

   ```bash
   pcmrecord <data-group>   # Ctrl-C after a few seconds
   soxi *.wav
   ```

   `run.sh` defaults to 12000 Hz; set `FREEDV_CHANNEL_RATE` if your
   capture reports something else. This bridge resamples to the 8000 Hz
   `freedv_rx`'s HF modem modes actually require, via `sox` — unlike
   direwolf, `freedv_rx` has no "tell me the input rate" flag, so getting
   this wrong produces silence/garbage rather than a clean decode failure.

4. **Know which FreeDV mode is in use.** `1600` is the long-standing
   default and this bridge's default; `700C`/`700D`/`700E`/`800XA`/
   `2400A`/`2400B`/`FSK_LDPC` are the other options `freedv_rx` supports.
   Run `freedv_rx` with no arguments to see the current list from the
   build you actually have.

## Running it

```bash
FREEDV_DATA_GROUP=239.192.64.XX \
FREEDV_CHANNEL_RATE=12000 \
FREEDV_MODE=1600 \
  decoders/freedv-hf/run.sh
```

`FREEDV_DATA_GROUP` has **no default** (unlike `hackrf-aprs-direwolf`,
there's no reference mission to assume) and the script refuses to run
without it.

`FREEDV_AUDIO_OUT` controls where decoded speech goes: `aplay` (default,
plays live over this host's audio output) or a file path, written via
`sox` (e.g. `FREEDV_AUDIO_OUT=/tmp/freedv-out.wav`).

## Not included here

No systemd unit — unlike `hackrf-aprs-direwolf`'s always-on APRS digipeat
monitoring, FreeDV reception is normally an attended, pick-a-band-and-
listen activity. Wrap `run.sh` in your own unit (same shape as
`hackrf-aprs-direwolf.service`, with `FREEDV_DATA_GROUP` etc. set via
`Environment=`) if you want it standing.
