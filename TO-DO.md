# TO-DO

## Open

- [ ] **Confirm `RESETFX3` works under both RX-888 firmwares.** The handoff
  (`scripts/handoff/rx888`) resets the FX3 with `fx3_cmd reset`, falling back
  to `fx3_cmd usbreset`. rx888-firmware documents both for its own
  SDDC_FX3 image, but neither has been run here, and nobody has checked the
  firmware ka9q-radio's `rx888_boot` loads or the one RX888MK2-Soapy
  uploads. Needs a host with
  ka9q-radio installed: assign the RX-888 to `radiod`, then to `openwebrx`,
  and check it re-enumerates as `04b4:00f3` without being unplugged.

## Done

- [x] **Validate per-device assignment on real hardware (sigedge-mac),
  2026-10-02.** Removed the duplicate `soapysdr0.8-module-hackrf`
  (`driver-check` clean), installed the `sdr` access model (both devices
  `root:sdr 660` once the rule was renamed `10-sigedge-sdr.rules`),
  adopted OpenWebRX+'s devices, and moved the HackRF out of OpenWebRX+ and
  back. Its entry returned pinned to its serial with all three profiles, the
  RX-888's gain and waterfall settings and all other settings were
  unchanged, and `settings.json` stayed owned by `openwebrx`. Both radios
  streamed in the web UI afterwards (HackRF on SIGedge's SoapyHackRF, RX-888
  through the `sdr` group). Not exercised:
  `radiod` and `rtltcp` adapters (neither installed here) and the RX-888
  handoff (see above).

- [x] **shellcheck, 2026-10-02.** shellcheck 0.10.0 over `sdr-assign`,
  `sdr-access`, `driver-check`, `service_toggle`, `device-inventory.sh`,
  `handoff/rx888`, `lib/sdr_common.sh`, `adapters/*` and
  `tests/sdr-assign-test.sh`: clean at the default checks after removing
  two dead tables from `device-inventory.sh`. The optional checks report
  only style preferences the rest of SIGedge doesn't follow either
  (SC2250 `${var}` braces, SC2312 masked return values, SC2249 default
  `case` branches).

- [x] **Rebuild `debs/direwolf_current_arm64.deb`, 2026-10-02.** Built on
  sigpi (Raspberry Pi, arm64) with `./SIGedge package direwolf` (commit
  `6eb4a35`). The package now declares its Depends, including
  `libgps30t64` and `libhamlib4t64`, installs cleanly, has no missing
  libraries, and runs (`Dire Wolf Release 1.8.1`). Both the amd64 and
  arm64 packages are now built against libgps 30.
