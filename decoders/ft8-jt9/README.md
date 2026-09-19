# ft8-jt9

Decodes FT8 (or FT4/WSPR) off a `radiod` USB channel using ka9q-radio's
own `jt-decoded`, backed by WSJT-X's `jt9`.

## How this differs from every other bridge here

Every other decoder in `decoders/` is a shell pipeline —
`pcmrecord --stdout --raw | sox | <decoder>`. This one isn't: `jt-decoded`
(shipped in `ka9q-radio-tools`, already installed on this host) is a
**native ka9q-radio client** that joins the channel's multicast group
itself and manages its own short `.wav` captures, handing each to `jt9`
for decode. `run.sh` here is a thin wrapper supplying defaults, not a
pipe.

```text
radiod@<mission> --RTP/multicast--> jt-decoded --<wav captures>--> jt9 --> decoded text
```

## Prerequisites

1. **A `radiod` channel demodulating USB on an FT8 (or FT4/WSPR)
   frequency.** Same gap as `freedv-hf`/`radiosonde-rs41` — no reference
   mission covers this; add one with `scripts/cfg_ka9q-radio_tui` (see
   [scripts/README.md](../../scripts/README.md)).
   **14.074 MHz USB** is the universally used 20m FT8 dial frequency and
   the standard starting point — unlike FreeDV's "commonly used" calling
   frequency, this one is a fixed, near-universal convention across the
   FT8 user base.

2. **`jt-decoded` and `jt9` must both be present.** Confirmed already
   true on this host:

   ```bash
   command -v jt-decoded   # ka9q-radio-tools
   command -v jt9          # wsjtx / wsjtx-data
   ```

   If either is missing: `source packages/pkg_ka9q-radio install` (for
   `jt-decoded`) or `sudo apt-get install wsjtx` (for `jt9`).

## What `-4`/`-8`/`-w` actually do — read before trusting this

`jt-decoded`'s own man page is a content-free stub (`"jt-decoded ... does
something"` — verbatim, this is not a paraphrase), and `--help`/`-h`
aren't recognized options, so everything below the usage line itself is
**inference, not confirmed behavior**:

- `-8` (FT8) and `-4` (FT4) are presumably passed straight to `jt9`, which
  does handle both natively (confirmed: `jt9`'s own `--help` lists
  `-p SECONDS`/`--tr-period`, consistent with FT8/FT4's fixed Tx/Rx
  cycles).
- `-w` (presumably WSPR) is less certain: WSPR has historically been
  decoded by a *separate* binary, `wsprd` (also installed on this host,
  confirmed via `wsprd` with no args printing its own usage), not `jt9`.
  `jt-decoded` only exposes `-x <PATH_TO_JT9>` to override the decoder
  path — there's no equivalent flag for a `wsprd` path — so either `-w`
  still shells out to `jt9` (which may or may not decode WSPR in this
  WSJT-X build), or `jt-decoded` finds `wsprd` on `$PATH` internally.
  **Verify WSPR mode actually produces decodes before relying on it**;
  `run.sh` defaults to `-8` (FT8) precisely because that path is the
  best-understood of the three.

Similarly unconfirmed: where decoded *text* actually appears. `-d
recording_dir` clearly controls where the working `.wav` captures go
(`run.sh` defaults this to `~/ft8-jt9-recordings`), and `-k` presumably
keeps those `.wav` files instead of deleting them after decode — but
whether decoded message text prints to stdout, gets written into
`recording_dir` alongside the `.wav`s, or both, isn't documented anywhere
this review could find. **Check both places** the first time you run
this.

## Running it

```bash
FT8_DATA_GROUP=239.192.64.XX \
  decoders/ft8-jt9/run.sh
```

`FT8_DATA_GROUP` has **no default** and the script refuses to run without
it — same convention as `freedv-hf`/`radiosonde-rs41`.

| Variable | Purpose | Default |
|---|---|---|
| `FT8_DATA_GROUP` | Multicast data group to read (required) | none |
| `FT8_MODE_FLAG` | `-8` (FT8) / `-4` (FT4) / `-w` (WSPR, unverified — see above) | `-8` |
| `FT8_RECORDING_DIR` | Where `jt-decoded` stores its `.wav` captures | `~/ft8-jt9-recordings` |
| `FT8_JT9_PATH` | Path to `jt9` | auto-detected via `PATH` |
| `FT8_KEEP_WAV` | `1` passes `-k` (keep captures — useful while confirming this decodes anything); `0` omits it | `1` |

## Installing as a service

FT8 monitoring is normally run continuously, unlike `freedv-hf`/
`radiosonde-rs41`'s attended, pick-a-session use — so this one does ship
a systemd unit, disabled by default like every other service in this
project:

```bash
sudo cp decoders/ft8-jt9/ft8-jt9.service /etc/systemd/system/
# Fill in @radiod_service@, @decoder_user@, @sigedge_home@, and
# @ft8_data_group@ in that copy first -- see the unit file's own comments.
sudo systemctl daemon-reload
sudo systemctl enable --now ft8-jt9.service
```
