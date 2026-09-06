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
- [ ] **The interactive checklist path** (`./SIGedge setup` → whiptail →
  `scripts/setup_services`'s `grep -qx 'kismet' "$SIGEDGE_INSTALLED_SERVICES"`
  branch) — only direct `./SIGedge build/package/install kismet` calls
  were exercised. The orchestration logic (prefer a saved `.deb`, else
  build) was reviewed but never actually run end-to-end through the real
  setup flow.
- [ ] **arm64 / Raspberry Pi 5** — only validated on rubberduck's amd64.
  `pkg_kismet`'s `package` action has an explicit x86_64→amd64,
  aarch64→arm64 branch, but the build itself (dependency availability,
  compile time, capture helper behavior) has never run on arm64 at all.
- [ ] **Ubertooth as a live Kismet source** — `kismet_cap_ubertooth_one` is
  compiled in and confirmed present, but never added as an actual data
  source with a physical Ubertooth One attached and exercised, unlike
  WiFi.
- [ ] **RTL-433 as a live Kismet source** — same gap as Ubertooth:
  `kismet_cap_sdr_rtl433` is present but never added as a source and
  exercised with a real RTL-SDR.

## Deferred (deliberate, not bugs — but worth a fresh look)

- [ ] **Kismet→AI bridge** (kismetdb → an LLM-queryable tool, the
  sovereign-sigint pattern) — scoped out of SIGedge entirely and into
  SIGliere per the tiered architecture (SIGedge = capture/aggregation,
  SIGliere = AI/cognition). Nothing built yet on either side.
- [ ] **`KISMET_REF=master`** — still an unpinned moving target. The
  script's own comment flags this and suggests pinning a validated
  commit once one exists, matching `pkg_ka9q-radio`'s `KA9Q_RADIO_REF`
  precedent. The commit validated this session (`e24ee9be`) is a
  candidate.
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
