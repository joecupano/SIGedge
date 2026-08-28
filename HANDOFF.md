# SIGedge SDR Platform — Codex Handoff

## Purpose

This document transfers context for ongoing development of the SIGedge software-defined radio (SDR) edge platform.

The current work focuses on integrating:

- `ka9q-radio`
- RX-888 MkII
- HackRF
- RTL-SDR

The relevant scripts have already been added to a local repository that is part of the larger SDR platform project.

**Important development constraint:** preserve the existing repository's coding style, structure, control flow, environment-variable conventions, package lifecycle, naming conventions, and operational behavior unless the current implementation prevents correct operation. Do not refactor simply to make the code more idiomatic, modern, abstract, or stylistically different.

When a local style choice conflicts with functionality, correctness takes precedence, but changes should be as narrow as possible.

---

# 1. Development Principles

## 1.1 Preserve Repository Style

Before changing any script:

1. Inspect neighboring package/configuration scripts in the repository.
2. Follow their:
   - indentation
   - comment style
   - banner formatting
   - `case` statement flow
   - use of `;;&`
   - environment-variable conventions
   - `sudo` conventions
   - source/build/package/install lifecycle
   - package tracking mechanisms
   - directory layout
   - naming patterns
3. Avoid introducing frameworks, helper libraries, shell abstractions, or large structural rewrites unless required for correctness.
4. Prefer local fixes over broad cleanup.

The existing SIGedge flow is authoritative unless it breaks the required implementation.

---

## 1.2 Scripts May Be Sourced

Package/configuration scripts may be called by a parent Bash script using:

```bash
source <script> <action>
```

The invoking user has `sudo` privileges.

Because scripts may be sourced:

- Avoid changing shell options globally unless the surrounding repo already does so.
- Do not introduce `set -e`, `set -u`, or `set -o pipefail` into a sourced child script unless that is already the repository convention.
- Prefer `return` over `exit` for errors when returning control to the parent shell.
- Avoid changing the caller's working environment unnecessarily.
- Preserve environment variables supplied by the parent.
- Use `sudo` for privileged operations rather than requiring the entire child script to execute as root.

If repository-local scripts use a different established pattern, follow that pattern unless it causes functional breakage.

---

# 2. Existing SIGedge Environment

The parent framework supplies environment variables such as:

```text
SIGEDGE_SOURCE
SIGEDGE_PACKAGES
SIGEDGE_DEBS
SIGEDGE_PKGLIST
SIGEDGE_INSTALLED
SIGEDGE_ETC
SIGEDGE_DESKTOP
SIGEDGE_HWARCH
SIGEDGE_BANNER_COLOR
SIGEDGE_BANNER_RESET
```

Do not replace these with hard-coded repo paths if the parent already supplies them.

Hardware architecture values currently used include:

```text
x86_64
aarch64
```

Target operating system:

```text
Ubuntu Server 24.04 LTS
```

Target CPU architectures:

```text
Intel/AMD: amd64 / x86_64
Raspberry Pi 5: arm64 / aarch64
```

---

# 3. Package Script Lifecycle

SIGedge package scripts generally expose:

```text
remove
purge
install
build
package
```

Typical structure:

```bash
case "$1" in

    remove|purge|install|build|package )
        # common banner
        ;;&

    remove )
        # remove installed package
        ;;&

    purge )
        # purge installed package/config
        ;;&

    install|build|package )
        # dependencies
        ;;&

    install )
        # install pre-built package
        ;;&

    build|package )
        # clone/build source
        ;;&

    build )
        # local install
        ;;&

    package )
        # create .deb
        ;;&

    remove|purge|install|build|package )
        # completion banner
        ;;
esac
```

Preserve this flow where practical.

Do not reorganize scripts into functions/classes/modules merely for stylistic reasons.

---

# 4. SDR Architecture

The edge platform separates SDR hardware ownership from downstream consumers.

Conceptually:

```text
                    SIGedge SDR Edge Node

   +---------------------------------------------------+
   |                                                   |
   | RX-888 MkII -----> ka9q radiod instance          |
   | HackRF ----------> ka9q radiod instance          |
   | RTL-SDR ---------> ka9q radiod instance          |
   |                                                   |
   +--------------------------+------------------------+
                              |
                       RTP/IP multicast
                              |
              +---------------+----------------+
              |               |                |
            MCP/API        Analytics         Recorders
              |               |                |
         operator control  read-only       persistence
```

`ka9q-radio` is intended to own SDR hardware used by `radiod`.

Do not assume SoapySDR sits between `radiod` and these radios.

SoapySDR may be installed elsewhere in the larger platform for other applications, but the ka9q path should remain native.

---

# 5. Radio Assignments

Current required fixed-channel assignments are:

| SDR | Frequency | Mode | Purpose |
|---|---:|---|---|
| RX-888 MkII | 10.000 MHz | AM | WWV |
| HackRF | 144.390 MHz | FM/NBFM | APRS |
| RTL-SDR | 144.650 MHz | FM/NBFM | Amateur radio voice simplex |

These are the initial reference channels, not necessarily the final limit of the platform.

Future requirements may use multiple channels per SDR.

---

# 6. RX-888 Operational Assumptions

Current design target:

```text
RX-888 MkII
64.8 Msps
ka9q-radio / radiod
Ubuntu 24.04
```

The 64.8 Msps sample rate is the intended initial production setting.

Do not assume the platform must run the RX-888 at 129.6 Msps.

The RX-888 is expected to use a USB 3.x SuperSpeed path.

High-rate USB reliability is important.

---

# 7. RX-888 Firmware Model

The RX-888 uses Cypress FX3 firmware.

Current firmware source:

```text
https://github.com/ringof/rx888-firmware.git
```

Firmware artifact:

```text
SDDC_FX3.img
```

The preferred operational model is:

```text
host stores firmware
        |
        v
radiod / RX-888 tooling loads firmware
        |
        v
FX3 RAM
```

The provisioning workflow intentionally avoids unattended permanent EEPROM/SPI flashing.

The firmware should remain recoverable and host-managed.

Expected staged location:

```text
/usr/local/share/ka9q-radio/SDDC_FX3.img
```

---

# 8. `pkg_rx888.sh`

This script runs before the ka9q-radio package script.

Responsibilities include:

- install RX-888 firmware build dependencies
- clone/build RX-888 FX3 firmware
- install RX-888 udev rules
- configure USB buffering required for high-rate RX-888 transfers
- stage `SDDC_FX3.img`
- optionally upload/test firmware when hardware is attached
- create a handoff manifest for downstream scripts

Expected manifest:

```text
/var/lib/rx888/rx888-prep.env
```

Expected manifest fields include values similar to:

```text
RX888_PREP_VERSION
RX888_OS
RX888_ARCH
RX888_FW_REPO
RX888_FW_REF
RX888_FW_COMMIT
RX888_FW_PATH
RX888_FW_SHA256
RX888_UDEV_RULE
RX888_USBFS_MEMORY_MB
RX888_VALIDATION
```

### Ownership Rule

`pkg_rx888.sh` owns RX-888-specific preparation resources.

Examples:

```text
/usr/local/share/ka9q-radio/SDDC_FX3.img
/etc/udev/rules.d/99-rx888.rules
/etc/modprobe.d/usbcore.conf
/var/lib/rx888/rx888-prep.env
```

Other scripts should not remove these unless explicitly part of RX-888 removal/purge.

---

# 9. `pkg_ka9q-radio.sh`

This script runs after RX-888 preparation when RX-888 is part of the build.

However, RX-888 is **optional**.

The ka9q-radio package script must remain usable on systems containing:

- RX-888
- HackRF
- RTL-SDR
- combinations of those radios
- other ka9q-supported SDRs in the future

Therefore:

```text
RX-888 preparation present     -> validate it
RX-888 preparation absent      -> continue normally
```

Do not make `/var/lib/rx888/rx888-prep.env` a mandatory prerequisite for installing ka9q-radio.

### Expected ka9q responsibilities

The script should:

- install required build/runtime dependencies
- install HackRF dependencies
- install RTL-SDR dependencies
- install general USB dependencies
- install/enable Avahi
- clone/build ka9q-radio when requested
- install architecture-appropriate prebuilt `.deb` when requested
- support package creation
- run `ldconfig`
- reload systemd when needed
- reload udev when needed
- verify core binaries such as:

```text
radiod
control
monitor
```

### RX-888 Integration

If:

```text
/var/lib/rx888/rx888-prep.env
```

exists, the script may:

- source the manifest
- verify firmware exists
- verify firmware SHA-256
- report RX-888 preparation status

It should not own or delete the RX-888 preparation artifacts.

---

# 10. Important `pkg_ka9q-radio.sh` Corrections Already Identified

Previous versions contained:

```bash
sudo dmesg --follow
```

inside the install/build flow.

That command blocks indefinitely and must not be used in unattended package execution.

Use bounded diagnostics if needed, for example:

```bash
sudo dmesg | tail -n 50
```

Previous code also contained:

```bash
input("Press Enter...")
```

which is not Bash syntax.

Do not reintroduce that construct.

Interactive unplug/replug requirements should be avoided in the main package lifecycle unless the surrounding repository explicitly requires interactive install behavior.

---

# 11. Package Ownership Issue to Watch

There are currently two possible ka9q install paths:

```text
install -> installs a prebuilt .deb using dpkg
build   -> may run make install
```

Removal currently assumes Debian package ownership.

This creates a potential mismatch:

```text
make install
    !=
dpkg-owned package
```

Do not perform a broad refactor solely to solve this unless needed immediately.

However, when touching this area, prefer converging toward one package ownership model if it can be done without breaking the surrounding SIGedge flow.

The preferred long-term model is:

```text
source build
     |
     v
generate .deb
     |
     v
install .deb
     |
     v
dpkg owns installed files
```

---

# 12. `cfg_ka9q-radio.sh`

This script generates radio-specific `radiod` configurations after ka9q-radio is installed.

Current intended configurations:

```text
/etc/radio/radiod@rx888-wwv.conf
/etc/radio/radiod@hackrf-aprs.conf
/etc/radio/radiod@rtlsdr-simplex.conf
```

Associated service instances:

```text
radiod@rx888-wwv
radiod@hackrf-aprs
radiod@rtlsdr-simplex
```

The generator should remain separate from the package installer.

This separation is deliberate:

```text
package installation
      !=
radio mission configuration
```

Do not merge radio configuration into `pkg_ka9q-radio.sh` unless the larger repo architecture requires it.

---

# 13. RX-888 Configuration Intent

Signal:

```text
WWV
10.000 MHz
AM
```

Hardware:

```text
RX-888 MkII
64.8 Msps
direct-sampling mode
```

Expected conceptual configuration:

```ini
[global]
hardware = rx888
status = rx888-wwv.local
mode = am

[rx888]
device = rx888
description = "SIGedge RX-888 WWV 10 MHz"
samprate = 64800000
firmware = SDDC_FX3.img

[wwv-10mhz]
freq = "10m0"
```

Before relying on exact option names, verify them against the ka9q-radio revision currently pinned or built by the repo.

Do not silently assume syntax from older documentation if the current source differs.

---

# 14. HackRF Configuration Intent

Signal:

```text
APRS
144.390 MHz
FM/NBFM
```

The tuner center may be offset from the desired channel so the wanted signal does not fall exactly at zero IF/DC.

Current default design:

```text
desired channel: 144.390 MHz
hardware center: 144.640 MHz
offset: +250 kHz
```

Conceptually:

```ini
[global]
hardware = hackrf
status = hackrf-aprs.local
mode = fm

[hackrf]
device = hackrf
frequency = 144640000

[aprs-144390]
freq = "144m390"
```

Verify current HackRF-specific keys against the actual ka9q source revision.

The downstream APRS decoder is not yet finalized.

Likely future pipeline:

```text
HackRF
  |
radiod
  |
144.390 MHz FM PCM/baseband
  |
APRS decoder / packet service
  |
MCP / analytics / upstream applications
```

---

# 15. RTL-SDR Configuration Intent

Signal:

```text
144.650 MHz
FM/NBFM
amateur-radio voice simplex
```

Current default tuner center:

```text
desired channel: 144.650 MHz
hardware center: 144.900 MHz
offset: +250 kHz
```

Conceptually:

```ini
[global]
hardware = rtlsdr
status = rtlsdr-simplex.local
mode = fm

[rtlsdr]
device = rtlsdr
samprate = 1800000
frequency = 144900000

[simplex-144650]
freq = "144m650"
```

Again, verify exact field names against the source revision actually used by SIGedge.

---

# 16. Hardware Selection and Serial Numbers

The platform may eventually contain multiple SDRs of the same model.

Configuration generation should therefore support optional serial-number selection when the ka9q driver exposes it.

Candidate environment variables currently include:

```text
RX888_SERIAL
HACKRF_SERIAL
RTLSDR_SERIAL
```

Do not invent unsupported ka9q configuration keys.

Verify driver capabilities first.

If serial-based selection is not supported for a specific front end, document the limitation rather than implementing a fake option.

---

# 17. Multicast and Networking

ka9q-radio uses multicast for its SDR service architecture.

The edge node may contain multiple interfaces, including:

```text
Ethernet
Wi-Fi
Docker bridges
Podman bridges
Kubernetes/CNI interfaces
VPN interfaces
management interfaces
```

Radio multicast should not accidentally bind to the wrong network.

Configuration generation should support an optional interface variable such as:

```text
KA9Q_IFACE
```

but should not hard-code a physical interface name unless the larger SIGedge network configuration layer already defines one.

Current default multicast TTL:

```text
1
```

This is appropriate for local-segment SDR distribution unless platform requirements change.

---

# 18. Service Startup Policy

Preferred behavior:

```text
generate config
enable service
do not automatically start unless requested
```

Reason:

- hardware may not yet be attached
- multicast interface may not yet be configured
- multiple SDRs may share USB resources
- downstream networking may not yet be ready
- validation may need to happen first

Current environment concept:

```text
KA9Q_ENABLE_SERVICES=1
KA9Q_START_SERVICES=0
```

If the larger repository already has a standardized service-start policy, follow that instead.

---

# 19. Current Compute Targets

## Intel

Minimum practical target for:

```text
1 x RX-888
64.8 Msps
~8 channels
ka9q-radio
```

is approximately:

```text
Intel N100/N150 class
8 GB RAM
```

Preferred consolidated edge platform:

```text
Intel N305 or modern Core i3/i5
16 GB RAM
NVMe storage
```

## Raspberry Pi

Supported design target:

```text
Raspberry Pi 5
8 GB RAM
Ubuntu Server 24.04 ARM64
active cooling
RX-888 at 64.8 Msps
```

Pi 5 should be treated primarily as a dedicated `radiod` appliance, not as the preferred host for heavy local AI/DSP workloads.

---

# 20. Storage Context

The platform may retain approximately 48 hours of selected-channel data.

Current preferred baseline:

```text
1 TB NVMe
```

for an edge system retaining multiple selected IQ/audio streams with operational margin.

Do not assume the platform stores the full 64.8 Msps RX-888 raw ADC stream.

Full-band RX-888 capture requires storage on the order of tens of terabytes over 48 hours and is a different architecture.

---

# 21. Future Application Architecture

Expected upstream/downstream applications may include:

```text
ka9q-radio
OpenWebRX+
SDRangel
GNU Radio
MCP server
Ollama / AI services
recorders
signal decoders
analytics
```

Do not assume all of these run on the same hardware.

Preferred separation:

```text
SDR ownership / real-time DSP
        |
        v
ka9q radiod edge node
        |
        v
multicast/network services
        |
        +--> operator tools
        +--> analysts
        +--> decoders
        +--> recorders
        +--> MCP
        +--> AI/analytics
```

---

# 22. Analyst vs Operator Control Model

Longer-term design distinguishes:

### Analyst

```text
read-only
subscribe to streams
read status/telemetry
no direct hardware control
```

### Operator

```text
authenticated control
frequency/mode/channel changes
radio control
stream access
```

Expected control model:

```text
Operator
   |
MCP/API
   |
ka9q control protocol
   |
radiod
   |
SDR
```

This is not yet fully implemented.

Avoid embedding unrestricted hardware-control assumptions into downstream applications.

---

# 23. Code Review Priorities for Codex

When reviewing the current repository, prioritize correctness in this order:

1. **Does the existing repo control flow work?**
2. **Are sourced scripts safe for the parent shell?**
3. **Are package ownership/remove/purge behaviors internally consistent?**
4. **Does ka9q-radio compile on Ubuntu 24.04 amd64 and arm64?**
5. **Are RX-888 firmware and udev preparation correct?**
6. **Does RX-888 operate at 64.8 Msps reliably?**
7. **Do HackRF and RTL-SDR front ends compile and load?**
8. **Are the generated `radiod` configs valid for the actual ka9q revision?**
9. **Does multicast select the intended network interface?**
10. **Do systemd instances map correctly to generated config filenames?**
11. **Can each SDR operate independently?**
12. **Can multiple SDR instances operate simultaneously without device-selection conflicts?**

---

# 24. Validate Against Source, Not Assumptions

ka9q-radio changes over time.

Before modifying configuration keys or driver assumptions, inspect the version actually used by the repository.

Check:

```bash
git -C <ka9q-source-dir> rev-parse HEAD
```

Then inspect:

```text
docs/
radio hardware driver source
example configuration files
systemd service templates
Makefile/install targets
```

Do the same for RX-888 firmware.

Where source and older examples disagree:

```text
current pinned source
    >
current upstream documentation
    >
older README/wiki examples
```

Do not change working repository syntax solely because a different upstream branch looks newer.

---

# 25. Avoid Unnecessary Refactoring

Do not automatically replace:

```text
case + ;;&
individual apt install calls
existing banner code
repo-specific variable names
existing directory layout
simple Bash
```

with:

```text
new frameworks
generic package abstractions
large helper libraries
arrays/functions everywhere
new config formats
new directory structures
Docker-only deployment
Ansible-only deployment
```

unless the current implementation cannot meet requirements.

A change should solve a real problem.

Examples of justified changes:

- sourced script uses `exit` and kills the parent unexpectedly
- command blocks forever
- invalid Bash syntax
- incorrect ka9q config syntax
- package purge deletes another package's owned resources
- service name does not match config filename
- firmware path is wrong
- driver dependency is missing
- USB settings prevent RX-888 operation
- code assumes RX-888 is mandatory when it is optional

Examples of unjustified changes:

- converting a working `case` structure into a new command framework
- renaming all variables for consistency
- replacing repo banner output because another style looks cleaner
- splitting a short script into several modules without need
- making shell code "more modern" without functional benefit

---

# 26. Recommended Immediate Next Work

Codex should begin by inspecting the actual repository rather than modifying files immediately.

Recommended sequence:

```text
1. Inspect repository structure.
2. Identify several neighboring pkg_*.sh scripts.
3. Identify several cfg_*.sh scripts if they exist.
4. Compare:
      pkg_rx888.sh
      pkg_ka9q-radio.sh
      cfg_ka9q-radio.sh
   against local repo conventions.
5. Identify functional deviations only.
6. Inspect the ka9q-radio source/version used by the project.
7. Validate actual RX-888/HackRF/RTL-SDR configuration syntax.
8. Make minimal corrections.
9. Run bash syntax checks.
10. Run shellcheck only as advisory unless repo treats it as authoritative.
11. Validate build/package paths.
12. Validate systemd instance/config mapping.
13. Produce a concise change summary.
```

Do not begin by wholesale rewriting the three scripts.

---

# 27. Suggested Validation Commands

At minimum:

```bash
bash -n pkg_rx888.sh
bash -n pkg_ka9q-radio.sh
bash -n cfg_ka9q-radio.sh
```

Where appropriate:

```bash
shellcheck pkg_rx888.sh
shellcheck pkg_ka9q-radio.sh
shellcheck cfg_ka9q-radio.sh
```

Treat ShellCheck findings in context.

Do not change repository style simply to eliminate non-functional ShellCheck warnings.

Validate ka9q binaries:

```bash
which radiod
which control
which monitor
```

USB:

```bash
lsusb
lsusb -t
```

RX-888:

```bash
ls -l /usr/local/share/ka9q-radio/SDDC_FX3.img
cat /var/lib/rx888/rx888-prep.env
```

Services:

```bash
systemctl status radiod@rx888-wwv
systemctl status radiod@hackrf-aprs
systemctl status radiod@rtlsdr-simplex
```

Logs:

```bash
journalctl -u radiod@rx888-wwv
journalctl -u radiod@hackrf-aprs
journalctl -u radiod@rtlsdr-simplex
```

Multicast:

```bash
ip maddr show
```

mDNS:

```bash
avahi-browse -art
```

---

# 28. Current Files of Interest

At the time of this handoff, the primary files are:

```text
pkg_rx888.sh
pkg_ka9q-radio.sh
cfg_ka9q-radio.sh
```

These are already in the local repository.

Inspect their actual repo versions before modifying them.

Do not assume the versions described here are byte-for-byte identical to earlier generated drafts.

The repository copies are the source of truth.

---

# 29. Definition of Done for the Current Integration

The current SDR integration can be considered functionally complete when:

### RX-888

```text
pkg_rx888.sh install
    succeeds

SDDC_FX3.img
    is staged correctly

RX-888
    enumerates over USB 3.x

radiod
    can initialize RX-888 at 64.8 Msps

WWV 10 MHz
    can be received as AM
```

### HackRF

```text
HackRF
    enumerates correctly

radiod
    opens the intended HackRF

144.390 MHz
    can be received in FM/NBFM

output
    is suitable for APRS decoding
```

### RTL-SDR

```text
RTL-SDR
    enumerates correctly

radiod
    opens the intended RTL-SDR

144.650 MHz
    can be received in FM/NBFM

output
    is suitable for voice monitoring
```

### Platform

```text
all three configurations
    can coexist

systemd service names
    map to config files correctly

multicast
    leaves through the intended interface

remove/purge
    respect package ownership

scripts
    remain consistent with SIGedge repo style
```

---

# 30. Core Instruction to Codex

**Treat the existing local repository as an established codebase, not a blank-slate prototype.**

Understand the repository first.

Preserve its style and execution model.

Make the smallest changes necessary for:

- correctness
- reliable RX-888 operation
- multi-SDR ka9q support
- Ubuntu 24.04 compatibility
- amd64 and arm64 support
- predictable package lifecycle
- predictable systemd behavior
- correct multicast operation

Do not redesign working code merely because another implementation would be cleaner.

