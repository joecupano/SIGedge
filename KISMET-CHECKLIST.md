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
- [ ] **Post-install messaging is imprecise on reinstall** — the "WiFi
  source is NOT yet configured" message is static and prints
  unconditionally, even when `kismet_site.conf` already has a real
  `source=` line from a previous install (confirmed misleading during the
  `install`-from-`.deb` test). Cosmetic, but a real rough edge for an
  operator re-running the script.

## Out of scope, not on this list

Evil Crow RF v2 and any other non-Kismet protocol-security device —
never a Kismet capture source to begin with, tracked separately if at
all.
