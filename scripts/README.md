# Scripts

## First time setup
When **./SIGedge setup** is run it calls the following scripts in order:

- **setup_start**
starts a menu to select devices and services

- **setup_core**
installs baseline software and libraries used across packages, and the
shared SDR access model (`sdr-access install`).

- **setup_devices**
installs drivers and supporting software for devices. Each device has
its own **devices/pkg_<device>** for installation and removal.

- **setup_decoders**
installs codecs, demodulators, and other decode-side utilities (APTdec,
codec2, multimon-ng, direwolf, etc.) shared across packages, independent
of which SDR devices or services are selected.

- **setup_services**
installs and setups services that use the devices. Every service is left
disabled; a service starts when a device is assigned to it with
`SIGedge assign`. `setup_start` finishes by running `driver-check`.

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

## Device ownership

Each attached SDR is assigned to exactly one service, recorded in
`/etc/sigedge/assignments`. See [README.md](../README.md#device-ownership-across-services)
for the model; these are the pieces.

- **sdr-assign** (`SIGedge assign`)
Assigns one device to one service: `sdr-assign <device> <service>[:instance]`,
`sdr-assign <device> none`, `sdr-assign list`, `sdr-assign adopt`. A device
is a serial, `port:<usb-port>` (RX-888), or a kind (`rx888`, `hackrf`,
`rtlsdr`) when only one of that kind is attached. Services: `radiod[:mission]`,
`openwebrx`, `rtltcp`, `sdrangelsrv`, `soapysdrsrv`. Each move releases the
current owner (and any other service whose config still claims the device),
waits until `fuser` shows nothing holding the USB device, runs the device's
handoff hook, then has the new owner's adapter configure and start it, and
records the result. Refuses to mix the whole-host services (SDRangel server,
SoapySDR server, which open any device they can see) with other owners unless
`--force`. `-y` skips the prompt, `-n` is a dry run. The first assignment on a
host with no record adopts the current claims.

- **device-inventory.sh** (`SIGedge inventory`)
Read-only. One line per attached SDR: its id, its assignment, and who
actually holds it right now -- process and systemd unit, from `fuser` on
`/dev/bus/usb/...` (run with `sudo` to see other users' processes, otherwise
`?`). Warns when assignment, live holder and service configs disagree, when
ka9q-radio's `rx888_boot` firmware loader is active for an RX-888 assigned
elsewhere, and when ka9q-radio's udev autostart is enabled. `--detail` adds
every config-level claim (radiod `serial =`, `RTLTCP_SERIAL`, OpenWebRX+,
SDRangel/SoapySDR server state); `--json` is machine-readable.

- **service_toggle**
Compatibility wrapper for "everything to one side": `service_toggle
ka9q-radio [mission ...]` assigns each configured mission's device to it,
`service_toggle openwebrx` assigns every attached device to OpenWebRX+, and
`service_toggle off` releases every assigned device -- all through
`sdr-assign`, so each device still gets the full handoff and the record stays
correct. `-y`, `-n` as above.

- **adapters/**
One file per service, sourced by `sdr-assign` and `device-inventory.sh`:
`adapter_kinds`, `adapter_whole_host`, `adapter_installed`, `adapter_units`,
`adapter_claims` (what its own config says it uses), `adapter_acquire` and
`adapter_release` (configure/start or stop it for one device). `radiod`
pins `serial =` in the mission and starts `radiod@<mission>`; `openwebrx`
rewrites OpenWebRX+'s device list with `owrx_settings.py` (assigned entries
enabled and pinned, the rest disabled, never deleted); `rtltcp` writes
`RTLTCP_SERIAL` to `/etc/default/rtltcp`; `sdrangelsrv` and `soapysdrsrv` run
their unit while any device is assigned to them. A new service plugs in by
adding a file here and its name to `SDR_SERVICES` in `lib/sdr_common.sh`.

- **handoff/**
Device-type hooks run between release and acquire. `handoff/rx888` masks
ka9q-radio's `rx888_boot.service` unless `radiod` is the new owner, then
resets the FX3 to its bootloader with `fx3_cmd reset` (RESETFX3), falling
back to `fx3_cmd usbreset`, so the next owner loads its own firmware. HackRF
and RTL-SDR need no handoff.

- **lib/sdr_common.sh**
Shared by all of the above: device discovery from sysfs (no device is
opened), live holders via `fuser`, the assignment record, and adapter
loading. An RX-888 is identified by USB port because its serial changes with
its firmware state.

- **sdr-access**
One access model for SDR hardware. `install` creates the `sdr` group and
installs `config/99-sigedge-sdr.rules` (every supported SDR `0660 root:sdr`,
overriding the vendor rules' mix of `plugdev`/`radio`); `sync` adds the
service accounts that exist (`openwebrx`, `radio`) and the invoking user to
`sdr`; `check` reports the rule, the group and each device node's owner.
`setup_core` runs `install`; `pkg_openwebrxplus` and `pkg_ka9q-radio` run
`sync`.

- **driver-check**
Read-only driver-stack check, run at the end of `SIGedge setup`: the same
SoapySDR driver registered twice (e.g. SIGedge's SoapyHackRF and the
distro's `soapysdr0.8-module-hackrf`, with load order deciding which runs),
binaries in `/usr/local` or SIGedge-built packages that can't load a library,
`/usr/local` Python modules hiding packaged ones (PROBLEM, exit 1), and
`/usr/local` libraries shadowing packaged ones of the same soname (NOTE --
often deliberate).

Regression test: `tests/sdr-assign-test.sh` exercises all of this in a
sandbox (fake sysfs, systemctl, sudo, fx3_cmd) without root or hardware.

## Environment support
- **SIGedge_env**
Environment variables used by SIGedge project. Use as a template for your
own custom scripts>
