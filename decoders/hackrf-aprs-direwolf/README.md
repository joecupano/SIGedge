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
   has something to decode once the mission itself is enabled and started
   -- see [KA9Q-DEPLOYMENT.md](../../KA9Q-DEPLOYMENT.md) §5. Check with:

   ```bash
   systemctl is-active radiod@hackrf-aprs
   ```

2. **`direwolf` must actually run on this host.** On the host this was
   sketched against, the installed `direwolf` binary fails immediately:

   ```
   direwolf: error while loading shared libraries: libgps.so.28: cannot open shared object file
   ```

   The installed `libgps30t64` package (Ubuntu 24.04's 64-bit-time_t
   transition) only provides `libgps.so.30` -- the prebuilt
   `direwolf_current_amd64.deb` was linked against the older `.so.28`.
   Rebuilding it locally against the currently installed `libgps-dev`
   resolves this:

   ```bash
   source packages/pkg_direwolf build
   ```

   Verify before relying on this bridge:

   ```bash
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
