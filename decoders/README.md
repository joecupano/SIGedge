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

## Wired up

| Bridge | Decoder | Feeds from | Needs a new radiod mission? |
|---|---|---|---|
| [hackrf-aprs-direwolf](hackrf-aprs-direwolf/README.md) | `direwolf` (AX.25/APRS) | `radiod@hackrf-aprs` (existing reference mission) | No — rides the existing FM/144.390 MHz channel |
| [freedv-hf](freedv-hf/README.md) | `codec2`'s `freedv_rx` (FreeDV digital voice) | any USB HF channel you configure | Yes — no reference mission demodulates USB |
| [radiosonde-rs41](radiosonde-rs41/README.md) | `pkg_radiosonde`'s `rs41dm_dft` (telemetry) | any FM 400-406 MHz channel you configure | Yes — no reference mission covers that band |
| [ft8-jt9](ft8-jt9/README.md) | ka9q-radio's own `jt-decoded` + WSJT-X's `jt9` (FT8/FT4/WSPR) | any USB HF channel you configure | Yes — no reference mission demodulates USB |

`hackrf-aprs-direwolf` needed nothing beyond a shell pipeline because a
matching `radiod` channel already existed. `freedv-hf`, `radiosonde-rs41`,
and `ft8-jt9` don't have that luxury — their operating frequency is a
real band/site choice, so those three require adding a channel yourself
first via `scripts/cfg_ka9q-radio_tui` (see each bridge's README for a
starting-point frequency and why `cfg_ka9q-radio` itself can't generate
one for you). `ft8-jt9` is also structurally different from the other
three: `jt-decoded` is a native ka9q-radio multicast client, not a shell
pipe through `pcmrecord`/`sox` — see its README.

## Not wired up — no CLI decoder exists to pipe into

Two packages reviewed as ka9q-radio decoder candidates turned out, on
inspection of what they actually install, to have **no standalone decoder
executable at all**:

- **ggmorse** — ships only `libggmorse.so` and a header (confirmed via
  `dpkg -L ggmorse`). `packages/pkg_ggmorse` builds with
  `-DGGMORSE_BUILD_EXAMPLES=OFF` deliberately, and upstream's own examples
  are an SDL2 live-mic GUI (`ggmorse-gui`) and a text-to-WAV *encoder*
  (`ggmorse-to-file`) — neither reads a file or stdin to decode. Wiring
  this up for real means writing a small program against `ggmorse.h`
  (feed it PCM frames, print what it decodes), not just connecting
  existing pieces the way the three bridges above do.
- **inmarsatc** — ships three libraries (`libinmarsatc_decoder.so`,
  `_demodulator.so`, `_parser.so`) and headers, no executable. Beyond
  that, its demodulator wants **48 kS/s complex I/Q**, not demodulated
  audio — a fundamentally different `radiod` output mode (`iq`, not
  `fm`/`usb`) from every other decoder here, on top of needing an
  L-band-capable front end and a directional antenna pointed at a
  specific Inmarsat satellite. It's designed to be embedded in something
  like SDR++/SDRangel's own Inmarsat-C plugin, not run standalone; the
  related `stdcdec`/`qstdcdec` projects upstream mentions are the actual
  usable CLI tools, and neither is in this repo's `packages/`.

Both are one-way doors past "pipe an existing binary" — say the word if
you want either turned into an actual wrapper program (linking
`libggmorse`/`libinmarsatc_*` directly) rather than left as a gap.

## Adding another decoder bridge

The same shape applies to any other audio-in decoder: `pcmrecord --stdout
--raw <data-group>`, resampled with `sox` if the decoder needs a fixed
rate `radiod`'s channel doesn't happen to already produce, piped into
whatever the decoder accepts on stdin — wrapped in a small script, plus a
disabled-by-default systemd unit if it's meant to run standing rather than
attended.
