# Kismet completion checklist

Working checklist for what's left on `packages/pkg_kismet` after the
initial rewrite (`ac473e9`) and the hardware-validation bugfix pass
(`cdfa58d`). Core capture is done and proven on real hardware (see
`packages/pkg_kismet`'s own comments for the detail); everything below is
either genuinely untested or a deliberate deferral that hasn't been
revisited. Walk through each with a decision: **test it**, **defer
explicitly** (with a reason, so it doesn't get rediscovered as a mystery
later), or **drop it** from scope.

For each item: `- [ ]` unchecked = open, check it off once a decision is
made and acted on. Add the decision inline when resolved.

## Not tested

- [x] **`./SIGedge remove kismet` / `purge kismet`** — tested on real
  hardware. `remove` behaved correctly as-is: stopped/disabled the
  service, uninstalled the dpkg-tracked binary, left the site conf and
  systemd unit alone (as designed), and correctly preserved
  `/usr/local/etc/kismet.conf` etc. **Bug found and fixed**: `purge`'s
  `apt-get purge -y kismet` turned out to be a no-op in practice, because
  after `remove`, dpkg had zero record of the package at all (not even
  the normal "removed, config files remain" state) -- traced to Kismet's
  own Makefile skipping re-writes of config files that already exist
  (from an earlier raw `build`), which means checkinstall's file-tracking
  never saw them written and the `.deb` never claimed ownership. Fixed:
  `purge` now explicitly removes `/usr/local/etc/kismet*.conf` (9 shipped
  config templates) itself rather than relying on `apt-get purge` for
  them. Verified: those 9 files are gone after the fix, while `~/.kismet/`
  (real per-user web UI credentials, device-tracker DB, capture state)
  is confirmed completely untouched. One real security note surfaced
  during this: `~/.kismet/kismet_httpd.conf` holds the web UI
  username/password in plaintext -- worth remembering if that file is
  ever shared/pasted anywhere. The `kismet` system group is intentionally
  never removed by `remove`/`purge`, matching `pkg_ka9q-radio`'s same
  choice not to tear down its `radio` system user.
- [x] **checkinstall replaced entirely with real `debian/` packaging** —
  not originally its own checklist item; surfaced *while* testing item 1
  above. Purging and reinstalling from the saved `.deb` revealed it was
  fundamentally broken: it never contained `kismet.conf` at all (Kismet's
  Makefile skips rewriting config that already exists, and checkinstall's
  file-tracking only ever saw a `/usr/local` that already had leftover
  state from an earlier raw `build` — so it never observed those files
  being written, and never claimed ownership of them). Installing that
  `.deb` on a genuinely clean host would crash-loop
  (`Error reading config file '/usr/local/etc/kismet.conf': No such file
  or directory`), confirmed live. Chasing that surfaced four total
  checkinstall failure modes from a clean state (version-string
  auto-detect ignoring `--pkgversion`, a `--requires` alternation syntax
  that broke checkinstall's own argument parsing, an unhandled `cp -r`
  collision, a `mkdir -p` that failed originating a new directory tree) —
  each fixed only to reveal the next, which is what triggered replacing
  the mechanism rather than continuing to patch it. New design: real
  `debian/control` + `debian/rules` + `debian/kismet.postinst`, authored
  in `config/kismet-debian/` (Kismet ships none upstream), driving
  `dpkg-buildpackage` with `DESTDIR`-staged installs instead of tracing
  writes into the live `/usr/local` -- the fresh, empty staging tree on
  every build is what actually eliminates the whole class of bug, not
  just the four instances found. Setuid + `kismet`-group ownership on the
  capture helpers is granted by `debian/kismet.postinst` at install time
  (resolved fresh on the real target host) rather than baked into the
  package payload at build time, fixing a real GID-portability problem
  checkinstall's approach had too (`kismet` is a dynamically-created
  group with no fixed GID). Fully re-validated end to end on real
  hardware: `package` produces a complete `.deb` with every config file
  present and a real version string (`2020-12-R1-2286-ge24ee9be2-1`, not
  checkinstall's inexplicable `2004.03`); `install` on a genuinely clean
  host runs the postinst correctly (`kismet_cap_*` binaries land
  `root:kismet` mode `4550`); and the resulting Kismet actually captures
  live 802.11 traffic using those permissions, not just installs cleanly.
- [x] **The interactive checklist path** — validated the orchestration
  logic in isolation rather than a full `./SIGedge setup` run, deliberately:
  that command also runs `apt-get update && upgrade` on the whole OS and
  ends with `sudo reboot`, affecting everything else running on rubberduck
  (SIGliere, any live ka9q-radio/OpenWebRX+ state), not just Kismet --
  too large a blast radius to justify for this one check. Instead, ran
  `scripts/setup_services`'s exact real kismet conditional (copied
  verbatim) against three scenarios with the actual `pkg_kismet`
  install/build calls stood in for by echo, no sudo, no side effects:
  kismet selected + a saved `.deb` present → correctly chose `install`;
  kismet selected + none present → correctly fell back to `build`;
  kismet not selected → block correctly skipped entirely. The install/
  build actions themselves are already separately validated many times
  over; this closes the one previously-untested piece, the branching
  logic itself. The whiptail checklist entry in `scripts/setup_start` is
  boilerplate-identical to the already-working `ka9q-radio`/`openwebrx`
  entries in the same array -- not independently live-testable without an
  interactive TUI session, but not a distinct risk either given the exact
  pattern match.
- [ ] **arm64 / Raspberry Pi 5** — only validated on rubberduck's amd64.
  `pkg_kismet`'s `package` action has an explicit x86_64→amd64,
  aarch64→arm64 branch, but the build itself (dependency availability,
  compile time, capture helper behavior) has never run on arm64 at all.
- [x] **Ubertooth as a live Kismet source** — validated on real hardware
  (physical Ubertooth One attached to rubberduck). Real, non-obvious
  finding along the way: the device's factory firmware (2017-03-R2, API
  1.02) was too old for this build's `libubertooth` (1.1, needs API
  >= 1.06) -- Kismet's own capture helper refused the source with a clear
  "API mismatch" error. Fixed with a real firmware upgrade
  (`ubertooth-util -f` then `ubertooth-dfu -d
  /usr/share/ubertooth/firmware/bluetooth_rxtx.dfu -r`, the CLI's own
  advertised update procedure) -- confirmed via GreatScottGadgets' own
  docs before touching real device firmware. Hit one more real gotcha
  mid-flash: `ubertooth-dfu` run as the plain user failed with a
  misleading "<file>: Permission denied" (the file itself was genuinely
  world-readable; the real failure was a libusb device-open error,
  misattributed in the tool's own error string) -- retrying the identical
  command with `sudo` succeeded immediately. After the flash, Kismet's
  own retry loop picked the device back up automatically and the source
  opened cleanly, stable for the full observation window with zero
  errors. No Bluetooth device detections logged in that window -- not a
  capability gap, just no active BT/BLE traffic nearby at the time
  (Classic Bluetooth sniffing via Ubertooth in particular requires
  locking onto a frequency-hopping piconet, inherently harder than BLE
  advertisement capture).

  Also modernized `devices/pkg_ubertooth` while here: it previously built
  its own `libbtbb` from source into `/usr/local`, alongside the
  apt-installed `libbtbb1`/`libubertooth1` that `packages/pkg_kismet`'s
  own build dependencies already pull in -- the same libbtbb-triplication
  risk flagged elsewhere on this checklist, just discovered concretely
  this time. Confirmed Ubuntu's own `ubertooth` apt package
  (2018.12.R1-5.1) is the exact same release as those already-installed
  headers/runtime libs, so `devices/pkg_ubertooth` now just does
  `apt-get install ubertooth` -- no competing copies, and it actually
  provides the CLI tools (`ubertooth-util`, `ubertooth-dfu`, etc.) this
  device needs standalone. `build`/`package` actions now say "not
  available, use install" rather than building from source with no
  forcing reason to.
- [ ] **RTL-433 as a live Kismet source** — same gap as Ubertooth:
  `kismet_cap_sdr_rtl433` is present but never added as a source and
  exercised with a real RTL-SDR.

## Deferred (deliberate, not bugs — but worth a fresh look)

- [ ] **Kismet→AI bridge** (kismetdb → an LLM-queryable tool, the
  sovereign-sigint pattern) — scoped out of SIGedge entirely and into
  SIGliere per the tiered architecture (SIGedge = capture/aggregation,
  SIGliere = AI/cognition). Nothing built yet on either side.
- [x] **`KISMET_REF`** — pinned to `e24ee9be2b56db21c16cffe72d4334bd7232dabe`,
  the exact commit every real-hardware validation this session ran
  against (build, package, install, postinst, live capture). Matches
  `pkg_ka9q-radio`'s `KA9Q_RADIO_REF` precedent. Still override-able
  (`KISMET_REF=master` or another ref) for anyone who wants to track tip
  -- just re-validate before trusting it the way this commit has been.
- [ ] **`libbtbb` triplication** — `packages/pkg_libbtbb`,
  `devices/pkg_ubertooth` (builds its own `libbtbb` inline, ignoring the
  former), and now Kismet's own `libbtbb-dev` apt dependency are three
  independent, uncoordinated paths to the same library. Called out in the
  original review, untouched since.
- [ ] **No ufw automation** — matches this repo's existing convention
  (confirmed: no package script anywhere manages ufw), so an install-time
  reminder was added instead of an automatic `ufw allow`. Worth
  reconsidering only if that convention itself changes project-wide.
- [x] **Post-install messaging is imprecise on reinstall** — fixed. The
  "WiFi source is NOT yet configured" message now only prints when
  `kismet_site.conf` genuinely has no active `source=` line; otherwise it
  prints the real configured source instead. Verified both branches on
  real hardware (a fresh site conf correctly showed "NOT yet configured";
  a reinstall over an already-configured site conf correctly showed the
  real source line instead of the stale warning).

## Out of scope, not on this list

Evil Crow RF v2 and any other non-Kismet protocol-security device —
never a Kismet capture source to begin with, tracked separately if at
all.
