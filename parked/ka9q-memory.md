# ka9q-radio Expertise Archive

Reference notes distilled from the upstream repo while building
`install_ka9q-radio.sh` (since removed from this directory; superseded by
`devices/pkg_rx888` and `packages/pkg_ka9q-radio` in the main tree) and
[ka9q-radio-config-gen.sh](ka9q-radio-config-gen.sh), which is still here.
Everything below was pulled from the project's own docs/config files (cited
per section), not guessed — use it as ground truth for other ka9q-radio work
instead of re-deriving it. Upstream: https://github.com/ka9q/ka9q-radio
(README states the project is "NOT yet ready for general use" and some docs,
e.g. `docs/radiod.8`, `docs/SDR/hackrf.md`, `docs/SDR/sdrplay.md`, are
stubs/incomplete — noted below wherever that applies).

## What it is

`radiod` is the core daemon: a multichannel SDR "spectrum server" that reads
one hardware front end and fans out one or more demodulated channels as RTP
multicast streams. Companion tools (`control`, `monitor`, `metadump`,
`pcmrecord`, etc.) attach to those streams. Config drives everything — no
special install steps beyond the udev/group setup in `install_ka9q-radio.sh`.

## Config file format

- Location: `/etc/radio/radiod@<instance>.conf`, or a
  `/etc/radio/radiod@<instance>.conf.d/` directory whose files are
  concatenated in lexicographical order and treated as one file.
  (Source: `config/README`)
- INI-style: `[section]` headers, `key = value` lines, `#` comments.
  Undefined/misspelled keys in a section are silently ignored — no error.
  (Source: `docs/ka9q-radio.md` part 1)
- Three kinds of section, in this order by convention:
  1. `[global]` — mandatory, exactly one.
  2. One hardware section, named whatever `global`'s `hardware =` says.
  3. One or more channel-group sections (arbitrary names, e.g. `[FM]`,
     `[WSPR]`) — each defines a shared mode/output stream tuned to one or
     more frequencies.
- Per-device USB auto-config via udev: `start-ka9q-radio` looks for
  `/etc/radio/devices/vvvv-dddd-<serial>.conf` first, then
  `vvvv-dddd.conf` (lowercase hex, dash-separated vendor-device id). Don't
  edit the shipped defaults in that tree — copy to a custom file in
  `/etc/radio/devices` instead. (Source: `config/defaults/README`)

## `[global]` section keys

Required: `hardware` (names the hardware section), `status` (mDNS/multicast
status domain, e.g. `myradio.local`).

Optional (defaults in parens): `iface` (multicast interface), `dns` (off),
`data` (default output multicast group name), `mode` (default demod
preset — see Presets below), `ttl` (0 = stay on-LAN), `tos` (48),
`blocktime` ms (20 — must be an Opus-legal value: `2.5 5 10 20 40 60 80 100
120`), `overlap` (5, FFT block overlap = 1/N), `fft-threads` (2),
`fft-internal-threads` (0), `rtcp` (no, experimental), `sap` (no),
`mode-file` (path to presets.conf, default
`/usr/local/share/ka9q-radio/presets.conf`), `wisdom-file` (FFTW3 wisdom
cache, default `/var/lib/ka9q-radio/wisdom`), plus commonly-seen but less
formally documented: `encoding` (e.g. `opus`), `verbose`, `buffer`,
`static`, `affinity`. (Source: `docs/ka9q-radio.md` part 1 + multiple
`config/examples/*.conf`)

## Hardware section — universal keys

- `device` — **mandatory**. Selects the front-end driver:
  `rtlsdr | hackrf | rx888 | airspy | airspyhf | sdrplay | bladerf | fobos |
  hydrasdr | funcube`.
- `description` — recommended free text advertised via mDNS. **Must be ≤63
  chars and contain no `/` or control characters** (spaces OK).
- `serial` — optional hex serial to pick a specific unit when more than one
  is attached (device discovered first is used otherwise). Per-device tools
  to read it: `rtl_eeprom`, `airspy_info`, `airspyhf_info`.
  (Source: `docs/ka9q-radio.md` part 2 + each `docs/SDR/*.md`)

## Per-device hardware keys (confirmed from upstream docs/examples)

**rtlsdr** (`docs/SDR/rtlsdr.md`, `config/defaults/rtlsdr.conf`): `samprate`
(default 1,800,000 Hz), `direct_sampling` (0 off / 1=I / 2=Q, default 0),
`agc` (bool, default false), `bias` (bool, default false — bias-tee), `gain`
(float dB, default 0.0).

**hackrf** (`docs/SDR/hackrf.md` — incomplete upstream past `serial`;
`config/defaults/hackrf.conf`): only `samprate` is confirmed beyond
`device`/`serial` (example uses `5m0` = 5 MHz; device tops out ~20 Msps).
Other gain knobs likely exist per driver version but aren't documented — the
config generator leaves an "extra lines" free-form escape hatch for this
device rather than inventing field names.

**rx888** (`docs/SDR/rx888.md`, `config/defaults/rx888.conf`) — direct
sampling only, R820 tuner path not yet supported: `samprate` (default
64,800,000 Hz; hardware rated to 129,600,000 Hz but users hit thermal issues
at full rate, hence the halved default), `gain` (float dB, default 10.0 —
AD8370 analog VGA; aim for -20 to -25 dBFS at the A/D), `att` (float dB,
0–31.5 in 0.5 steps, default 0.0 — PE4312 attenuator ahead of the VGA),
`calibrate` (double, default 0 — clock error fraction e.g. `-1e-6`;
**experimental**, corrects both tuning and output rate via sample
interpolation but is CPU-heavy and can "chug" at low SNR), `firmware`
(string, default `SDDC_FX3.img`, relative to
`/usr/local/share/ka9q-radio`), `queuedepth` (int, default 16 USB
transfer buffers), `reqsize` (int, default 32, ×16KB per buffer),
`dither`/`rand` (bool, default false — LTC2208 dither / output
randomization features, minimal measured benefit). One instance per host is
recommended (>2 Gbps at full rate).

**airspy** (R2/Mini) (`docs/SDR/airspy.md`,
`config/examples/radiod@airspy-generic.conf`): `samprate` (default = highest
advertised, usually 20,000,000 Hz — note the R2's "10Msps complex" figure is
really 20Msps real samples halved by the library; radiod can accept raw real
samples directly and skip that conversion), `linearity` (bool, default
false — switches Airspy library gain table from sensitivity-optimized to
intermod-resistant), `lna-agc`/`mixer-agc` (bool, default false — hardware
AGC; upstream notes these "don't seem to keep proper gain distribution",
prefer the default software AGC), `lna-gain`/`mixer-gain`/`vga-gain` (int,
default -1=auto; setting any disables software AGC), `gainstep` (int 0–21,
default -1=auto), `bias` (bool, default false), `converter` (int, default 0
— upconverter LO e.g. 120MHz for SpyVerter), `agc-high-threshold` /
`agc-low-threshold` (float dBFS, default -10.0 / -40.0 — software AGC gain
step thresholds).

**airspyhf** (HF+/HF+ Discovery) (`docs/SDR/airspy.md`,
`config/examples/radiod@airspyhf-generic.conf`): `samprate` — **must be one
of** `912k 768k 456k 384k 256k 192k`; driver default 912k is reported to
drop USB data, upstream's own example configs use `768k`. `hf-agc`,
`hf-att`, `hf-lna`, `agc-thresh` (all bool, default false; exact function of
`agc-thresh` undocumented upstream), `lib-dsp` (bool, default true —
library-side fine frequency + I/Q imbalance correction; CPU-costly but
affordable at this low sample rate).

**sdrplay** (RSP family) (`docs/SDR/sdrplay.md` — stub upstream;
`config/examples/radiod@sdrplay-generic.conf` is the only real source):
`antenna` (string, RSP-model dependent, e.g. `"Antenna A/B/C"` on an RSPdx),
`samprate` (example uses 2,000,000 Hz), `lna-state` (int, model-dependent
index), `if-agc` (bool), `overload-gr-interval` (int seconds, example: 30),
`frequency` (a static/fallback tune frequency at the front-end level).
Treat this device's field list as provisional — confirm against a current
`config/examples/radiod@sdrplay-*.conf` for your checkout.

**bladerf** (`docs/SDR/bladerf.md`, `config/defaults/bladerf.conf`):
`samprate` (default 12,000,000 Hz), `bandwidth` (default 80% of samprate),
`gain` (default AGC/auto), `bias` (bool, default false). The shipped
default file also sets `linearity`/`lna-agc`/`mixer-agc` — the same
Airspy-family option names, reused by this driver.

**fobos** (RigExpert) (`docs/SDR/fobos.md`) — requires building/installing
`libfobos` separately (not yet packaged for Debian); see the doc for the
`cmake`/`udev` install steps. `samprate` (double, default = highest
advertised, usually 80,000,000 Hz), `clk_source` (0=internal/1=external
CLKIN, default 0, external untested), `direct_sampling` (bool, default
false — HF1/HF2 direct path instead of RF input), `hf_input` (0=I/Q,
1=HF1, 2=HF2, default 0, only meaningful with direct_sampling), `lna_gain`
(0/1→0dB, 2→+16dB, 3→+33dB; ignored in direct sampling), `vga_gain` (0–62dB
in 2dB steps, default 0; ignored in direct sampling).

**hydrasdr** (RFone) (`docs/SDR/hydrasdr.md` — thin upstream;
`config/defaults/hydrasdr.conf`): `samprate` (default = highest advertised,
~20,000,000 Hz), `linearity`, `lna-agc`, `mixer-agc` (bool — same semantics
as the Airspy R2 driver; shipped default enables both AGCs), plus
`agc-high-threshold`/`agc-low-threshold` (float dBFS) and an optional static
`frequency`, mirrored from the airspy driver's option set.

**funcube** (AMSAT-UK dongle) — explicitly called "very old and limited...
untested" upstream. `config/defaults/funcube.conf` only sets `number`
(device index, default 0) beyond `device`/`description`. Note: that shipped
default file has a section-header bug — it's headed `[rx888]` even though
`hardware = funcube` — don't copy that mismatch; name the section after the
device consistently.

## Presets (`presets.conf`, referenced via `mode =`)

| preset | type | bw | purpose |
|---|---|---|---|
| pm / npm | FM | 16.0k / 12.5k | narrowband FM voice, de-emphasized |
| fm / nfm | FM | 16.0k / 12.5k | narrowband FM data, no de-emphasis |
| wfm | wideband FM | 220.0k | broadcast FM, stereo, 48k audio |
| am | linear | 10.0k | envelope-detected AM |
| sam | linear | 10.0k | coherent AM, carrier tracking |
| ame | linear | 5.1k | coherent AM, USB-only |
| iq | linear | 10.0k | raw I/Q passthrough |
| cwu / cwl | linear | 0.4k | CW on USB/LSB, 500Hz filter |
| usb / lsb | linear | 3.05k | amateur SSB voice |
| dsb | linear | 10.0k | DSB-SC, PLL carrier recovery |
| amsq | linear | 6.0k | AM with carrier squelch |
| wspr | linear | 3.05k | USB variant, AGC disabled |
| nam | linear | 6.0k | flat-response AM |
| spectrum | spectrum | n/a | experimental |

(Source: `docs/presets.conf.md`)

## Channel-group section syntax

Each section (name is arbitrary, e.g. `[FM]`) shares one mode and one output
stream across one or more tuned frequencies.

- `mode` — preset name from the table above; required unless set in
  `[global]`.
- `data` — mDNS name for the output multicast group; required unless set in
  `[global]`. radiod hashes it into a 239.0.0.0/8 IPv4 multicast address.
- `freq` — carrier frequency. Accepts plain decimal Hz, or the project's own
  shorthand where the decimal point is replaced by a scale letter, e.g.
  `88m3` = 88.3 MHz, `123.4k`, `1.234g`. **Caution:** a small bare number
  (e.g. `400`) is heuristically read as MHz, not Hz — always give enough
  digits to be unambiguous, or use a suffixed form. Multiple frequencies go
  in one quoted, space-separated string:
  `freq = "14m095600 7m038600"`. Ten aliases `freq0`–`freq9` exist to dodge
  parser line-length limits.
- `demod` — optional demodulator override (`linear`, `fm`, `wfm`).
- `samprate` — optional output sample rate in Hz, must be a multiple of 200.
- `ssrc` — optional RTP SSRC (auto-derived from frequency if omitted).
- `disable` — `y` to keep a section defined but inactive.
- `channels` — 1 (mono) or 2 (stereo) output channels.
- `encoding` — per-channel output format override (`s16le`, `s16be`,
  `f32le`, `opus`, ...).
- Ad hoc extras seen in real configs: `low`/`high` (e.g. WSPR segment
  offsets in the shipped `radiod@airspyhf-generic.conf`).

(Source: `docs/ka9q-radio.md` part 3 + `config/examples/radiod@fm.conf`,
`radiod@airspyhf-generic.conf`, `radiod@sdrplay-generic.conf`)

### Real example (verbatim, `config/examples/radiod@fm.conf`)

```ini
[global]
mode = wfm
status = fm.local
hardware = airspy
iface = eth0
data = fm-pcm.local
ttl = 1

[airspy]
device = airspy
description = "FM broadcast"

[FM]
# KSDS jazz
data = ksds-pcm.local
freq = 88m3

[FM2]
# KPBS NPR - mono
freq = 89m5
data = kpbs-pcm.local
channels = 1
```

## Gotchas worth remembering

- Opus `blocktime` must be one of `2.5 5 10 20 40 60 80 100 120` ms.
- RX-888 MkII: default samprate is deliberately half the rated 129.6MHz due
  to reported thermal problems at full rate; only one unit per host is
  practical (>2 Gbps at full rate).
- Airspy HF+: don't use the driver's own 912k default sample rate — 768k is
  what upstream actually ships in its example configs, because 912k drops
  USB data.
- `docs/SDR/hackrf.md` and `docs/SDR/sdrplay.md` are stubs — trust the
  `config/examples/*.conf` files over the prose for those two.
- `config/defaults/funcube.conf` has a section-name/hardware-name mismatch
  (`[rx888]` header under `hardware = funcube`) — a bug in the shipped
  file, not a convention to copy.
- mDNS `description` fields: ≤63 chars, no `/`, no control characters.
- Multiple `radiod` instances can coexist on one host, bounded by CPU and
  USB bandwidth (e.g. Airspy R2 is USB2 at 240Mb/s — give each instance its
  own host controller).

## Tooling produced this session (this repo)

- `install_ka9q-radio.sh` (no longer present in this directory) — bootstrap
  installer for Ubuntu 24.04 (build deps, clone+build ka9q-radio, `radio`
  group, config dirs). Ran as a normal sudo-capable user (refused to run as
  root itself) and escalated only the individual steps that needed it via
  `sudo`. Its job is now done by `devices/pkg_rx888` and
  `packages/pkg_ka9q-radio` — see [KA9Q-DEPLOYMENT.md](../KA9Q-DEPLOYMENT.md).
- [ka9q-radio-config-gen.sh](ka9q-radio-config-gen.sh) — interactive wizard
  that generates a real `radiod@<name>.conf`: walks `[global]`, the correct
  per-device hardware section (all 10 device types above, field-accurate),
  and repeatable channel-group sections, then writes the file (optionally
  installing it to `/etc/radio` and enabling the systemd unit via
  `--install`). Frequencies accept `14074000`, `14.074M`, `500k`, etc. and
  normalize to Hz. `--list-devices` / `--help` for non-interactive info.

## Primary sources consulted

- https://github.com/ka9q/ka9q-radio (README)
- `docs/ka9q-radio.md` (config guide, parts 1–3)
- `docs/presets.conf.md`
- `docs/SDR/{rtlsdr,hackrf,rx888,airspy,sdrplay,bladerf,fobos,hydrasdr}.md`
- `config/README`, `config/defaults/README`
- `config/defaults/{rtlsdr,hackrf,rx888,airspy,airspyhf,bladerf,fobos,funcube,hydrasdr}.conf`
- `config/examples/{radiod@fm,radiod@airspy-generic,radiod@airspyhf-generic,radiod@sdrplay-generic}.conf`
