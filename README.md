# SIGedge

SIGedge is an SDR edge platform for turning attached radio hardware into RF, IQ, and audio services for network-connected consumers. Typical consumers include analytics and AI workflows, recorders, decoders, operator tools, SDRangel, OpenWebRX+, and custom applications.

The preferred interface from a SIGedge node to upper-layer network services is **ka9q-radio**. Its `radiod` instances own the selected SDR hardware and publish control, status, IQ, and demodulated streams over IP multicast.

```text
SDR hardware -> ka9q-radio radiod -> RTP/IP multicast -> network services
```

SIGedge also installs plumbing that allows applications to access supported SDRs directly, including SoapySDR-based paths. This is an alternative integration path for applications that cannot consume ka9q-radio services; it is not the primary SIGedge service architecture.

## Default service policy

Installation and activation are separate:

- The standard setup installs SDR drivers and supporting components.
- ka9q-radio support is installed, but no radio-specific `radiod` instance is configured, enabled, or started by default.
- Direct SDR network-service plumbing is installed, but it is not enabled by default.
- The operator must explicitly choose a service path and the SDR assigned to it.

Only one service should own an SDR at a time. Do not start a direct-access service for a device already owned by `radiod`, or start `radiod` for a device in use by SDRangel, OpenWebRX+, SoapyRemote, `rtl_tcp`, or another application.

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

## Setup

On a fresh Ubuntu Server 24.04 LTS installation:

```bash
sudo apt update
sudo apt upgrade
sudo apt install -y build-essential cmake git
git clone https://github.com/joecupano/SIGedge.git
cd SIGedge
./SIGedge setup
```

Setup presents device and service choices, installs the selected components, and reboots the system when complete. RTL-SDR and HackRF are the default device selections; other supported devices can be selected during setup or installed later.

> **Current ka9q-radio packaging status:** the repository does not include the prebuilt ka9q-radio `.deb` files expected by the standard install action. A clean checkout must currently use the source-build path described in [KA9Q-DEPLOYMENT.md](KA9Q-DEPLOYMENT.md) or supply the appropriate package.

To add a device after initial setup:

```bash
SIGedge device install <device>
```

## Package management

List the package library and show installed entries:

```bash
SIGedge list library
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

## Opting in to ka9q-radio

SIGedge includes a separate configuration layer for radio missions. The current reference configurations are:

| SDR | Channel | Mode | Service instance |
|---|---:|---|---|
| RX-888 MkII | WWV, 10.000 MHz | AM | `radiod@rx888-wwv` |
| HackRF | APRS, 144.390 MHz | FM/NBFM | `radiod@hackrf-aprs` |
| RTL-SDR | Amateur simplex, 144.650 MHz | FM/NBFM | `radiod@rtlsdr-simplex` |

Running the configuration script is an explicit opt-in. For example, to generate and enable the HackRF reference instance without starting it:

```bash
KA9Q_ENABLE_SERVICES=1 KA9Q_START_SERVICES=0 \
  bash scripts/cfg_ka9q-radio hackrf
```

After reviewing the generated configuration, start that receiver explicitly:

```bash
sudo systemctl start radiod@hackrf-aprs
```

The configuration script also accepts `rx888`, `rtlsdr`, or `all`. Set `KA9Q_IFACE` when multicast must use a specific network interface. Multicast TTL defaults to 1 for local-segment distribution.

## Network and hardware notes

- Use a USB 3.x SuperSpeed path for the RX-888 MkII. The initial target sample rate is 64.8 Msps.
- Bind multicast deliberately on hosts with multiple Ethernet, Wi-Fi, VPN, container, or management interfaces.
- Disable onboard Bluetooth and Wi-Fi on dedicated receive nodes when they are unnecessary and local RF emissions are a concern.
- Size powered USB hubs and power supplies for the attached devices; do not assume every hub port can supply its maximum current simultaneously.

Current ka9q-radio deployment instructions and implementation limitations are documented in [KA9Q-DEPLOYMENT.md](KA9Q-DEPLOYMENT.md). Development context for the current integration work is recorded in [HANDOFF.md](HANDOFF.md).
