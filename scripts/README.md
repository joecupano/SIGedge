# Scripts

## First time setup
When **./SIGedge setup** is run it calls the following scripts in order:

- **setup_start**
starts a menu to select devices and services

- **setup_core**
installs baseline software and libraries used across packages.

- **setup_devices**
installs drivers and supporting software for devices. Each device has
its own **devices/pkg_<device>** for installation and removal.

- **setup_decoders**
installs codecs, demodulators, and other decode-side utilities (APTdec,
codec2, multimon-ng, direwolf, etc.) shared across packages, independent
of which SDR devices or services are selected.

- **setup_services**
installs and setups services that use the devices. The services are setup
but further configuration is necessary for each service before enabling them.

## Services ##
- **cfg_ka9q-radio**
Directly sourced by **setup_services** during **SIGedge setup**.
Reachable via **SIGedge config ka9q-radio <mission>**. 

- **ka9q-radio-builder**
Standalone Python/[Textual](https://textual.textualize.io/) editor for
`radiod@<instance>.conf` files, styled after ka9q-radio's own `control`
program (bordered panels, live status, single-letter hotkeys). Full
add/change/delete/update over the complete config: a mission list (`n`
new, `d` delete) on the left with live enabled/active state, and on the
right a tree of the selected mission's actual sections and keys (`a` add
a section/key, `c` change a value, `x` delete, `w` write to disk with a
backup, `s`/`t` toggle enable/start). Parses each file with `configparser`
(order- and case-preserving, values kept exactly as written) and writes
directly via `sudo tee` with a timestamped backup first -- it does not go
through `cfg_ka9q-radio`, which can only regenerate its three fixed
single-channel templates and has no way to express an arbitrary added key
or a mission of any other name; see the script's own module docstring and
[KA9Q-DEPLOYMENT.md](../KA9Q-DEPLOYMENT.md#interactive-alternative) for
why. `cfg_ka9q-radio` itself is unchanged and still what `setup_services`
uses non-interactively for the three reference missions. Requires the
`textual` package, not installed by any SIGedge setup script -- install it
yourself the first time (the Debian/Ubuntu `python3-textual` apt package
is version 0.1.x and far too old for this script): `pip install --user
--break-system-packages textual`, or `sudo apt-get install -y python3-venv
&& python3 -m venv .venv && .venv/bin/pip install textual` if you'd rather
keep it isolated (plain `python3 -m venv` fails on Debian/Ubuntu until
`python3-venv` is installed -- ensurepip isn't in the base image). Run
directly: `scripts/ka9q-radio-builder`; not part of the `SIGedge`
parent-script dispatch.

- **service_toggle**
Safely switches between ka9q-radio and OpenWebRX, which are alternative
deployments for the same SDR hardware and must never both be active at
once. Always stops+disables the side being switched away from before
enabling+starting the other, verifying each step against `systemctl`
rather than assuming prior state. Switching only -- for current state,
use `device-inventory.sh` below. Run directly, e.g.
`scripts/service_toggle ka9q-radio` or `scripts/service_toggle openwebrx`;
not part of the `SIGedge` parent-script dispatch.

- **device-inventory.sh**
Read-only tool, and the one place to see the full picture: what's
physically attached, what already claims it, and whether that claim is
actually live right now. Lists attached SDR/RF USB devices (RTL-SDR,
HackRF, RX-888) with their real USB serial numbers, side by
side with whatever SIGedge configs currently claim each device --
`radiod`'s per-mission `serial =` line (plus each mission's live
systemd enabled/active state), OpenWebRX's live enabled/active state,
and RTL-TCP server's `RTLTCP_SERIAL` override
(`/etc/default/rtltcp`, see `config/rtltcp.service`) -- cross-matched
against what's actually plugged in, and flags it if a radiod mission and
OpenWebRX are ever both active at once (the one conflict that can
actually be confirmed). SDRangel server and SoapySDR Server are reported
as active-or-not only -- neither exposes a per-device claim SIGedge can
read. Answers "what's attached, what claims it, and is that claim live"
without switching anything itself -- use `service_toggle` above to
actually move a device between radiod and OpenWebRX; see
[README.md](../README.md)'s device-ownership section for the actual
one-owner-per-device policy. No arguments, no sudo required:
`./scripts/device-inventory.sh` (add `--json` for a machine-readable
version of the same data).

## Environment support
- **SIGedge_env**
Environment variables used by SIGedge project. Use as a template for your
own custom scripts>
