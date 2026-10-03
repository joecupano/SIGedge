# config

Various config files.

**99-sigedge-sdr.rules**  - udev rule installed by `scripts/sdr-access install` (run by `setup_core`):
every supported SDR's USB node is `0660 root:sdr` in every state (RX-888 bootloader and firmware
modes included), overriding the vendor rules' mix of `plugdev` 0666 and `radio` 0660. Service
accounts join the `sdr` group via `scripts/sdr-access sync`.
**blacklist-msi.conf**    - Used by RTLSDR to blacklist drivers
**banner_sigedge**        - Banner screens called by SIGedge setup

**rtltcp.service**        - Optional direct-access service instead of radiod, deployed by
`scripts/setup_services` when `rtltcpsrv` is selected. No package script -- just wraps
`rtl_tcp`, which the rtlsdr device driver already installs. Reads an optional
`RTLTCP_SERIAL=<serial>` from `/etc/default/rtltcp` (via `EnvironmentFile=-`) to pin a
specific unit when more than one RTL-SDR is attached. `SIGedge assign <rtl-sdr> rtltcp`
writes that file and starts the unit (`scripts/adapters/rtltcp`).
**sdrangelsrv.service**   - Optional direct-access service instead of radiod, deployed by
`scripts/setup_services` (via `packages/pkg_sdrangelsrv`) when `sdrangelsrv` is selected.
Whole-host: SDRangel server can open any SDR, so `SIGedge assign` won't mix it with other owners
without `--force`.
**soapysdrsrv.service**   - Optional direct-access service instead of radiod, deployed by
`scripts/setup_services` when `soapysdrsrv` is selected. No package script -- just wraps
`SoapySDRServer`, which `soapysdr-tools` already installs unconditionally. Whole-host, like
SDRangel server.

**radiod@\<instance>.conf** - Proven radiod reference-mission templates, deployed as-is by
`scripts/cfg_ka9q-radio` (`##TTL##`/`##CENTER_HZ##`/`##IFACE##`/`##SERIAL##` are the only
placeholders it fills in per host; everything else is trusted, checked-in convention). Each
uses `dns = yes` for a static multicast `data` address (a literal `239.192.x.x` right in the
template) and a static `status` address (still the `sigedge-<hardware>.local` name here --
`scripts/cfg_ka9q-radio` pins it to a fixed address via a `/etc/hosts` entry, since a
literal address in `status` itself doesn't work; see NETWORKING.md's "How the override
actually works"). See [NETWORKING.md](../NETWORKING.md)'s "Current static assignment"
table for the actual address-per-instance assignment. `scripts/ka9q-radio-builder` is the
separate, interactive tool for building or editing configs beyond these fixed reference
missions.
