# Project State

Last updated: 2026-09-05

This file describes what has actually been installed, tested, or found broken
on a live host, as distinct from what the repository's scripts and docs
describe in general. It complements [README.md](README.md) and
[KA9Q-DEPLOYMENT.md](KA9Q-DEPLOYMENT.md) rather than replacing them.

## Live status on rubberduck

rubberduck runs `ka9q-radio` with three reference missions
(`radiod@rx888-wwv`, `radiod@hackrf-aprs`, `radiod@rtlsdr-simplex`) alongside
two sibling projects on the same host: `~/sovereign-sigint` and `~/SIGliere`
(the AI/cognition tier — no SDR involvement, its own CUDA stack is for
Ollama, unrelated to anything below).

### OpenWebRX+ / RX-888 — confirmed working

`./SIGedge install openwebrx` (`packages/pkg_openwebrx`) was tried first and
found broken for actual RX-888 use: it builds plain `jketterl/openwebrx`,
not actually "OpenWebRX+", and never clones or builds `sddc_connector` at
all — the one thing the RX-888 (SIGedge's flagship reference device) needs
from that install path.

**Working path instead**: the luarvique PPA
(`https://luarvique.github.io/ppa/noble`), package `openwebrx` — the same
approach `~/sovereign-sigint/scripts/phase6-openwebrx.sh` already uses.
RX-888 support comes from OpenWebRX+'s `soapy_sddc` feature, backed by a
SoapySDR module built from `ON5HB/RX888MK2-Soapy` (not SIGedge's own
`SDDC_Driver` module, which serves a different direct-access purpose) — no
CUDA, no `sddc_connector` needed. Full detail, including the `radio` group
membership requirement and the RX-888 FX3-firmware/power-cycle gotcha that
blocked this for a while, is now in
[KA9Q-DEPLOYMENT.md](KA9Q-DEPLOYMENT.md#rx-888-in-openwebrx--confirmed-working-path-not-packagespkg_openwebrx).

As of this update: OpenWebRX+ is installed, running, reachable, with an
admin account, the RX-888 configured as a device (32 MS/s, center 15 MHz,
RF/IF gain 20/20), and **confirmed actually streaming** — verified via a
live waterfall/audio in the browser and a sustained ~105% CPU
`soapy_connector` process with no errors.

### Known gaps found in `packages/pkg_openwebrx` (not yet fixed in scripts)

- Never clones/builds `sddc_connector` — the RX-888's native
  high-bandwidth OpenWebRX device path is entirely missing from this
  install target.
- `m17-cxx-demod` fails to configure: SIGedge's own `codec2` package
  doesn't install a `codec2Config.cmake`, so `find_package(codec2)` fails.
  M17 digital voice decode is silently unavailable as a result.
- Its dependency chain is internally inconsistent: `openwebrx` itself is
  cloned from its `develop` branch, but `csdr`/`owrx_connector` are cloned
  from `master`, which is frozen at older releases (0.18.2/0.6.2) that
  don't satisfy what `develop`'s dependents (like `sddc_connector`)
  actually require (0.19.0/0.7.0, i.e. their own `develop` branches).
- Net effect: the package name says "OpenWebRX+" but the actual install is
  plain upstream `jketterl/openwebrx`, and it isn't usable for the RX-888
  as shipped. The PPA path above is the one to use until this is reworked.

## Other repo notes worth carrying forward

- The dated `*_FOLLOWUP_<date>.md` doc pattern (see `SIGLIERE_FOLLOWUP_2026-09-04.md`'s
  history) is for point-in-time session handoff notes, expected to be
  pruned once folded back into a permanent doc. `OPENWEBRX_RX888_FOLLOWUP_2026-09-04.md`
  followed that pattern and has now been folded into this file and into
  [KA9Q-DEPLOYMENT.md](KA9Q-DEPLOYMENT.md) and removed.
- `CLAUDE_MEMORY_openwebrx-rx888-rubberduck.md` is a verbatim copy of an
  agent session-memory file, kept in sync with the live `~/.claude` memory
  of the same name rather than folded/pruned — it's a different kind of
  artifact than the followup docs.
