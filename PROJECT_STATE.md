# Project State

Last updated: 2026-09-09

This file describes what has actually been installed, tested, or found broken
on a live host, as distinct from what the repository's scripts and docs
describe in general. It complements [README.md](README.md) and
[KA9Q-DEPLOYMENT.md](KA9Q-DEPLOYMENT.md) rather than replacing them.

## Live status on sigpi

sigpi is a Raspberry Pi 4B (4 GB RAM) running Raspberry Pi OS Desktop --
Debian GNU/Linux 13 (Trixie), arm64/aarch64. This is a supported combination
(`scripts/setup_start`'s certification check accepts Debian 13 on aarch64
explicitly) but is not the primary reference example in README.md, which
otherwise centers Ubuntu Server 24.04 and Raspberry Pi 5. Attached hardware
during this round of work: one RTL-SDR (`0bda:2838`) only -- no RX-888 or
HackRF physically connected, so nothing RX-888-specific below was validated
against real hardware, only against the build/install/service chain.

### ka9q-radio -- installed, arm64 packages fixed

`./SIGedge setup` initially failed installing ka9q-radio on this host: the
repository had only ever shipped an amd64 build of `debs/ka9q-radio/*.deb`
(from a prior amd64 dev-machine session), and both `packages/pkg_ka9q-radio
install` and the `setup_services` check that picks packages-vs-source-build
grabbed/looked for *any* `.deb` in that directory regardless of
architecture -- so an arm64 host got handed an unsatisfiable amd64 apt install
instead of falling back to building from source. Fixed (see
`packages/pkg_ka9q-radio`, `scripts/setup_services`) to filter by host
arch, and a real arm64 build was produced via `SIGedge package ka9q-radio`
and committed alongside the existing amd64 one, matching the dual-arch
convention the rest of `debs/` already uses. `apt-get install --dry-run`
against the new arm64 packages resolves cleanly. `radiod@.service` is
installed, `disabled`/inactive -- no mission has been enabled or started on
this host, by deliberate operator choice while OpenWebRX is being evaluated
instead (see "Device ownership" in README.md).

### RX-888 SDDC_Driver (direct-access SoapySDR path) -- three aarch64 build bugs fixed

`scripts/setup_devices` clones and builds `renardspark/SDDC_Driver` for the
optional direct-access RX-888 path. On this host it failed with three
separate, real upstream bugs, none specific to this repo but all specific
to 64-bit ARM (aarch64) with a modern GCC (14, as shipped by Trixie) -- none
of these had apparently ever been exercised on an aarch64 build before:

1. `Core/CMakeLists.txt`'s CPU-detection regex (`arm.*`) does not match
   `aarch64` (no "arm" substring in that string), so it hit
   `FATAL_ERROR "Unable to identify CPU"` immediately.
2. `HWCAP_NEON` is only defined for 32-bit ARM headers; aarch64 reports
   NEON/Advanced SIMD via `HWCAP_ASIMD` instead, so
   `fft_mt_r2iq.cpp`'s `detect_neon()` failed to compile at all.
3. `-mfpu=neon-vfpv4` is an AArch32-only GCC/Clang flag; the code only
   skipped it for `APPLE` (Apple Silicon clang), not Linux aarch64/GCC, so
   the NEON source file failed to compile on this GCC toolchain.

All three are patched into `scripts/setup_devices` as idempotent
post-clone `sed`/`python3` steps (the actual fix lives there, not in
`source/`, which is gitignored and rebuilt from a fresh clone each time).
Verified: full `cmake`+`make`+`install` succeeds and produces a working
SoapySDR SDDC module on this host. Confirmed this does not affect amd64 --
all three fixes are inside CPU/arch-gated branches that amd64's own
`STREQUAL "x86_64"`/`__x86_64__` branch is selected before ever reaching.

### OpenWebRX (`packages/pkg_openwebrx`) -- general build chain fixed; RX-888 gap unchanged

A prior session (2026-09-04, on host rubberduck) found `packages/pkg_openwebrx`
broken for RX-888 use specifically -- see the "RX-888 in OpenWebRX+" section
of KA9Q-DEPLOYMENT.md, still accurate and still the reason to use the
luarvique PPA instead of this script for that device. This session found
(on sigpi, arm64/Trixie/GCC 14) that the build chain didn't even complete
independent of that RX-888 gap -- three more bugs, all now fixed:

1. **csdr**: `libcsdr.c`'s `NEON_OPTS` path (compiled in on arm/aarch64)
   called `errhead()`, a helper defined in a different, unlinked build
   target (`csdr.c`, the CLI executable, not the `csdr` library target
   `libcsdr.c` builds into) using that target's own globals. Older GCC
   only warned on the resulting implicit declaration; GCC 14 makes it a
   hard error. Fixed by dropping the stray calls (pure diagnostics, no
   functional loss) -- patched into `packages/pkg_openwebrx` as a
   post-clone `sed` step.
2. **digiham**: pins `CMAKE_CXX_STANDARD 11`, which fails against Debian
   Trixie's ICU 76.1 headers (`auto` as a non-type template parameter --
   a C++17 feature). digiham's own code has no dependency on pre-C++17
   semantics, so raised to 17 instead of pinning ICU down. Patched into
   `packages/pkg_openwebrx` as a post-clone `sed` step.
3. **openwebrx itself**: `packages/pkg_openwebrx` tracked openwebrx's
   `master` branch (`v1.3.0-dev`), which requires csdr/pycsdr >= 0.19.0 --
   a version neither project has actually released yet (their own
   `master` is 0.18.2). The app refused to start with "you are missing
   required dependencies" even right after a clean, successful build.
   Pinned to release tag `1.2.2` instead, which only requires
   csdr/pycsdr >= 0.18.0 and digiham >= 0.6 -- both satisfied.

The previously-noted gap ("`m17-cxx-demod` fails to configure: SIGedge's
own `codec2` package doesn't install a `codec2Config.cmake`") no longer
reproduces on this host -- `codec2`/`libcodec2-1.2` are installed via
SIGedge's own `packages/pkg_codec2` and `codec2-config.cmake` is present;
`m17-cxx-demod` configures and builds cleanly. Not independently
re-verified whether this was fixed elsewhere or was host-specific.

**Net result on sigpi**: `./SIGedge install openwebrx` now completes --
csdr, pycsdr, js8py, owrx_connector, codecserver, digiham, pydigiham, and
m17-cxx-demod all build and install; `openwebrx.service` installs
`disabled` (by design, matching the install-disabled/activate-explicitly
pattern used throughout SIGedge). Once enabled+started
(`sudo systemctl enable --now openwebrx.service`), it reaches `active`,
listens on `0.0.0.0:8073`, and is reachable both on the host and over the
network. An admin user (`pi`) was created via
`./openwebrx.py admin adduser pi`. `radiod@.service` remained `disabled`
throughout this work, confirmed after each step -- no device-ownership
conflict.

**Still not available via this path**: RX-888 support specifically --
`sddc_connector` is still never cloned or built by `packages/pkg_openwebrx`
(unchanged from the 2026-09-04 finding). Use the luarvique PPA path in
KA9Q-DEPLOYMENT.md's "RX-888 in OpenWebRX+" section for that device. This
was not re-tested against real RX-888 hardware this session (none attached
to sigpi) -- everything above is build/install/service-level verification
only, for RTL-SDR-class general use.

## Other repo notes worth carrying forward

- The pattern of a dated `*_FOLLOWUP_<date>.md` doc for point-in-time
  session handoff notes is intentional and expected to be pruned once
  superseded -- this file (`PROJECT_STATE.md`) is the durable one that
  survives; fold a followup doc's lasting findings back into this file (or
  directly into README.md/KA9Q-DEPLOYMENT.md, as done this round) and
  remove the followup doc once it's fully closed out.
