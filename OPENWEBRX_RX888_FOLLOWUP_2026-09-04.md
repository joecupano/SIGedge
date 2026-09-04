# OpenWebRX+ / RX-888 on rubberduck — session notes, 2026-09-04

Point-in-time handoff notes from testing OpenWebRX+'s setup/installation on
rubberduck and getting the RX-888 usable in it for a session, while leaving
`radiod@hackrf-aprs` and `radiod@rtlsdr-simplex` running on ka9q-radio
untouched. Prune/fold into [PROJECT_STATE.md](PROJECT_STATE.md) or
[KA9Q-DEPLOYMENT.md](KA9Q-DEPLOYMENT.md) once the open item below is closed,
same as `SIGLIERE_FOLLOWUP_2026-09-04.md` was handled earlier the same day.

## Current state

- `radiod@rx888-wwv.service` stopped + disabled (only that mission — the
  HackRF and RTL-SDR missions were left running, as intended: an SDR needs
  exactly one owner, but that's per-device, not per-host).
- OpenWebRX+ installed via the **luarvique PPA**
  (`https://luarvique.github.io/ppa/noble`), package `openwebrx` 1.2.123 —
  *not* built from source via `./SIGedge install openwebrx`. See "Why the
  in-repo install path doesn't work" below.
- Admin web user `admin` created (`sudo openwebrx admin adduser admin`). A
  pre-existing user `ne2z` was already present in `users.json` before this
  work started and was left untouched.
- ufw: port 8073/tcp opened (was default-deny from earlier
  SIGliere/sovereign-sigint hardening work).
- RX-888 added as a device in the OpenWebRX+ web UI, type `BBRF103 / RX666
  / RX888 / RX888 mkII (SDDC) device (via SoapySDR)`, using the SoapySDR
  module SIGedge's own `SDDC_Driver` device package already builds
  (`/usr/local/lib/SoapySDR/modules0.8/libSDDCSupport.so`) — no CUDA, no
  `sddc_connector` needed for this path.

## Open item: RX-888 USB pipe error

Last attempt to start the RX-888 source failed:

```
[SDDC] ERROR - usb_device: libusb Pipe error (.../usb_device.cpp:336)
...
SDR device "RX-888 MkII" has failed, selecting new device
```

Root cause: the RX-888's FX3 chip holds only one driver stack's firmware at
a time, freshly uploaded on each power cycle. `radiod` had loaded its own
firmware onto the device earlier in the session; OpenWebRX+'s SDDC driver
was then trying to talk to a device still running that firmware instead of
its own, and got USB control-transfer errors as a result.

**Fix, not yet confirmed working**: physically power-cycle the RX-888
(unplug ~15s, replug) so the FX3 returns to DFU/bootloader mode, then start
OpenWebRX+ fresh so it uploads its own firmware:

```bash
sudo systemctl kill openwebrx.service   # was hung in "deactivating (stop-sigterm)"
                                          # after a broken-pipe websocket error — kill first
# physically power-cycle the RX-888 here
lsusb -d 04b4:                           # confirm it re-enumerated (04b4:00f1)
sudo systemctl start openwebrx.service
sudo systemctl status openwebrx.service --no-pager -l | head -15
```

## RX-888 device UI notes (confirmed during this session / carried from sovereign-sigint)

- Sample rate is a **fixed list only**: 2/4/8/16/32/64 MS/s — 64.8
  (`radiod`'s native rate) is rejected by the UI.
- Start at **32 MS/s** — 64 MS/s pegged CPU and caused audio stutter on
  comparable hardware in `sovereign-sigint`'s build.
- Raise the global **FFT size** (Settings, not per-device) to **16384** for
  usable waterfall resolution at 32 MS/s.
- **Gain lives in the profile** (SDR devices → device → profile → RF
  gain), not the live receiver panel's gain control.
- Center frequency ~15 MHz gives a sane span for a WWV/HF profile; a low
  center (e.g. 3.5 MHz) with a wide sample rate pushes span below 0 Hz and
  looks broken.
- A newly added/edited profile does **not** appear in the receiver page
  until `sudo systemctl restart openwebrx` — it *is* saved immediately to
  `/var/lib/openwebrx/settings.json`, it's just the running process's
  in-memory list that's stale.

## Why the in-repo install path doesn't work yet

`./SIGedge install openwebrx` (`packages/pkg_openwebrx`) builds plain
`jketterl/openwebrx` from source — not actually "OpenWebRX+" despite the
package description — and is broken for RX-888 use specifically:

- It never clones or builds `sddc_connector` at all — the RX-888's native
  OpenWebRX device path is simply missing from the install.
- `sddc_connector`'s current `master` branch requires CUDA (unconditional
  `enable_language(CUDA)`) plus `csdr`>=0.19.0 and `owrx_connector`>=0.7.0
  — i.e. **their `develop` branches**, not the `master` branches
  `pkg_openwebrx` actually clones (frozen at 0.18.2/0.6.2, matching
  `openwebrx`'s own `develop` branch's needs only by accident for
  everything except this).
- `m17-cxx-demod` also fails to configure in this same install: SIGedge's
  own `codec2` package doesn't install a `codec2Config.cmake`, so
  `find_package(codec2)` can't find it. M17 digital voice ends up silently
  unavailable.
- Mixing the from-source build with the PPA package (as this session did,
  before abandoning the from-source path) causes real breakage worth
  remembering if this is ever attempted again: `/usr/local/bin` and
  `/usr/local/lib/python3.*/dist-packages` shadow the PPA's `/usr/bin` and
  `/usr/lib/python3/dist-packages` files. This caused a crash loop
  (`ImportError: cannot import name 'NoiseFilter' from 'pycsdr.modules'`)
  via a stale from-source `pycsdr` egg still registered in
  `easy-install.pth`, which in turn made the PPA package's own `postinst`
  fail (`dpkg` showed `openwebrx` as `iF`, half-configured) because
  postinst itself invokes `openwebrx admin ...`, which crashed on the same
  import. Files that pre-existed from the abandoned from-source install
  (`users.json`, `bands.json`) were also left owned by `baldrick` instead
  of the `openwebrx` system user, since the package postinst only chowns
  files it creates fresh — this let `sudo openwebrx admin adduser` succeed
  (running as root) while the live service, running as `openwebrx`, still
  couldn't read the file to authenticate a web login.

**Until `packages/pkg_openwebrx` is reworked** (clone `sddc_connector` +
its actual version requirements, or drop the from-source path entirely in
favor of the PPA), use the luarvique PPA directly for OpenWebRX+ on
RX-888-capable hosts — see `~/sovereign-sigint/scripts/phase6-openwebrx.sh`
and `~/sovereign-sigint/docs/openwebrx-sdr-quickstart.md` for a working,
previously-validated reference (that project built its own SoapySDDC
module from `ON5HB/RX888MK2-Soapy` since it didn't have SIGedge's
`SDDC_Driver` already built; rubberduck did, so that step was skippable
here).

## Other things worth remembering from this session

- `sudo` needs a real TTY — an unattended/agent session has no cached
  credential and no NOPASSWD rule here, so privileged commands have to be
  run interactively. Chunk multi-line privileged scripts rather than
  pasting them as one block — a big block can silently stall on a password
  prompt with no visible feedback.
- rubberduck's own LAN address is `192.168.173.65/24` (`eno1`). A laptop
  reaching it over SSH showed source IP `192.168.73.65` — a *different*
  `/24` (`192.168.73.0/24`, not `.173.`). Easy to transpose; caused one
  firewall rule to silently not match.
- ufw is active by default (default-deny incoming) from earlier
  SIGliere/sovereign-sigint hardening work — a service with no explicit
  `ufw allow` just times out rather than refusing, which looks identical
  to a dead service from the client side.
- `~/SIGliere` (capital "S", capital "L" mid-word) is the correct
  directory casing.
