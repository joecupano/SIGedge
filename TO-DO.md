# TO-DO

## Open

- [ ] **Confirm `RESETFX3` works under ka9q-radio's RX-888 firmware.** The
  handoff (`scripts/handoff/rx888`) resets the FX3 with `fx3_cmd reset`.
  Confirmed with RX888MK2-Soapy's firmware (see Done). Still unchecked: the
  firmware ka9q-radio's `rx888_boot` loads. Needs ka9q-radio installed: assign
  the RX-888 to `radiod`, then to `openwebrx`, and check it comes back as
  `04b4:00f3` without being unplugged.

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

- [x] **`RESETFX3` under RX888MK2-Soapy's firmware, 2026-10-02.** On
  sigedge-mac, `SIGedge assign rx888 none` reset the RX-888 to its
  bootloader. That run also exposed three bugs, all fixed: the bootloader
  enumerates at USB 2, so the device moved from port `4-4` to `3-4` and the
  handoff falsely reported failure (the RX-888 id is now the socket's USB 2
  path); the failed handoff left a stale assignment; and that stale record
  made OpenWebRX+ get a second RX-888 entry (only one RX-888 assignment is
  now honoured). Re-run after the fix (`41e576e`): `assign rx888 none` reset
  the RX-888 to its bootloader with no fallback and no error, `assign rx888
  openwebrx` reused the original entry (gain kept), the id stayed `port:3-4`
  across both buses, and OpenWebRX+ reloaded its firmware and streamed.
