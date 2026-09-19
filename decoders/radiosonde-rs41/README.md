# radiosonde-rs41

Feeds a `radiod` FM channel tuned to an active radiosonde into
`packages/pkg_radiosonde`'s `rs41dm_dft` for telemetry decode (position,
altitude, and the rest of the frame `rs41dm_dft` prints per line).

## How it's different from hackrf-aprs-direwolf

Same gap as `freedv-hf`: no SIGedge reference mission demodulates
400-406 MHz, and *which* frequency has a sonde on it right now is a
local, time-bound fact (which launch site, which flight, updated
constantly) — not a stable default this project can check in. Check
[sondehub.org](https://sondehub.org) or [radiosondy.info](https://radiosondy.info)
for what's actually in the air near you before picking a frequency.

## Prerequisites

1. **A `radiod` channel demodulating FM on a radiosonde frequency.** Add
   one with `scripts/cfg_ka9q-radio_tui` (see
   [scripts/README.md](../../scripts/README.md)) —
   `cfg_ka9q-radio` itself only regenerates the three fixed reference
   templates and none of them is a 400-406 MHz mission.

2. **`rs41dm_dft` must actually be installed.** `pkg_radiosonde` is not
   part of `scripts/setup_decoders` today (it's commented out there),
   so it needs installing explicitly:

   ```bash
   source packages/pkg_radiosonde install
   command -v rs41dm_dft
   ```

   **Heads-up:** this host already has a *different* radiosonde decoder
   set installed system-wide — the `sonde-decoders` apt package
   (`rs41mod`, `dfm09mod`, `m10mod`, ...), from a newer, more actively
   maintained `auto_rx` fork of the same rs1729/RS lineage. `pkg_radiosonde`
   builds the older, standalone `_dft` tools (`rs41dm_dft`, `dfm09dm_dft`,
   `m10dm_dft`, `rs92dm_dft`, `lms6dm_dft`) directly from source instead.
   This bridge targets `pkg_radiosonde`'s own build because that's the
   package actually reviewed in `packages/` — but if `sonde-decoders` is
   already on your host and kept up to date, pointing `RS_DECODER` at
   `rs41mod` instead (same stdin convention, per that fork's own docs) is
   a reasonable swap; check its `--help` output before assuming the
   arguments line up exactly with `rs41dm_dft`'s.

3. **Confirm the channel's actual audio sample rate once** (same caveat
   as the other bridges):

   ```bash
   pcmrecord <data-group>   # Ctrl-C after a few seconds
   soxi *.wav
   ```

   `run.sh` defaults to 12000 Hz and resamples to the 48000 Hz the
   `demod_dft` family conventionally expects, via `sox`, wrapped in a WAV
   header rather than headerless raw — every rs1729/RS usage guide pipes
   `sox`'s WAV output into these tools rather than raw samples, since they
   read format/rate from the header. Verify `rs41dm_dft`'s actual argument
   convention (`-` for stdin is this bridge's assumption, not a confirmed
   fact for this exact build) before relying on it unattended.

4. **Know which sonde type is on the frequency.** `rs41dm_dft` (Vaisala
   RS41, this bridge's default) covers the most common type in service
   globally, but not the only one. `pkg_radiosonde` also builds
   `dft_detect`/`rs_detect` specifically to identify what's actually
   transmitting — run one of those against a short capture first if
   decode comes back empty, and set `RS_DECODER` to the matching binary
   (`dfm09dm_dft`, `m10dm_dft`, `rs92dm_dft`, `lms6dm_dft`).

## Running it

```bash
RS_DATA_GROUP=239.192.64.XX \
RS_CHANNEL_RATE=12000 \
RS_DECODER=rs41dm_dft \
  decoders/radiosonde-rs41/run.sh
```

`RS_DATA_GROUP` has **no default** and the script refuses to run without
it. `RS_LOG_FILE`, if set, additionally appends every decoded line to that
path (`tee`) alongside stdout.

## Not included here

No systemd unit — a sonde flight lasts on the order of two hours and the
frequency/type changes flight to flight, so this is an attended,
per-launch activity rather than a standing daemon. Wrap `run.sh` in your
own unit if your site tracks a fixed, recurring launch schedule on a fixed
frequency.
