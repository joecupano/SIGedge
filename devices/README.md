# Devices

These scripts are called during SIGedge installation as well as directly via
**SIGedge device (install|remove|purge|build|package) <DEVICE>** for managing
individual devices.

SIGedge project does its utmost to ensure the most recent stable releases for devices are available for installation and maintained in the **debs** directory.

When running **SIGedge device package <DEVICE>** the resulting debian packages are stored in the **debs** directory.

## Device kinds, drivers and handoff

The device kinds SIGedge can assign to services (`SIGedge assign`, see
[scripts/README.md](../scripts/README.md#device-ownership)) are `rx888`,
`hackrf` and `rtlsdr`. Two rules for the scripts in this directory:

- **One driver per device.** Where a script builds a SoapySDR module itself
  (`pkg_hackrf` SoapyHackRF, `pkg_rtlsdr` SoapyRTLSDR, `pkg_rx888mk2-soapy`
  SDDC), it removes the distro's package for the same driver, and
  `setup_devices` installs SoapySDR without recommends so
  `soapysdr0.8-module-all` doesn't bring the distro copies back. Two modules
  registering one driver name means load order decides which runs;
  `scripts/driver-check` reports it.
- **Handoff needs.** A device whose state survives a change of owner gets a
  hook in `scripts/handoff/<kind>`. The RX-888 is the one today: its FX3 keeps
  the last owner's firmware, so `pkg_rx888` installs `fx3_cmd`
  (`/usr/local/bin`), which `scripts/handoff/rx888` uses to reset it to the
  bootloader.

## DEVICES file format

Same shape as `packages/PACKAGES` -- see that file's README for the
rationale on separate arch columns:

```
name,version_amd64,version_arm64,description,date
```
