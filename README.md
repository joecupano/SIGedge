# SIGedge

SIGedge is an RF edge platform for presenting attached software defined radios (SDRs) to upstream services, local host and network connected, for signals analysis and further services consumption. SIGedge can present signals as raw IQ up to demodulated signals. Potential upstream services include OpenWebRX+, Ollama with Open WebUI, Kismet, SDRangel server and Soapy service consumers.

Some upstream services require exclusive ownership of an SDR. SIGedge supports this through
**two separate, mutually exclusive ways to expose an SDR** — pick one per device, never both at once:

```text
SDR hardware -> ka9q-radio radiod -> RTP/IP multicast -> any number of network consumers
SDR hardware -> direct-access app (SoapySDR / SoapyRemote) -> one exclusive upstream owner
```

| | ka9q-radio (primary) | Direct SDR access (alternative) |
|---|---|---|
| How it's exposed | `radiod` owns the hardware and republishes IQ/audio/control as IP multicast RTP | A single application opens the SDR directly, locally via SoapySDR or over the network via SoapyRemote |
| Consumers | Any number of network clients can subscribe to the multicast streams | Exactly one application at a time |
| Use it when | You want SIGedge itself to act as a shared SDR server for other systems | A specific app (SDRangel, OpenWebRX+, GQRX, CubicSDR, `rtl_tcp`, ...) needs raw, exclusive access to the hardware |
| Setup section | [ka9q-radio: use and setup](#ka9q-radio-use-and-setup) | [Direct SDR use, including SoapySDR](#direct-sdr-use-including-soapysdr) |

**An SDR must have exactly one active owner.** Do not start a direct-access application against a device that a `radiod` instance already owns, and do not start `radiod` for a device in use by SDRangel, OpenWebRX+, SoapyRemote, `rtl_tcp`, or another application. Two different physical SDRs on the same host can run under two different owners simultaneously (e.g. HackRF under `radiod`, RTL-SDR handed to a direct-access app) — the constraint is per device, not per host.

Kismet extends this same constraint to its own capture sources. It's a protocol-layer monitor (WiFi, Bluetooth, RF) that runs alongside `radiod`, not a replacement for it, and whichever devices it opens directly — RTL-SDR via `kismet_cap_sdr_rtl433`, Ubertooth via `kismet_cap_ubertooth_one` — still need exactly one owner. When two always-on services genuinely need the same device *type* at the same time (`radiod` running an RTL-SDR mission while Kismet also wants RTL-SDR-based ISM-band capture, for instance), the resolution is one physical unit per consumer, each pinned to its own service by USB serial number, never left to auto-detect and risk both landing on the same dongle: `scripts/cfg_ka9q-radio` takes `RTLSDR_SERIAL=<serial>` for `radiod`'s mission, and Kismet's own source definition takes a `rtl433-sn-<serial>`-style string for the same purpose (see `config/kismet_site.conf.example`). RTL-SDR dongles are cheap enough that a dedicated unit per consumer is the practical default here — RX-888/HackRF's higher cost is exactly why the discipline-only, one-unit-total model above still applies to them instead.

## Architecture

```text
                              SIGedge node

  RX-888 MkII ----+       +-------------------+
  HackRF ----------+------>| ka9q-radio radiod |----> RTP/IP multicast
  RTL-SDR ---------+       +-------------------+              |
                                                             +--> APIs / MCP
                                                             +--> analytics
                                                             +--> recorders
                                                             +--> decoders

  Selected SDR --------> optional direct-access service ----> compatible app
                         (installed, disabled by default)
```

ka9q-radio uses its native hardware interfaces for the RX-888 MkII, HackRF, and RTL-SDR paths. SoapySDR is available for the optional direct-access application ecosystem; it does not sit between these radios and `radiod`.

## Supported platforms

The current target operating system is Ubuntu Server 24.04 LTS on:

- amd64/x86_64 systems, typically an Intel i5-class host with 16 GB RAM and at least 128 GB storage
- arm64/aarch64 systems, including Raspberry Pi 5 with 8 GB RAM and at least 64 GB storage

Actual compute, USB, network, and storage requirements depend on the SDR sample rates and the number and type of downstream channels.

## SIGedge installation and setup

On a fresh Ubuntu Server 24.04 LTS installation:

```bash
sudo apt update
sudo apt upgrade
sudo apt install -y build-essential cmake git
git clone https://github.com/joecupano/SIGedge.git
cd SIGedge
./SIGedge setup
```

Setup presents device and service choices, installs the selected components, and reboots the system when complete. RTL-SDR and HackRF are the default device selections; other supported devices can be selected during setup or installed later:

```bash
SIGedge device install <device>
```

Installation and activation are always kept separate, for both deployment paths:

- The standard setup installs SDR drivers, ka9q-radio support, and direct-access (SoapySDR) plumbing.
- No radio-specific `radiod` instance is configured, enabled, or started by default.
- Direct-access network-service plumbing (SoapyRemote) is installed, but its network service is left disabled and stopped by default.
- The operator must explicitly choose a service path per device and enable it.

### Package management

List the package library and show installed entries:

```bash
SIGedge list library
SIGedge list installed
SIGedge list packages
```

Manage an individual package with:

```bash
SIGedge install <package>
SIGedge remove <package>
SIGedge purge <package>
```

Build-capable packages may also support:

```bash
SIGedge build <package>
SIGedge package <package>
```

## ka9q-radio: use and setup

`ka9q-radio` is the primary, recommended way to get RF/IQ/audio out of a SIGedge node onto the network. `radiod` owns the SDR hardware; consumers subscribe to its multicast RTP streams rather than opening the device themselves.

### Install ka9q-radio

Upstream ka9q-radio ships its own native Debian packaging, split into about 18 binary packages (one per front end/subsystem). SIGedge builds and installs only the subset its reference missions use: the core daemon, shared files, the `rx888`/`hackrf`/`rtlsdr` front ends, and the interactive tools.

Reproducible, dpkg-tracked path (recommended — `remove`/`purge` work cleanly against it afterward):

```bash
./SIGedge package ka9q-radio   # builds .deb files into debs/ka9q-radio/
./SIGedge install ka9q-radio   # installs them via apt-get
```

Quick manual test-build path (raw `make install` to `/usr/local`, not tracked by dpkg; clean up with `make uninstall`/`make purge` in the source tree, not `SIGedge remove`):

```bash
./SIGedge build ka9q-radio
```

`./SIGedge setup` and `scripts/setup_services` use the packaged path automatically once `debs/ka9q-radio/` has been populated by `SIGedge package ka9q-radio`; otherwise they fall back to the build path on a clean checkout.

Verify the install:

```bash
command -v radiod control monitor
systemctl is-active avahi-daemon
```

### Configure and activate a mission

SIGedge includes a separate configuration layer for radio missions, kept deliberately independent of installation. The current reference configurations are:

| SDR | Channel | Mode | Service instance |
|---|---:|---|---|
| RX-888 MkII | WWV, 10.000 MHz | AM | `radiod@rx888-wwv` |
| HackRF | APRS, 144.390 MHz | FM/NBFM | `radiod@hackrf-aprs` |
| RTL-SDR | Amateur simplex, 144.650 MHz | FM/NBFM | `radiod@rtlsdr-simplex` |

Running the configuration script is an explicit opt-in. For example, to generate the HackRF reference instance without enabling or starting it:

```bash
KA9Q_IFACE=<your-iface> KA9Q_ENABLE_SERVICES=0 KA9Q_START_SERVICES=0 \
  bash scripts/cfg_ka9q-radio hackrf
```

Review the generated `/etc/radio/radiod@hackrf-aprs.conf`, then enable and start that receiver explicitly:

```bash
sudo systemctl enable --now radiod@hackrf-aprs
```

The configuration script also accepts `rx888`, `rtlsdr`, or `all`. Set `KA9Q_IFACE` when multicast must use a specific network interface (recommended on any host with more than one). Multicast TTL defaults to 1 for local-segment distribution.

Confirm a receiver is actually up:

```bash
systemctl status radiod@hackrf-aprs
avahi-browse -art
```

Full deployment details, RX-888 firmware bring-up, and current implementation limitations are documented in [KA9Q-DEPLOYMENT.md](KA9Q-DEPLOYMENT.md).

## Direct SDR use, including SoapySDR

Some applications need to open an SDR directly rather than consuming a `radiod` multicast stream — for example, SDRangel, OpenWebRX+, GQRX, CubicSDR, or vendor tools like `hackrf_transfer`/`rtl_tcp`. SIGedge installs the plumbing for this path but does not activate it by default, and it is a separate deployment from ka9q-radio: **do not point a direct-access app at a device `radiod` already owns.**

`./SIGedge setup` (via `scripts/setup_devices`) installs:

- Generic SoapySDR tooling and headers (`soapysdr-tools`, `libsoapysdr-dev`) for applications that link against SoapySDR locally on the same host.
- The RX-888 SoapySDR driver (SDDC_Driver), for direct-access RX-888 use outside of ka9q-radio.
- `soapyremote-server` and `soapysdr-module-remote`, for exposing SoapySDR devices to *remote* network clients over SoapyRemote's own protocol.

### Local direct access

An application built against SoapySDR (or a device-specific tool such as `rtl_tcp`, `hackrf_transfer`, `hackrf_info`) can open a locally attached, supported SDR directly once its driver package is installed via `SIGedge device install <device>`. No additional SIGedge service needs to be enabled for this — it's just the application and the hardware.

### Remote direct access (SoapyRemote)

`soapyremote-server` lets a remote SoapySDR client discover and stream from this host's SDRs over the network. Because that's a much bigger exposure than local-only access, SIGedge always leaves it **disabled and stopped** after install — enabling it is an explicit, separate opt-in:

```bash
sudo systemctl enable --now soapyremote-server.service
```

Verify it's actually running before relying on it, and stop it when you're done:

```bash
systemctl is-active soapyremote-server.service
avahi-browse -rt _soapy._tcp   # confirms it's discoverable on the network
sudo systemctl disable --now soapyremote-server.service
```

Before enabling it, make sure none of the SDRs it would expose are already owned by a running `radiod` instance (`systemctl status radiod@*`) — SoapyRemote does not know or care that another process has a device open, and a collision there fails at the driver/USB level, not gracefully.

## Network and hardware notes

- Use a USB 3.x SuperSpeed path for the RX-888 MkII. The initial target sample rate is 64.8 Msps.
- Bind multicast deliberately on hosts with multiple Ethernet, Wi-Fi, VPN, container, or management interfaces.
- Disable onboard Bluetooth and Wi-Fi on dedicated receive nodes when they are unnecessary and local RF emissions are a concern.
- Size powered USB hubs and power supplies for the attached devices; do not assume every hub port can supply its maximum current simultaneously.

## Further reading

- [KA9Q-DEPLOYMENT.md](KA9Q-DEPLOYMENT.md) — full ka9q-radio deployment instructions, RX-888 firmware bring-up, and current implementation limitations.
- [NETWORKING.md](NETWORKING.md) — how ka9q-radio's multicast addressing actually resolves (`dns = yes` vs. hashed), and this deployment's static address scheme.
- [PROJECT_STATE.md](PROJECT_STATE.md) — what's actually been installed, tested, or found broken on a live host, as distinct from what the scripts and docs describe in general.
- [KISMET-CHECKLIST.md](KISMET-CHECKLIST.md) — validation status and open items for Kismet as a protocol-layer monitor alongside `radiod`.
- [ai/README.md](ai/README.md) — bridges/adapters exposing `radiod` multicast channels to AI consumers (the "APIs / MCP" branch of the architecture diagram above).
