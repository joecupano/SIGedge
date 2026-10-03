# Tests

**sdr-assign-test.sh** -- regression test for per-device assignment:
`scripts/sdr-assign`, the service adapters in `scripts/adapters/`, the RX-888
handoff (`scripts/handoff/rx888`), the `scripts/service_toggle` wrapper and
`scripts/device-inventory.sh`.

```bash
tests/sdr-assign-test.sh      # exit 0 = all checks passed
```

It runs in a temporary sandbox, with no root, hardware or real services
needed:

- fake sysfs entries for an RTL-SDR, a HackRF and an RX-888;
- fake `sudo`, `systemctl`, `fuser` and `fx3_cmd` on `PATH`;
- the scripts' config paths redirected into the sandbox (`SDR_SYSFS_USB`,
  `SDR_ASSIGNMENTS`, `KA9Q_CONFIG_DIR`, `RTLTCP_ENV`, `OWRX_SETTINGS`).

It covers adopting existing claims, moving each device between `radiod`,
OpenWebRX+ and `rtl_tcp`, the RX-888 firmware handoff and `rx888_boot`
masking, the whole-host guard for SDRangel server, invalid requests, all
three `service_toggle` modes, and the inventory's JSON and warnings.
