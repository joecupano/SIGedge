# ka9q-radio deployment on SIGedge

This document describes the ka9q-radio integration that exists in the current SIGedge repository. It is an operator-facing companion to the project overview in [README.md](README.md).

## Service model

ka9q-radio is SIGedge's primary interface between attached SDR hardware and upper-layer network services:

```text
SDR -> native ka9q-radio front end -> radiod -> RTP/IP multicast -> consumers
```

For the RX-888 MkII, HackRF, and RTL-SDR paths, SoapySDR is not between the hardware and `radiod`. SIGedge installs SoapySDR and related direct-access plumbing for applications that need an alternative path, but those services are not enabled by default.

An SDR must have only one active owner. Do not run `radiod` and a direct-access application against the same device at the same time.

## Current implementation

| Component | Repository path | Current behavior |
|---|---|---|
| RX-888 host preparation | `devices/pkg_rx888` | Builds and stages volatile FX3 firmware, installs udev rules, configures USB buffering, and records a manifest |
| ka9q-radio package lifecycle | `packages/pkg_ka9q-radio` | Installs dependencies; builds, packages, installs, removes, or purges ka9q-radio; validates optional RX-888 preparation |
| Radio mission configuration | `scripts/cfg_ka9q-radio` | Generates RX-888, HackRF, and RTL-SDR configurations and optionally enables or starts their services |
| Radio mission configuration (TUI) | `scripts/cfg_ka9q-radio_tui` | Interactive Python/Textual editor for `radiod@<instance>.conf` files: full add/change/delete of missions, sections, and keys, plus live enable/start control. Writes files directly (does not go through `cfg_ka9q-radio`) -- see its module docstring for why |
| Reference configurations | `config/radiod@*.EXAMPLE` | Shows the current generated configuration shape |
| ka9q-radio / OpenWebRX switch | `scripts/service_toggle` | Safely switches between ka9q-radio radiod missions and OpenWebRX, always stopping+disabling the side being left before starting the other |

Package installation and radio mission configuration are intentionally separate. Installing ka9q-radio does not create or start a radio-specific `radiod` instance.

## Current limitations

The repository is not yet a fully reproducible production deployment:

- `packages/pkg_ka9q-radio install` expects a populated `debs/ka9q-radio/` directory (one `.deb` per binary package SIGedge builds; see step 2). It now ships both amd64 and arm64 prebuilt packages there, matching the rest of `debs/`'s dual-arch convention (e.g. `debs/codec2_current_*.deb`). Both `install` and the `setup_services` check that decides between installing packages vs. building from source filter to the host's own arch -- a real bug fixed 2026-09 (they used to accept or merely check for *any* `.deb` regardless of architecture, so an arm64 host with only a committed amd64 build would get fed an unsatisfiable amd64 install instead of falling back to building from source). A checkout missing packages for the current arch still needs the `package` action run (or `build`, or the directory supplied separately).
- ka9q-radio's own upstream `debian/` packaging defines build dependencies (`libfobos-dev`, `libhydrasdr-dev`) that are not packaged for Ubuntu 24.04 at all. `packages/pkg_ka9q-radio package` works around this by excluding the binary packages that need them (`ka9q-radio-fobos`, `ka9q-radio-hydrasdr`) from the build rather than trying to satisfy them.
- `packages/pkg_ka9q-radio` pins ka9q-radio to a fixed commit via `KA9Q_RADIO_REF` rather than following upstream `main`, so it can lag behind current upstream until that pin is updated deliberately.
- RX-888 firmware also defaults to its upstream `main` branch unless `RX888_FW_REF` is set.
- The generated radio configurations are reference missions. Validate their option names and hardware behavior against the installed ka9q-radio revision before production use.

Regardless of installation path, SIGedge does not start a radio receiver by default. Hardware assignment, multicast interface selection, and receiver activation remain explicit operator actions.

## Prerequisites

The current target is Ubuntu Server 24.04 LTS on amd64/x86_64 or arm64/aarch64. The host needs:

- `sudo` privileges
- working package and source-network access
- a multicast-capable network interface
- a USB 3.x SuperSpeed path for an RX-888 MkII
- sufficient CPU, memory, and USB bandwidth for the selected sample rates and channels

The package scripts install their build and runtime dependencies. Avahi is enabled and started during the ka9q-radio build/install lifecycle because ka9q-radio uses multicast DNS for discovery.

## 1. Prepare an RX-888 MkII when applicable

RX-888 preparation is optional, and HackRF, RTL-SDR, and other supported front ends do not require it at all. It is no longer a hard prerequisite for RX-888 either: as of the current `KA9Q_RADIO_REF`, the `ka9q-radio-rx888` binary package (built by `packages/pkg_ka9q-radio package`) bundles its own FX3 boot firmware and a udev rule + `rx888_boot.service` that auto-loads it the moment an unprogrammed RX-888 (`04b4:00f3`) is plugged in — no separate firmware staging step required for the device to enumerate and for `radiod` to open it. `devices/pkg_rx888` still matters for what it does that the package doesn't: tuning `usbfs_memory_mb` for reliable sustained transfers at 64.8 Msps. Run it when you need that tuning, or when you want firmware pinned to a specific, verified build rather than whatever the ka9q-radio package currently bundles.

Under the normal SIGedge parent installer, run the RX-888 device install before installing or building ka9q-radio. For direct use from a repository checkout, provide a source directory and source the package script:

```bash
mkdir -p /tmp/sigedge-build
SIGEDGE_SOURCE=/tmp/sigedge-build source devices/pkg_rx888 install
```

To build and stage firmware without attached-hardware validation:

```bash
mkdir -p /tmp/sigedge-build
RX888_VALIDATE=0 SIGEDGE_SOURCE=/tmp/sigedge-build \
  source devices/pkg_rx888 install
```

The script installs or creates:

```text
/usr/local/share/ka9q-radio/SDDC_FX3.img
/etc/udev/rules.d/99-rx888.rules
/etc/modprobe.d/usbcore.conf
/var/lib/rx888/rx888-prep.env
```

Firmware is staged on the host and loaded into volatile FX3 RAM. The script does not permanently flash EEPROM or SPI storage.

Check the result with:

```bash
cat /var/lib/rx888/rx888-prep.env
ls -l /usr/local/share/ka9q-radio/SDDC_FX3.img
cat /sys/module/usbcore/parameters/usbfs_memory_mb
lsusb -t
```

If the USB buffering setting could not be applied live, reboot before high-rate RX-888 operation.

## 2. Build or install ka9q-radio

Upstream ka9q-radio ships its own native Debian packaging (`debian/control`, debhelper-compat 13) that splits the project into about 18 binary packages, one per front end or subsystem. SIGedge builds and installs only the subset its reference missions use: `ka9q-radio`, `ka9q-radio-common`, `ka9q-radio-rx888`, `ka9q-radio-hackrf`, `ka9q-radio-rtlsdr`, `ka9q-radio-control`, `ka9q-radio-monitor`, `ka9q-radio-tools`, `ka9q-radio-siggen` (see `KA9Q_RADIO_PKGS` in `packages/pkg_ka9q-radio`).

### Packaged path (recommended)

Build reproducible, dpkg-tracked `.deb` files via `dpkg-buildpackage` against upstream's own `debian/` directory, then install them:

```bash
cd /path/to/SIGedge
./SIGedge package ka9q-radio   # -> debs/ka9q-radio/*.deb
./SIGedge install ka9q-radio   # apt-get installs debs/ka9q-radio/*.deb
```

Because dpkg tracks the result, `./SIGedge remove ka9q-radio` and `./SIGedge purge ka9q-radio` work cleanly afterward.

### Manual test-build path

For a quick one-off test build outside package management (raw `make install` to `/usr/local`, not tracked by dpkg — `remove`/`purge` are no-ops against it; clean up with `make uninstall`/`make purge` in the source tree instead):

```bash
mkdir -p /tmp/sigedge-build
SIGEDGE_SOURCE=/tmp/sigedge-build source packages/pkg_ka9q-radio build
```

### Verify the installation

```bash
command -v radiod
command -v control
command -v monitor
systemctl is-active avahi-daemon
avahi-browse -art
```

If dynamic front-end modules were produced, they are under `/usr/lib/ka9q-radio/` for a packaged install, or `/usr/local/lib/ka9q-radio/` for a manual `build`-action install:

```bash
ls -la /usr/lib/ka9q-radio/ /usr/local/lib/ka9q-radio/ 2>/dev/null
```

Some front ends may be built directly into `radiod`, so the absence of a same-named `.so` file is not by itself an installation failure.

## 3. Select the multicast interface

On a host with Ethernet, Wi-Fi, VPN, container bridges, or multiple management interfaces, select the radio-facing interface deliberately:

```bash
ip -br link
ip -br address
ip route
```

Pass its name as `KA9Q_IFACE` when generating configurations. If it is omitted, `radiod` selects the interface. SIGedge defaults multicast TTL to 1, limiting distribution to the local segment.

## 4. Generate a radio mission

The current reference missions are:

| Selection | SDR | Channel | Generated configuration | Service instance |
|---|---|---|---|---|
| `rx888` | RX-888 MkII | WWV 10.000 MHz AM | `/etc/radio/radiod@rx888-wwv.conf` | `radiod@rx888-wwv` |
| `hackrf` | HackRF | APRS 144.390 MHz FM | `/etc/radio/radiod@hackrf-aprs.conf` | `radiod@hackrf-aprs` |
| `rtlsdr` | RTL-SDR | Simplex 144.650 MHz FM | `/etc/radio/radiod@rtlsdr-simplex.conf` | `radiod@rtlsdr-simplex` |

Each mission's `status`/`data` multicast address is a static `239.192.x.x` value (`dns =
on`) rather than one that's re-derived from a hash on every `radiod` restart --
`data` is a literal address checked directly into the template; `status` gets there via a
`/etc/hosts` entry this script syncs (see [NETWORKING.md](NETWORKING.md)'s "How the
override actually works" and "Current static assignment" table for both the mechanism and
the actual per-instance addresses). A consumer (a gateway's `nodes.json`, a firewall rule)
can point at these permanently.

Generate one configuration without enabling or starting it:

```bash
KA9Q_IFACE=enp1s0 \
KA9Q_ENABLE_SERVICES=0 \
KA9Q_START_SERVICES=0 \
  bash scripts/cfg_ka9q-radio hackrf
```

Replace `enp1s0` with the intended interface. Use `rx888`, `rtlsdr`, or `all` instead of `hackrf` as needed.

The configurator backs up an existing target file before replacing it. Review the generated file before enabling a receiver:

```bash
sudo sed -n '1,240p' /etc/radio/radiod@hackrf-aprs.conf
```

### Configuration overrides

| Variable | Purpose | Default |
|---|---|---|
| `KA9Q_IFACE` | Multicast network interface | selected by `radiod` |
| `KA9Q_TTL` | Multicast TTL | `1` |
| `KA9Q_ENABLE_SERVICES` | Enable generated instances | `0` |
| `KA9Q_START_SERVICES` | Start/restart generated instances | `0` |
| `RX888_SERIAL` | Select an RX-888 by serial | unset |
| `HACKRF_SERIAL` | Select a HackRF by serial | unset |
| `RTLSDR_SERIAL` | Select an RTL-SDR by serial | unset |
| `HACKRF_CENTER_HZ` | HackRF hardware center frequency | `144640000` |
| `RTLSDR_CENTER_HZ` | RTL-SDR hardware center frequency | `144900000` |

Serial overrides should be used only when supported by the installed ka9q-radio front end.

### Interactive alternative

`scripts/cfg_ka9q-radio_tui` is a standalone [Textual](https://textual.textualize.io/) app, styled after ka9q-radio's own `control` program (bordered panels, a live status list, single-letter hotkeys -- see `source/ka9q-radio/docs/utils/control.md` for `control`'s own key table): a mission list on the left (each row showing live enabled/active state), and on the right a tree of the selected mission's actual INI structure -- every section and every key/value pair, not a fixed field set.

It supports full add/change/delete/update over the complete config surface:

| Key | Action |
|---|---|
| `n` / `d` | New mission / delete mission (left-hand list) |
| `a` | Add -- a section (cursor on the mission root) or a key (cursor on a section/key) |
| `c` | Change the value of the key under the cursor |
| `x` | Delete the key or section under the cursor |
| `w` | Write the mission's config to disk (with a confirmation preview) |
| `s` / `t` | Toggle enabled-at-boot / toggle running now, for the selected mission |
| `r` | Refresh status |
| Tab | Switch focus between the mission list and the config tree |

**Design note:** this app writes `/etc/radio/radiod@<instance>.conf` directly (via `sudo tee`, after a timestamped backup -- the same convention as `cfg_ka9q-radio`'s own `backup_config`) instead of shelling out to `cfg_ka9q-radio`. `cfg_ka9q-radio` can only regenerate its three fixed, single-channel reference templates through a handful of environment variables; it has no way to express "add this new key" or "create a mission that isn't rx888/hackrf/rtlsdr". Genuine add/change/delete/update over arbitrary config content needs a real INI-level editor, so this tool is now that editor. `cfg_ka9q-radio` itself is unchanged and remains the non-interactive generator `setup_services` uses for the three reference missions.

Each mission's file is parsed with Python's `configparser` (order- and case-preserving) and values are kept exactly as written -- including ka9q-radio's own literal quoting of frequencies like `freq = "10m0"` -- so loading and re-saving a file without touching it round-trips byte-for-byte identically. Deleting a mission or a section/key never erases data outright: mission deletion renames the file aside with a `.<timestamp>.deleted` suffix, and every write backs up the previous version first, exactly like `cfg_ka9q-radio`.

Requires the `textual` Python package, which is not part of any SIGedge setup script -- install it yourself the first time you use this tool. The Debian/Ubuntu `python3-textual` package is version 0.1.x, far too old for the widgets this app uses; two ways to get a current one instead:

```bash
# Quick: --user install, bypassing the "externally managed environment" guard.
# This installs to ~/.local, not system-wide, so it can't collide with apt.
pip install --user --break-system-packages textual
```

```bash
# Isolated: a venv. Debian/Ubuntu strip ensurepip out of the base python3, so
# `python3 -m venv` fails with "ensurepip is not available" until python3-venv
# is installed first.
sudo apt-get install -y python3-venv
python3 -m venv scripts/.venv
scripts/.venv/bin/pip install textual
scripts/.venv/bin/python3 scripts/cfg_ka9q-radio_tui
```

Either way, once installed: `scripts/cfg_ka9q-radio_tui` (or `.venv/bin/python3 scripts/cfg_ka9q-radio_tui` for the venv path).

## 5. Enable and start explicitly

After reviewing a generated configuration:

```bash
sudo systemctl enable radiod@hackrf-aprs
sudo systemctl start radiod@hackrf-aprs
```

Equivalent instance names are `radiod@rx888-wwv` and `radiod@rtlsdr-simplex`.

Check immediate status and bounded logs:

```bash
systemctl --no-pager --full status radiod@hackrf-aprs
journalctl --no-pager -u radiod@hackrf-aprs -n 100
```

Do not enable every reference instance unless all corresponding devices are attached and intended for concurrent use.

## 6. Validate discovery and multicast

The reference missions use static multicast addresses (`dns = yes`, see
[NETWORKING.md](NETWORKING.md)'s "Current static assignment" and "How the override
actually works" sections for the mechanism and why `status`/`data` get there differently).
Avahi advertisement isn't disabled by any of this (it's gated by `advertise`, a separate
setting, default on) -- `avahi-browse -art` still shows these instances, and still
resolves `sigedge-<hardware>.local`, but it should now report the *same* address on every
restart instead of a new hash each time. Validate against the known address directly too:

```bash
avahi-browse -art
ip maddr show
ip -s link show enp1s0
sudo timeout 15 tcpdump -ni enp1s0 host 239.192.1.10 or host 239.192.64.10
control 239.192.1.10
```

Replace `enp1s0` with the configured interface, and the addresses with the target
instance's from NETWORKING.md. Use a bounded capture so validation cannot block an
unattended workflow indefinitely. If `avahi-browse` or a `sigedge-<hardware>.local` lookup
ever disagrees with NETWORKING.md's table, suspect `/etc/hosts`'s SIGedge block first (see
`scripts/cfg_ka9q-radio`'s `sync_static_hosts`) -- `status`'s static address depends on it
in a way `data`'s doesn't.

For hardware checks, stop any service that owns the device first, then use the appropriate tool:

```bash
hackrf_info
timeout 10 rtl_test -t
lsusb
lsusb -t
```

## 7. Stop or disable a receiver

```bash
sudo systemctl stop radiod@hackrf-aprs
sudo systemctl disable radiod@hackrf-aprs
```

Stopping `radiod` releases the SDR for an explicitly selected direct-access service. Stop that direct-access service before returning the device to ka9q-radio.

### Switching to or from OpenWebRX

ka9q-radio and OpenWebRX (`packages/pkg_openwebrx`, `config/openwebrx.service`) are alternative deployments for the same SDR hardware and must not both be active. Rather than stopping/disabling each side by hand, use `scripts/service_toggle`, which discovers whichever `radiod@<mission>` instances are actually configured or running (it does not assume the reference missions above are the only ones), stops+disables the side being left, and verifies the result against `systemctl` rather than trusting prior state:

```bash
scripts/service_toggle status                    # show current state of both sides
scripts/service_toggle ka9q-radio [mission ...]   # switch to ka9q-radio
scripts/service_toggle openwebrx                  # switch to OpenWebRX
scripts/service_toggle off                        # stop+disable both
```

It prompts before stopping anything currently active (`-y` to skip) and supports `-n`/`--dry-run` to preview the `systemctl` calls it would make.

### RX-888 in OpenWebRX+ — confirmed working path (not `packages/pkg_openwebrx`)

`packages/pkg_openwebrx`'s from-source build does not give you a usable
RX-888 in OpenWebRX+: it builds plain `jketterl/openwebrx` (despite the
package description) and never clones or builds `sddc_connector`, the
piece that device needs from that install path. Confirmed working
alternative, validated end-to-end on rubberduck:

> As of 2026-09, `packages/pkg_openwebrx`'s general build/install chain
> itself is fixed and verified working on arm64/Debian Trixie (GCC 14),
> where it previously failed outright -- see [PROJECT_STATE.md](PROJECT_STATE.md)
> for the three specific bugs and fixes. That does not change the
> `sddc_connector` gap above: RX-888 support specifically is still
> unavailable through this path, so the PPA route below remains the one
> to use for that device.

1. Install OpenWebRX+ from the **luarvique PPA**
   (`https://luarvique.github.io/ppa/noble`, package `openwebrx`) instead
   of `./SIGedge install openwebrx`. This is the same approach
   `~/sovereign-sigint/scripts/phase6-openwebrx.sh` uses.
2. RX-888 support comes from OpenWebRX+'s `soapy_sddc` feature, backed by
   a SoapySDR module built from **`ON5HB/RX888MK2-Soapy`**
   (`SOAPYSDDC_REPO` in `~/sovereign-sigint/scripts/phase6-openwebrx-rx888.sh`)
   — CPU-only, no CUDA, no `sddc_connector`. SIGedge's own `SDDC_Driver`
   device package (`devices/pkg_rx888`) builds a different SDDC SoapySDR
   module for its own direct-access purposes; the two are not
   interchangeable in practice — use the ON5HB build for OpenWebRX+.
3. Add the `openwebrx` system user to the **`radio`** group
   (`sudo usermod -aG radio openwebrx`, then restart the service). The
   RX-888 enumerates as `04b4:00f3` (DFU/unprogrammed) before firmware
   upload; that device node is `root:radio` mode `0660` plus a `uaccess`
   ACL that only covers an interactive login "seat" session — neither
   covers the `openwebrx` service account, so without `radio` group
   membership the SoapySDR module gets `LIBUSB_ERROR_ACCESS` and
   `soapy_connector` segfaults trying to stream anyway.
4. **The RX-888's FX3 chip holds only one driver stack's firmware at a
   time, loaded fresh into SRAM on every power cycle — and an OS reboot
   does not count.** A warm reboot resets the USB link (protocol-level)
   but does not necessarily drop USB port power (VBUS), so the FX3 can
   still be running whichever firmware a *previous* owner (e.g. `radiod`)
   loaded, even after a full system reboot. Confirmed symptom: repeated
   `[SDDC] ERROR - usb_device: libusb Pipe error` on specific write
   control transfers, immediately followed by a `soapy_connector`
   segfault on `activateStream`, while a `SoapySDRUtil --probe` still
   succeeds (probing doesn't touch the same code path). Fix: physically
   unplug the RX-888 for ~15s and replug it — an actual power cycle, not
   a reboot — so the FX3 returns to genuine DFU mode
   (`lsusb -d 04b4:` should show `00f3 ... (DFU mode)`) before the next
   owner opens it and uploads its own firmware.
5. In the web UI (Settings → SDR devices → Add new device), the exact
   entry is `BBRF103 / RX666 / RX888 / RX888 mkII (SDDC) device (via
   SoapySDR)` — not a generic "SoapySDR device". Sample rate is a fixed
   list only (2/4/8/16/32/64 MS/s; 64.8, `radiod`'s native rate, is
   rejected). 32 MS/s avoids the CPU/audio stutter 64 MS/s causes; raise
   the global FFT size (Settings, not per-device) to 16384 for usable
   resolution at that rate. Gain lives in the profile, not the live
   receiver panel. A newly added/edited profile needs
   `sudo systemctl restart openwebrx` before it appears in the receiver
   page — it's saved to `/var/lib/openwebrx/settings.json` immediately,
   it's just the running process's in-memory list that's stale.

## Troubleshooting

### A receiver cannot open its SDR

Check for another process that owns the device, stop conflicting direct-access services, and then inspect udev permissions and USB enumeration:

```bash
systemctl --no-pager --full status radiod@hackrf-aprs
journalctl --no-pager -u radiod@hackrf-aprs -n 100
lsusb
lsusb -t
```

A known culprit worth checking specifically: `soapyremote-server.service` should be disabled and stopped after a normal `SIGedge setup`, but if it was ever enabled by hand, or by a checkout predating that fix, it exposes every SoapySDR-visible device to the network and will fight `radiod` for the same hardware. Check `systemctl is-active soapyremote-server.service`; see [README.md](README.md#direct-sdr-use-including-soapysdr) for the intended opt-in/opt-out flow.

### Discovery works on the wrong interface

Regenerate the configuration with an explicit `KA9Q_IFACE`, then restart the selected receiver. Check routes and multicast membership before changing firewall rules.

### RX-888 drops samples or disconnects

Confirm SuperSpeed operation with `lsusb -t`, inspect kernel messages with `journalctl -k -n 100`, verify `usbfs_memory_mb`, and avoid sharing the controller with other high-bandwidth devices.

### Configuration fails after an upstream update

`packages/pkg_ka9q-radio` pins ka9q-radio to a fixed commit via `KA9Q_RADIO_REF`, not upstream `main`, so this should not happen from a routine `SIGedge package ka9q-radio` run. It becomes relevant if `KA9Q_RADIO_REF` is deliberately overridden to track `main` or another commit: upstream `main` is active development and can be broken outright (a recent example: a commit that referenced a header file it never added, breaking the build entirely, not just changing config syntax). Compare the generated configuration keys against the documentation or source for the exact installed commit (`git -C source/ka9q-radio rev-parse HEAD`) before assuming a syntax change is the cause.
