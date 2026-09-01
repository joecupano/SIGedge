# config

Various config files.

**blacklist-msi.conf**    - Used by RTLSDR to blacklist drivers
**banner_sigedge**        - Banners screens called by SIGpi-setup

**openwebrx.service**     - Optional Service instead of radiod (switch safely with `scripts/service_toggle`)
**rtltcp.service**        - Optional Service instead of radiod
**sdrangelsrv.service**   - Optional Service instead of radiod

**radiod@\<instance>.conf** - Proven radiod reference-mission templates, deployed as-is by
`scripts/cfg_ka9q-radio` (`##TTL##`/`##CENTER_HZ##`/`##IFACE##`/`##SERIAL##` are the only
placeholders it fills in per host; everything else is trusted, checked-in convention). See
[NETWORKING.md](../NETWORKING.md) for the `sigedge-<hardware>.local` / `sigedge-<channel>.local`
naming these files follow. `scripts/cfg_ka9q-radio_tui` is the separate, interactive tool for
building or editing configs beyond these fixed reference missions.
