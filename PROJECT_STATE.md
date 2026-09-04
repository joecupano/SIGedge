# Project State

Last updated: 2026-09-04

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

### OpenWebRX+ / RX-888 — in progress, see followup doc

`./SIGedge install openwebrx` (`packages/pkg_openwebrx`) was tried first and
found broken for actual RX-888 use — see
[OPENWEBRX_RX888_FOLLOWUP_2026-09-04.md](OPENWEBRX_RX888_FOLLOWUP_2026-09-04.md)
for the full diagnosis. In short: it builds plain `jketterl/openwebrx`, not
actually "OpenWebRX+", and never clones or builds `sddc_connector` at all —
the one thing the RX-888 (SIGedge's flagship reference device) needs from
that install path.

**Working path instead**: the luarvique PPA
(`https://luarvique.github.io/ppa/noble`), package `openwebrx` — the same
approach `~/sovereign-sigint/scripts/phase6-openwebrx.sh` already uses
successfully. RX-888 support comes from OpenWebRX+'s `soapy_sddc` feature,
which SIGedge's own `SDDC_Driver` device package already builds the
SoapySDR module for (`devices/pkg_rx888` /
`~/SIGedge/source/SDDC_Driver`) — no CUDA, no `sddc_connector` needed.

As of this update: OpenWebRX+ is installed, running, and reachable, with an
admin account created and the RX-888 added as a device in the web UI. Not
yet confirmed actually streaming — last blocker was a USB pipe error caused
by the RX-888's FX3 firmware state (ka9q-radio's firmware still loaded from
before the device was handed over); fix in progress is a physical
power-cycle of the device. See the followup doc for exact next steps.

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

- A prior `SIGLIERE_FOLLOWUP_2026-09-04.md` handoff doc was deprecated and
  removed earlier the same day this file was added — the pattern of a
  dated `*_FOLLOWUP_<date>.md` doc for point-in-time session handoff notes
  is intentional and expected to be pruned once superseded, same as this
  one should be once the RX-888 blocker above is resolved and folded back
  into this file or into `KA9Q-DEPLOYMENT.md`.
