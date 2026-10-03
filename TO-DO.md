# TO-DO

## Open

(nothing open)

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

- [x] **`RESETFX3` under ka9q-radio's firmware, 2026-10-03.** On
  sigedge-mac, with ka9q-radio installed: `SIGedge assign rx888
  radiod:rx888-wwv` unmasked `rx888_boot`, reset the RX-888, and
  `rx888_boot` reloaded ka9q's firmware (2.3) so fast that the handoff only
  saw the re-enumeration (the case fixed in `7b7aaa1`). radiod then streamed
  at 64.8 Msps over USB 3. `SIGedge assign rx888 openwebrx` stopped radiod,
  masked `rx888_boot`, and `RESETFX3` put the FX3 straight into its
  bootloader (`04b4:00f3`) with no USB-reset fallback. OpenWebRX+ reused its
  original RX-888 entry, loaded its own firmware over ka9q's and streamed
  WWV. The RX-888 now moves between radiod and OpenWebRX+ without being
  unplugged.

- [x] **radiod's `ttl == 0; iface ... ignored` message, 2026-10-03.** Not a
  config problem. radiod (ka9q-radio `2ecfe43`, `src/radio.c`) always
  creates two output sockets, one with TTL 1 on the configured `iface` and a
  loopback-only TTL 0 one for channels that ask for it, and creating the
  second prints this message on every start. The mission's `[global] ttl =
  1` does reach the channels (`loadpreset(&Template, Configtable, GLOBAL)`),
  and radiod advertised the WWV data stream as `TTL=1`. No template change
  needed.

- [x] **Install scripts no longer open devices in use, 2026-10-03.**
  `pkg_ka9q-radio`'s hardware report ran `hackrf_info` and `rtl_test -t`,
  opening each device; it now shows `device-inventory.sh`, which reads
  sysfs only. `pkg_rx888 install` ran `fw_test.sh`, which uploads firmware,
  on any attached RX-888; it now skips that (`RX888_VALIDATION=
  skipped-in-use`) when the RX-888 is assigned to a service or held open.
