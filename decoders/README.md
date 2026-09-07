# decoders

Bridges that turn a `radiod` audio channel into decoded output — the
"decoders" branch of the architecture diagram in the top-level
[README.md](../README.md), alongside `ai/`'s "APIs / MCP" branch. Nothing
here replaces the decoder applications themselves (those install via
`scripts/setup_decoders` / `packages/pkg_*`); each subdirectory is just the
plumbing that feeds one of them from a `radiod` multicast group instead of
a soundcard or an SDR the decoder would otherwise have to own directly.

**Sketch stage**, same footing as `ai/ollama-bridge`: not wired into
`SIGedge setup` or `scripts/` dispatch, no unit enabled by default. Each
subdirectory's own README covers its prerequisites and how to run it.

## hackrf-aprs-direwolf

Feeds the `radiod@hackrf-aprs` reference mission's demodulated FM audio
(APRS 144.390 MHz, `239.192.64.20`) into `direwolf` for AX.25/APRS
decoding, using `pcmrecord` (from `ka9q-radio-tools`) as the multicast-to-
pipe bridge. See [hackrf-aprs-direwolf/README.md](hackrf-aprs-direwolf/README.md).

## Adding another decoder bridge

The same shape applies to any of the other audio-in decoders reviewed
against ka9q-radio (`multimon-ng`, `aptdec`, `ggmorse`, the `radiosonde`
tools, `codec2`'s `freedv_rx`, `inmarsatc`): `pcmrecord --stdout --raw
<data-group>` piped into whatever the decoder accepts on stdin, wrapped in
a small script plus a disabled-by-default systemd unit that depends on the
`radiod@<mission>` instance it reads from. `hackrf-aprs-direwolf` is the
first of these and the template for the rest.
