# SIGedge

If you've plugged an RTL-SDR or a HackRF straight into SDRangel, GQRX, CubicSDR, or a similar app and listened to the world go by, you already understand the core of what SIGedge does — it just gives that same radio, and others like it, two more ways to work: as a browser-based receiver anyone on the network can open, and as a radio *server* that many apps and services can share at once instead of one app locking up the USB device by itself.

SIGedge is an RF edge platform: it takes SDR hardware attached to one host and makes it usable — as raw IQ or already-demodulated audio — by upstream services on that host or across the network. It doesn't replace SDRangel, GQRX, or OpenWebRX+; it's the layer underneath that decides how those apps, and others like Kismet or an AI/analytics pipeline, get access to the hardware.

## Supported SDR hardware

The three devices used throughout this documentation's reference examples:

| Device | Role |
|---|---|
| RX-888 MkII | Wideband HF receiver |
| HackRF One | Wideband TX/RX |
| RTL-SDR (v3/v4) | Low-cost VHF/UHF receiver |

Also supported, installable during setup or any time afterward with `SIGedge device install <device>`: BladeRF, Ettus Research USRP (UHD), RigExpert Fobos, KerberosSDR, LimeSDR, PlutoSDR, and SDRplay — plus Ubertooth One, a Bluetooth/BLE capture device used with Kismet rather than an RF receiver in the SDR sense. Run `SIGedge list library` for the full, current package list.

## From a dedicated SDR app to a shared radio platform

The apps in the SDR world you already know — SDRangel, GQRX, CubicSDR, `rtl_tcp`, `hackrf_transfer` — all work the same way: one app opens the radio directly, either locally or over the network via SoapyRemote, and has it exclusively for as long as it's running. SIGedge supports that model exactly as-is; nothing about it changes.

What SIGedge adds is a second model. Instead of one app owning the radio, a background service called `radiod` (from the [ka9q-radio](https://github.com/ka9q/ka9q-radio) project) owns it once, continuously, and republishes its IQ/audio/control data as an IP multicast network stream — so any number of consumers (other apps, other hosts, browser sessions, recorders, an AI pipeline) can listen to the *same* radio at the same time, without any of them opening the USB device themselves.

```text
SDR hardware -> ka9q-radio radiod -> RTP/IP multicast -> any number of network consumers
SDR hardware -> direct-access app (SoapySDR / SoapyRemote) -> one exclusive owner
```

Both models install side by side; you choose, per device, which one a given radio is doing at any moment. **A single physical SDR can only be in one of these two states at a time** — see "Device ownership across services" below.

## Services

Each of the following runs on top of one of the two models above. This section covers only what each one gives you and how it fits together — full setup steps live in the linked deployment document.

### Direct SDR access (SoapySDR / SoapyRemote)

**Delivers:** exactly the workflow you already know. SDRangel, GQRX, CubicSDR, or a vendor tool like `hackrf_transfer`/`rtl_tcp` opens a SIGedge-attached radio directly, either on the same host or, via SoapyRemote, from another machine on the network.

**How it fits together:** the application links against SoapySDR (or a device-specific driver) and talks to the hardware directly — SIGedge installs the driver/plumbing but puts nothing of its own between the app and the radio. Only one such application can hold a given device at a time.

**Setup:** device drivers install via `SIGedge device install <device>`; SoapyRemote's own network service ships disabled and is an explicit opt-in. See [Direct SDR use, including SoapySDR](#direct-sdr-use-including-soapysdr) below.

### ka9q-radio — shared radio server

**Delivers:** the radio becomes a standing network resource — any number of consumers can subscribe to it at once, instead of "whichever app has it, nothing else can touch it."

**How it fits together:**

```text
                              SIGedge node

  RX-888 MkII -----+       +-------------------+
  HackRF ----------+------>| ka9q-radio radiod |----> RTP/IP multicast
  RTL-SDR ---------+       +-------------------+              |
                                                              +--> APIs / MCP
                                                              +--> analytics
                                                              +--> recorders
                                                              +--> decoders
```

`radiod` uses ka9q-radio's native hardware interfaces for the RX-888 MkII, HackRF, and RTL-SDR paths; consumers subscribe to its multicast streams instead of opening the device.

**Setup:** full install, per-mission configuration (frequency/mode presets for each supported radio), and activation steps are in [KA9Q-DEPLOYMENT.md](KA9Q-DEPLOYMENT.md).

### OpenWebRX+ — browser waterfall and audio

**Delivers:** a receiver reachable from any browser, no client app to install — the easiest way to give someone else on the network, or yourself remotely, a listen without a dedicated SDR app.

**How it fits together:** it's a *direct-access* consumer of the hardware, the same model as SDRangel/GQRX above, so it's mutually exclusive with a `radiod` mission on the same device. The two are alternative deployments for the same radio, switched between with `scripts/service_toggle` rather than run at the same time.

**Setup:** the confirmed-working RX-888 install path (via the luarvique PPA, not `SIGedge install openwebrx`) is documented in KA9Q-DEPLOYMENT.md's ["RX-888 in OpenWebRX+"](KA9Q-DEPLOYMENT.md#rx-888-in-openwebrx--confirmed-working-path-not-packagespkg_openwebrx) section, alongside the switch-over instructions.

### Kismet — WiFi/Bluetooth/RF protocol monitor

**Delivers:** passive monitoring and device-tracking for WiFi, Bluetooth, and ISM-band RF traffic — a different job than tuning a signal by hand, closer to a network/RF security tool than a receiver app.

**How it fits together:** a protocol-layer service that runs *alongside* `radiod`/OpenWebRX+, not an alternative to either. It needs its own WiFi adapter (monitor-mode capable) and, optionally, its own RTL-SDR (rtl433) or Ubertooth unit for ISM-band and Bluetooth capture.

**Setup:** full build/install, capture-source configuration, and troubleshooting are in [KISMET-DEPLOYMENT.md](KISMET-DEPLOYMENT.md).

### AI and analytics bridges

**Delivers:** early-stage tooling for asking an LLM (via Ollama) what's active on a `radiod` channel, rather than watching a waterfall yourself.

**How it fits together:** reads `radiod`'s multicast channel status/audio, read-only, limited to whichever channels an operator has explicitly listed.

**Setup:** [ai/README.md](ai/README.md).

### Decoders — turning a radiod channel into decoded output

**Delivers:** the "decoders" leaf of the architecture diagram above — a `radiod` audio channel feeding an actual protocol/signal decoder (APRS, POCSAG, weather-satellite images, ...) instead of only being available to listen to.

**How it fits together:** `ka9q-radio-tools`' `pcmrecord` reads one channel's multicast audio and pipes it, raw, into a decoder that already accepts an audio stream on stdin — the same shape as the well-known `rtl_fm | direwolf` or `rtl_fm | multimon-ng` patterns, just with `pcmrecord` in place of `rtl_fm`.

**Setup:** [decoders/README.md](decoders/README.md); `decoders/hackrf-aprs-direwolf` is the first instance, bridging the `hackrf-aprs` reference mission into `direwolf`.

## Device ownership across services

Every service above eventually touches physical hardware, and **an SDR must have exactly one active owner at a time.** Do not start a direct-access application (SDRangel, OpenWebRX+, GQRX, `rtl_tcp`, ...) against a device a `radiod` instance already owns, and do not start `radiod` for a device a direct-access app or SoapyRemote already has open. Two different physical SDRs on the same host can run under two different owners simultaneously — for example, HackRF under `radiod` while an RTL-SDR is handed to a direct-access app — the constraint is per device, not per host.

Kismet extends the same rule to its own capture sources. Whichever devices it opens directly — RTL-SDR via `kismet_cap_sdr_rtl433`, Ubertooth via `kismet_cap_ubertooth_one` — still need exactly one owner. When two always-on services genuinely need the same device *type* at once (`radiod` running an RTL-SDR mission while Kismet also wants RTL-SDR-based ISM-band capture, for instance), the resolution is one physical unit per consumer, each pinned to its own service by USB serial number rather than left to auto-detect and risk both landing on the same dongle — RTL-SDR dongles are cheap enough that a dedicated unit per consumer is the practical default; RX-888/HackRF's higher cost is exactly why the discipline-only, one-unit-total model above still applies to them instead.

`scripts/device-inventory.sh` shows what's physically attached side by side with whatever already claims it (`radiod`'s per-mission `serial =` lines, Kismet's `rtl433-sn-<serial>`/`ubertooth<N>` source lines) — check it before enabling a new service on a device that might already be spoken for.

## Supported platforms

The current target operating system is Ubuntu Server 24.04 LTS or Debian GNU/Linux 13 (Trixie, including Raspberry Pi OS Desktop, which is Trixie-based) on:

- amd64/x86_64 systems, typically an Intel i5-class host with 16 GB RAM and at least 128 GB storage
- arm64/aarch64 systems, including Raspberry Pi 4B/5 with 4-8 GB RAM and at least 64 GB storage

Actual compute, USB, network, and storage requirements depend on the SDR sample rates and the number and type of downstream channels. See [PROJECT_STATE.md](PROJECT_STATE.md) for what's actually been validated on a live host, as distinct from this general target.

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

## Direct SDR use, including SoapySDR

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
- [KISMET-DEPLOYMENT.md](KISMET-DEPLOYMENT.md) — full Kismet build/install, capture-source configuration (WiFi, RTL-SDR, Ubertooth), and troubleshooting.
- [KISMET-CHECKLIST.md](KISMET-CHECKLIST.md) — validation status and open items for Kismet as a protocol-layer monitor alongside `radiod`.
- [ai/README.md](ai/README.md) — bridges/adapters exposing `radiod` multicast channels to AI consumers (the "APIs / MCP" branch of the architecture diagram above).
- [decoders/README.md](decoders/README.md) — bridges feeding `radiod` multicast audio into decode-side applications (the "decoders" branch of the architecture diagram above).
