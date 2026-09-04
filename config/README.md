# config

Various config files.

**blacklist-msi.conf**    - Used by RTLSDR to blacklist drivers
**banner_sigedge**        - Banners screens called by SIGpi-setup

**openwebrx.service**     - Optional Service instead of radiod (switch safely with `scripts/service_toggle`)
**rtltcp.service**        - Optional Service instead of radiod
**sdrangelsrv.service**   - Optional Service instead of radiod

**radiod@\<instance>.conf** - Proven radiod reference-mission templates, deployed as-is by
`scripts/cfg_ka9q-radio` (`##TTL##`/`##CENTER_HZ##`/`##IFACE##`/`##SERIAL##` are the only
placeholders it fills in per host; everything else is trusted, checked-in convention). Each
uses `dns = yes` for a static multicast `data` address (a literal `239.192.x.x` right in the
template) and a static `status` address (still the `sigedge-<hardware>.local` name here --
`scripts/cfg_ka9q-radio` pins it to a fixed address via a `/etc/hosts` entry, since a
literal address in `status` itself doesn't work; see NETWORKING.md's "How the override
actually works"). See [NETWORKING.md](../NETWORKING.md)'s "Current static assignment"
table for the actual address-per-instance assignment. `scripts/cfg_ka9q-radio_tui` is the
separate, interactive tool for building or editing configs beyond these fixed reference
missions.
