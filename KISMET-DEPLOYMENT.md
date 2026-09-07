# Kismet deployment on SIGedge

This document describes the Kismet integration that exists in the current SIGedge repository. It is an operator-facing companion to the project overview in [README.md](README.md), the same relationship [KA9Q-DEPLOYMENT.md](KA9Q-DEPLOYMENT.md) has to ka9q-radio. Validation status and open items live separately in [KISMET-CHECKLIST.md](KISMET-CHECKLIST.md).

## Service model

Kismet is a protocol-layer monitor (WiFi, Bluetooth, RF), not an alternative to `radiod`:

```text
WiFi adapter (monitor mode) --+
RTL-SDR (rtl433) -------------+---> Kismet ---> web UI (:2501) / kismetdb log
Ubertooth One -----------------+
```

It runs alongside ka9q-radio and OpenWebRX+ rather than switching with them the way those two switch with each other (see [KA9Q-DEPLOYMENT.md](KA9Q-DEPLOYMENT.md#switching-to-or-from-openwebrx) and `scripts/service_toggle`) -- there is no equivalent toggle for Kismet because it doesn't compete with `radiod` for the *same role*, only, sometimes, for the same physical device.

**An SDR must still have exactly one active owner.** Whichever devices Kismet opens directly -- RTL-SDR via `kismet_cap_sdr_rtl433`, Ubertooth via `kismet_cap_ubertooth_one` -- need exactly one owner, same as any other direct-access consumer (see [README.md](README.md)'s device-ownership section). If `radiod` already owns a device (e.g. `radiod@rtlsdr-simplex`), do not also point Kismet's `source=` at that same physical unit. When two always-on services genuinely need the same device *type* at once, pin one physical unit per consumer by USB serial rather than relying on auto-detect -- see "Configure capture sources" below and `scripts/device-inventory.sh`, which lists attached devices side by side with whatever already claims them.

## Current implementation

| Component | Repository path | Current behavior |
|---|---|---|
| Kismet package lifecycle | `packages/pkg_kismet` | Installs build dependencies; builds, packages, installs, removes, or purges Kismet; sets up the `kismet` group, site config, and systemd unit |
| Debian packaging | `config/kismet-debian/` | Real `debian/control` + `debian/rules` + `debian/kismet.postinst`, authored by SIGedge (Kismet ships none upstream) |
| Site configuration template | `config/kismet_site.conf.example` | Installed once to `/usr/local/etc/kismet_site.conf` (left alone on rebuild/reinstall so local edits survive) |
| systemd unit template | `config/kismet.service` | `@kismet_user@`/`@kismet_home@` placeholders filled in per host at install time |
| Device inventory helper | `scripts/device-inventory.sh` | Read-only: lists attached SDR/RF USB devices next to whatever `radiod`/Kismet configs already claim them |

Kismet's own selection in `./SIGedge setup` (`scripts/setup_start`, `scripts/setup_services`) follows the same packaged-path-first pattern as ka9q-radio: if `debs/kismet/*.deb` already exists, `setup_services` installs from it; otherwise it builds from source.

## Current limitations

- **Built from source, deliberately -- not from Kismet's own APT repo.** Kismet's prebuilt 2025+ packages depend on `libwebsockets17`, which is not installable on Ubuntu 24.04 (Noble carries a different `libwebsockets` version) -- a confirmed, still-open upstream issue ([kismetwireless/kismet#574](https://github.com/kismetwireless/kismet/issues/574)). Building from source links against Noble's own `libwebsockets-dev` (4.3.x) instead, sidestepping the pin. Same source-build approach this repo already uses for ka9q-radio and Ubertooth/libbtbb.
- **`packages/pkg_kismet` pins Kismet to a fixed commit** via `KISMET_REF` (currently `e24ee9be2b56db21c16cffe72d4334bd7232dabe`) rather than tracking upstream `master`, matching `pkg_ka9q-radio`'s `KA9Q_RADIO_REF` precedent -- `master` is active development and can be temporarily broken. Override with `KISMET_REF=master` or another ref if you need something newer; re-validate before trusting it the way this commit has been (see [KISMET-CHECKLIST.md](KISMET-CHECKLIST.md)).
- **arm64 / Raspberry Pi 5 is untested.** `pkg_kismet`'s `package` action has an explicit x86_64->amd64, aarch64->arm64 branch, but the build itself has only run on amd64 so far.
- **`libbtbb` triplication.** `packages/pkg_libbtbb`, `devices/pkg_ubertooth`, and Kismet's own `libbtbb-dev` apt dependency are three independent, uncoordinated paths to the same library. Called out in [KISMET-CHECKLIST.md](KISMET-CHECKLIST.md), untouched so far.
- **No ufw automation**, matching this repo's project-wide convention -- no package script here manages `ufw`. `pkg_kismet install` prints a reminder instead of an automatic `ufw allow` when it detects an active default-deny firewall with port 2501 not allowed.

## Prerequisites

The current target is Ubuntu Server 24.04 LTS on amd64/x86_64 (arm64/aarch64 untested, see above). The host needs:

- `sudo` privileges
- working package and source-network access
- a WiFi adapter that supports monitor mode for 802.11 capture (see "Configure capture sources" below) -- everything else (RTL-SDR, Ubertooth) is optional
- an open TCP port for the web UI (`2501` by default)

The package script installs its own build and runtime dependencies -- the full list from Kismet's own Linux install docs, plus the capture-source dev libraries (`libubertooth-dev`, `libbtbb-dev`, `librtlsdr-dev`) so the Ubertooth, Bluetooth, and RTL capture helpers are compiled in from the start. Kismet selects which capture helpers to build at `./configure` time based on which `-dev` libraries are present, so adding that hardware later is "enable the source in `kismet_site.conf`", not "rebuild Kismet" -- none of it needs to be attached for the build itself.

## 1. Build or install Kismet

### Packaged path (recommended -- `remove`/`purge` work cleanly against it afterward)

Real, dpkg-tracked `.deb` built via `dpkg-buildpackage` against SIGedge's own `config/kismet-debian/` (Kismet ships no `debian/` upstream):

```bash
./SIGedge package kismet   # builds .deb into debs/kismet/
./SIGedge install kismet   # installs it via apt-get
```

This replaced an earlier `checkinstall`-based approach that traced `make suidinstall` writing directly into a live `/usr/local` -- confirmed broken in four distinct ways on real hardware (see `config/kismet-debian/rules` and [KISMET-CHECKLIST.md](KISMET-CHECKLIST.md) for the full history). `dpkg-buildpackage`'s fresh, empty `debian/kismet/` staging tree on every build eliminates that whole class of bug rather than patching around it.

### Manual test-build path

Raw `make suidinstall` to `/usr/local`, not tracked by dpkg (`remove`/`purge` are no-ops against it -- only the small capture helper binaries are installed setuid-root; the Kismet server itself runs as a normal user):

```bash
./SIGedge build kismet
```

`./SIGedge setup` and `scripts/setup_services` use the packaged path automatically once `debs/kismet/` has been populated by `./SIGedge package kismet`; otherwise they fall back to the build path on a clean checkout -- same convention as ka9q-radio.

### Verify the install

```bash
command -v kismet
kismet --version
```

`packages/pkg_kismet` also reports which capture helpers actually got built (`kismet_cap_linux_wifi`, `kismet_cap_linux_bluetooth`, `kismet_cap_ubertooth_one`, `kismet_cap_sdr_rtl433`) -- which ones are present depends on which `-dev` libraries `./configure` found, not on attached hardware at build time.

## 2. Post-install state

Both the `build` and `install` paths leave the same working state behind:

- **`kismet` group.** The operator invoking `sudo` (or the current user, for a non-sudo build/package invocation) is added to the `kismet` group. **This only takes effect on a new login/session** -- log out and back in, or run `newgrp kismet`, before running `kismet` interactively. The systemd unit runs under a fresh session, so it already has it.
- **Site config**, installed once to `/usr/local/etc/kismet_site.conf` -- not overwritten on a rebuild/reinstall, so local edits survive. **Path detail that matters:** Kismet's `--sysconfdir` for a from-source install is the flat `/usr/local/etc/`, *not* `/usr/local/etc/kismet/`. A `kismet_site.conf` placed in a subdirectory is silently ignored ("Optional sub-config file not present" in the startup log) and no source loads -- confirmed real debugging time cost in an earlier project this evolved from.
- **systemd unit**, templated from `config/kismet.service` (`@kismet_user@`/`@kismet_home@` filled in), installed as a *system* unit (not `--user`) -- `make suidinstall`'s setuid-root capture helpers were confirmed flaky under `--user` session isolation. Enabled, and started only if not already running (so a rebuild/reinstall never restarts an operator's already-running Kismet).

## 3. Configure capture sources

Kismet loads `*_site.conf` last, after every shipped config -- edit `/usr/local/etc/kismet_site.conf` directly (see its own extensive comments), never the installed `kismet*.conf` files.

### WiFi (required for 802.11 capture)

No source is pre-defined -- unlike SIGedge's SDR devices, there's no fixed reference WiFi adapter; the interface name is host- and chipset-specific, and not every adapter supports monitor mode without an out-of-tree driver.

```bash
iw dev                                            # interface name
iw list | grep -A12 "Supported interface modes"   # look for "* monitor"
```

An MT7612U (mainline `mt76x2u`) works out of the box; an RTL8812AU needs a DKMS driver (e.g. `morrownr/8812au`) installed first. Then uncomment and edit in `kismet_site.conf`:

```
source=wlxXXXXXXXXXXXX:name=wifi
```

### RTL-SDR (ISM-band/rtl433, optional)

RTL-SDR is also a `radiod` device elsewhere in SIGedge -- a device can only have one owner (see "Service model" above). If this host's RTL-SDR is already a `radiod` mission (e.g. `radiod@rtlsdr-simplex`), do not also point Kismet at that same physical dongle. If you want both running at once, use a separate RTL-SDR unit per consumer (they're cheap enough that this is the practical default) and pin each one explicitly by USB serial:

```bash
rtl_eeprom -d 0        # read serial for dongle at index 0
rtl_eeprom -d 1        # read serial for dongle at index 1
```

`radiod`'s own pinning is `RTLSDR_SERIAL=<serial>` passed to `scripts/cfg_ka9q-radio`; Kismet's equivalent is a `rtl433-sn-<serial>` source string:

```
source=rtl433-sn-XXXXXXXX:name=ism-rtlsdr
```

`scripts/device-inventory.sh` surfaces both sides of this at once -- what's physically attached, and which config (radiod's or Kismet's) already claims each serial -- so a collision is visible before either service is enabled, not discovered at runtime.

### Ubertooth (Bluetooth/BLE, optional)

Unlike RTL-SDR, Kismet's Ubertooth source selects by numeric device index only (`ubertooth0`, `ubertooth1`, ...), not by serial -- less stable across replugging if more than one is ever attached, but Ubertooth is priced like HackRF/RX-888 (one unit per host, not a cheap multi-unit device), so this is a non-issue in the common case.

**Firmware gotcha, confirmed on real hardware:** a real Ubertooth One can arrive running firmware too old for this build's `libubertooth`, and the source fails with `API mismatch... make sure your libubertooth, libbtbb, and ubertooth firmware are all up to date`. Check first:

```bash
ubertooth-util -v
```

If the reported API version is older than what your `libubertooth` needs, upgrade firmware (`sudo` is required -- a plain-user `ubertooth-dfu` invocation fails with a misleading "Permission denied" that's actually a libusb device-open error, not a file-read error):

```bash
sudo ubertooth-util -f
sudo ubertooth-dfu -d /usr/share/ubertooth/firmware/bluetooth_rxtx.dfu -r
```

Then uncomment and edit in `kismet_site.conf`:

```
source=ubertooth0:name=bt-ubertooth
```

After editing any source, apply it:

```bash
sudo systemctl restart kismet
```

## 4. Verify it's running

```bash
systemctl --no-pager --full status kismet.service
journalctl --no-pager -u kismet.service -n 100
```

Web UI: `http://<host>:2501/` -- set an administrator username/password on first browse (stored per-user in `~/.kismet/kismet_httpd.conf`, plaintext, not site-wide -- worth remembering before sharing or pasting that file anywhere).

**A known culprit for "browser connection timed out" that looks like a service failure but isn't:** SIGedge does not manage `ufw` for any service. If this host has `ufw`'s default-deny incoming policy active (`sudo ufw status`), the web UI listens locally and silently times out from the network until you run:

```bash
sudo ufw allow 2501/tcp comment "Kismet (SIGedge)"
```

`pkg_kismet install` detects this condition and prints the same reminder.

## 5. Remove or purge

```bash
./SIGedge remove kismet   # stops+disables the service, uninstalls the dpkg package; site conf and systemd unit are left alone
./SIGedge purge kismet    # also removes /usr/local/etc/kismet*.conf and the systemd unit
```

`~/.kismet/` (real per-user web UI credentials, device-tracker database, capture state) is never touched by either action -- same reasoning `pkg_ka9q-radio` applies to RX-888 firmware ownership. The `kismet` system group is likewise never removed, matching `pkg_ka9q-radio`'s choice not to tear down its `radio` system user.

## Troubleshooting

### Kismet source won't open a device

Check for another process that already owns it (`radiod`, a direct-access app), then inspect USB enumeration:

```bash
sudo systemctl status kismet.service
journalctl --no-pager -u kismet.service -n 100
scripts/device-inventory.sh
lsusb
```

### Web UI unreachable from the network but the service is running

See "Verify it's running" above -- check `ufw` before suspecting the daemon itself; this exact symptom cost real debugging time on rubberduck once already.

### Ubertooth source fails with "API mismatch"

See "Configure capture sources" -- Ubertooth above. Upgrade firmware with `ubertooth-util -f` / `ubertooth-dfu`, both under `sudo`.

### `kismet_site.conf` edits seem to have no effect

Confirm the file is at the flat `/usr/local/etc/kismet_site.conf`, not a `kismet/` subdirectory under it -- Kismet silently ignores a misplaced site config rather than erroring. Then restart: `sudo systemctl restart kismet`.

### Group membership doesn't seem to apply

`usermod -aG kismet` only takes effect on a new login/session. Log out and back in, or run `newgrp kismet`, before running `kismet` interactively -- the systemd unit is unaffected since it always starts a fresh session.

### `./SIGedge purge kismet` doesn't seem to remove config files

If Kismet was ever raw-`build`-installed before a `.deb` existed for it, dpkg may have no record of the package at all after a plain `remove` (Kismet's own Makefile skips rewriting config that already exists, so an earlier build-then-package sequence can leave dpkg never having claimed those files). `pkg_kismet purge` handles this by removing `/usr/local/etc/kismet*.conf` directly rather than relying solely on `apt-get purge` -- if you still see stale files after `purge`, check `dpkg -s kismet` to confirm the package is genuinely gone.
