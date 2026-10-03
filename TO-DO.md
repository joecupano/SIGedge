# TO-DO

## Open

- [ ] **Rebuild `debs/direwolf_current_arm64.deb` on an arm64 host.**
  The amd64 package was rebuilt on Ubuntu 24.04 on 2026-09-30 (PR #3).
  The arm64 one is probably still linked against `libgps.so.28` and has
  no `Depends`, so on current releases it would install cleanly and then
  fail when direwolf starts. Rebuild it on an arm64 host such as a Pi:

  ```bash
  ./SIGedge package direwolf
  dpkg-deb -f debs/direwolf_current_arm64.deb Depends  # should list libgps30t64
  ldd "$(command -v direwolf)" | grep 'not found'      # should print nothing
  ```

  Then commit the new `debs/direwolf_current_arm64.deb`.

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
