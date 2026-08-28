# ka9q-radio deployment on SIGedge

This document describes the ka9q-radio integration that exists in the current SIGedge repository. It is an operator-facing companion to the project overview in [README.md](README.md). Development history and unfinished design work belong in [HANDOFF.md](HANDOFF.md), not in this guide.

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
| Reference configurations | `config/radiod@*.EXAMPLE` | Shows the current generated configuration shape |
| Diagnostic helper | `scripts/verify_ka9q-radio.sh` | Development helper; not suitable for unattended validation in its current form |

Package installation and radio mission configuration are intentionally separate. Installing ka9q-radio does not create or start a radio-specific `radiod` instance.

## Current limitations

The repository is not yet a fully reproducible production deployment:

- `packages/pkg_ka9q-radio install` expects `debs/ka9q-radio_current_amd64.deb` or `debs/ka9q-radio_current_arm64.deb`. Neither artifact is currently tracked, so a clean checkout must use the source `build` action or supply a package.
- The ka9q-radio source build follows upstream `main`; it is not pinned to a tested commit.
- RX-888 firmware also defaults to its upstream `main` branch unless `RX888_FW_REF` is set.
- The generated radio configurations are reference missions. Validate their option names and hardware behavior against the installed ka9q-radio revision before production use.
- `scripts/verify_ka9q-radio.sh` still references older service instance names and invokes interactive or unbounded tools. Use the bounded checks in this document instead.

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

RX-888 preparation is optional. HackRF, RTL-SDR, and other supported front ends do not require it.

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

### Source build available in a clean checkout

Until release `.deb` files are supplied, the source build is the usable clean-checkout path:

```bash
mkdir -p /tmp/sigedge-build
SIGEDGE_SOURCE=/tmp/sigedge-build source packages/pkg_ka9q-radio build
```

This installs dependencies, clones and builds ka9q-radio, runs `make install`, reloads systemd and udev, and verifies the `radiod`, `control`, and `monitor` commands.

For a repeatable deployment, set or record a tested upstream revision before production. The current package script does not yet expose a ka9q commit override.

### Prebuilt package path

When an architecture-appropriate package has been placed in `debs/`, the SIGedge `install` action can install it. The required names are:

```text
debs/ka9q-radio_current_amd64.deb
debs/ka9q-radio_current_arm64.deb
```

The parent SIGedge command supplies the environment used by the package script. Do not use the `install` action on a clean checkout until the appropriate file exists.

### Verify the installation

```bash
command -v radiod
command -v control
command -v monitor
systemctl is-active avahi-daemon
avahi-browse -art
```

If dynamic front-end modules were produced, they are normally under:

```bash
ls -la /usr/local/lib/ka9q-radio/
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

```bash
avahi-browse -art
ip maddr show
ip -s link show enp1s0
sudo timeout 15 tcpdump -ni enp1s0 multicast
```

Replace `enp1s0` with the configured interface. Use a bounded capture so validation cannot block an unattended workflow indefinitely.

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

## Troubleshooting

### A receiver cannot open its SDR

Check for another process that owns the device, stop conflicting direct-access services, and then inspect udev permissions and USB enumeration:

```bash
systemctl --no-pager --full status radiod@hackrf-aprs
journalctl --no-pager -u radiod@hackrf-aprs -n 100
lsusb
lsusb -t
```

### Discovery works on the wrong interface

Regenerate the configuration with an explicit `KA9Q_IFACE`, then restart the selected receiver. Check routes and multicast membership before changing firewall rules.

### RX-888 drops samples or disconnects

Confirm SuperSpeed operation with `lsusb -t`, inspect kernel messages with `journalctl -k -n 100`, verify `usbfs_memory_mb`, and avoid sharing the controller with other high-bandwidth devices.

### Configuration fails after an upstream update

Compare the generated configuration keys with the documentation or source for the exact installed ka9q-radio commit. The current SIGedge build tracks upstream `main`, so syntax or driver behavior can change until the project pins a tested revision.
