# hackrf-aprs-direwolf

Feeds `radiod@hackrf-aprs`'s demodulated FM audio into `direwolf` for
AX.25/APRS decoding, instead of leaving that multicast group unread. See
the top-level README's [ka9q-radio section](../../README.md#ka9q-radio-shared-radio-server)
for the "decoders" branch this fills in.

## How it works

```text
radiod@hackrf-aprs  --RTP/multicast-->  pcmrecord --stdout --raw  --pipe-->  direwolf -
     (239.192.64.20)                     (ka9q-radio-tools)                  (AX.25/APRS)
```

`pcmrecord` (shipped in `ka9q-radio-tools`, confirmed installed via
`ka9q-radio-tools_*.deb`) joins the channel's data multicast group and
writes raw 16-bit PCM to stdout instead of a `.wav` file. `direwolf`
reads raw PCM from stdin when given `-` as its audio device -- the same
pattern its own man page documents for `rtl_fm | direwolf`.

## Prerequisites

1. **`radiod@hackrf-aprs` must actually be running.** This bridge only
   has something to decode once the HackRF is assigned to the mission --
   see [KA9Q-DEPLOYMENT.md](../../KA9Q-DEPLOYMENT.md) §5:

   ```bash
   SIGedge assign hackrf radiod:hackrf-aprs
   SIGedge inventory                         # HackRF: assigned to radiod hackrf-aprs
   ```

2. **`direwolf` must actually run on this host.** The prebuilt
   `debs/direwolf_current_amd64.deb` used to be linked against
   `libgps.so.28`, which Ubuntu 24.04 doesn't ship (its `libgps30t64`
   provides only `libgps.so.30`), so the installed binary failed
   immediately:

   ```
   direwolf: error while loading shared libraries: libgps.so.28: cannot open shared object file
   ```

   As of 2026-09-30 the amd64 package is rebuilt on Ubuntu 24.04, and
   `packages/pkg_direwolf package` now records the libraries it links
   against as package `Depends`, so a mismatched `.deb` is refused by
   `dpkg -i` instead of installing a binary that can't load. A host that
   installed the older package (or the arm64 one, not yet rebuilt) can
   still have the broken binary -- rebuild locally against the installed
   `libgps-dev`:

   ```bash
   ./SIGedge package direwolf
   sudo dpkg -i debs/direwolf_current_$(dpkg --print-architecture).deb
   ```

   Verify before relying on this bridge:

   ```bash
   ldd "$(command -v direwolf)" | grep 'not found'   # should print nothing
   direwolf --help   # should print usage, not a linker error
   ```

3. **Confirm the channel's actual audio sample rate once.** `radiod`
   doesn't advertise a channel's output rate anywhere `pcmrecord --raw`'s
   stream itself exposes; get it from a normal (non-raw) capture instead:

   ```bash
   pcmrecord 239.192.64.20   # Ctrl-C after a few seconds
   soxi *.wav                # or: file / ffprobe on the resulting .wav
   ```

   `run.sh` defaults to 12000 Hz. If the capture reports something else,
   export `HACKRF_APRS_AUDIO_RATE` accordingly (see below) -- a mismatch
   doesn't error, it just silently decodes nothing, since AFSK tone
   detection is rate-dependent.

## Running it

One-off, foreground, for testing:

```bash
decoders/hackrf-aprs-direwolf/run.sh
```

Decoded packets print to stdout via direwolf's normal console output.
Stop with Ctrl-C.

## Installing as a service

```bash
sudo cp decoders/hackrf-aprs-direwolf/hackrf-aprs-direwolf.service /etc/systemd/system/
# Fill in @decoder_user@ and @sigedge_home@ in that copy first --
# see the unit file's own comments.
sudo systemctl daemon-reload
sudo systemctl enable --now hackrf-aprs-direwolf.service
```

Left disabled until you do this explicitly, same convention as every
other optional service in this project (`soapyremote-server`, a
`radiod@<mission>` instance, `ai/ollama-bridge`'s eventual daemon) --
installing SIGedge never enables a decoder bridge on its own.

## Configuration knobs

All via environment variable, read by `run.sh`:

| Variable | Purpose | Default |
|---|---|---|
| `HACKRF_APRS_DATA_GROUP` | Multicast data group to read | `239.192.64.20` |
| `HACKRF_APRS_AUDIO_RATE` | Sample rate to hand direwolf | `12000` |
| `HACKRF_APRS_DIREWOLF_CONF` | direwolf config file | `direwolf-aprs.conf` (this directory) |

## What this does not do

- **No transmit.** No PTT is configured in `direwolf-aprs.conf`; this is
  receive/decode-only.
- **No APRS-IS igating.** Relaying decoded packets to APRS-IS needs an
  explicit `IGSERVER`/`IGLOGIN` addition to `direwolf-aprs.conf` -- treat
  that the same as any other outbound network path in this project (an
  explicit opt-in, not a default), per the top-level README's posture on
  `soapyremote-server` and the `ai/` bridges.
- **No multi-instance handling.** This bridges exactly one mission
  (`hackrf-aprs`) to exactly one decoder. See `decoders/README.md` for
  extending the same pattern to other missions/decoders.
