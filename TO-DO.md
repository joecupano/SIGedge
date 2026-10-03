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

- [ ] **Validate per-device assignment on real hardware (sigedge-mac).**
  `scripts/sdr-assign` and its adapters pass `tests/sdr-assign-test.sh`
  (fake services and devices), but haven't driven real services yet. On
  this host:

  ```bash
  scripts/sdr-access install                # sdr group + udev rule; log out and back in after
  sudo systemctl restart openwebrx          # picks up the new group
  sudo SIGedge inventory                    # both radios, live holders
  SIGedge assign adopt                      # record OpenWebRX+'s current devices
  SIGedge assign hackrf none                # HackRF disabled in OpenWebRX+
  SIGedge assign hackrf openwebrx           # and back
  ```

  Check OpenWebRX+'s device list after each step, and that its
  `settings.json` is still owned by `openwebrx`.

- [ ] **Confirm `RESETFX3` works under both RX-888 firmwares.** The handoff
  (`scripts/handoff/rx888`) resets the FX3 with `fx3_cmd reset`, falling back
  to `fx3_cmd usbreset`. rx888-firmware documents both for its own
  SDDC_FX3 image, but neither has been run here, and nobody has checked the
  firmware ka9q-radio's `rx888_boot` loads or the one RX888MK2-Soapy
  uploads. Needs a host with
  ka9q-radio installed: assign the RX-888 to `radiod`, then to `openwebrx`,
  and check it re-enumerates as `04b4:00f3` without being unplugged.

- [ ] **Clear this host's driver-check problem.** `scripts/driver-check`
  reports SoapyHackRF installed twice: SIGedge's build in `/usr/local` and
  the distro's `soapysdr0.8-module-hackrf`, which currently wins. Remove the
  distro copy (`sudo apt-get remove soapysdr0.8-module-hackrf`), as
  `devices/pkg_hackrf` now does on install.

- [ ] **Run shellcheck over the new scripts** (`scripts/sdr-assign`,
  `sdr-access`, `driver-check`, `service_toggle`, `handoff/rx888`,
  `lib/sdr_common.sh`, `adapters/*`). It isn't installed on sigedge-mac, so
  they've only had `bash -n` and the regression test.
