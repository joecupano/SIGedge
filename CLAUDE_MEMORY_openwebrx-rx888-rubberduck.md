# Claude memory export: openwebrx-rx888-rubberduck

Verbatim copy of the Claude Code session memory file of the same name
(`~/.claude/projects/-home-baldrick-SIGedge/memory/openwebrx-rx888-rubberduck.md`
on rubberduck), kept in sync on request so it isn't only local to one
machine's agent memory. See [PROJECT_STATE.md](PROJECT_STATE.md) and
[KA9Q-DEPLOYMENT.md](KA9Q-DEPLOYMENT.md)'s "RX-888 in OpenWebRX+" section
for the same material written up as permanent repo docs.

---

OpenWebRX+ set up on host **rubberduck** (this machine is rubberduck itself — no SSH needed, work locally) with the RX-888 usable in it for a session, while leaving HackRF/RTL-SDR on ka9q-radio.

**Resolved, confirmed working (2026-09-05):**
- `radiod@rx888-wwv.service` stopped+disabled (only that mission — `radiod@hackrf-aprs` and `radiod@rtlsdr-simplex` untouched, as intended).
- OpenWebRX+ installed via the **luarvique PPA** (`https://luarvique.github.io/ppa/noble`), package `openwebrx` 1.2.123 — NOT built from source (`./SIGedge install openwebrx` / `packages/pkg_openwebrx` is broken for RX-888: builds plain `jketterl/openwebrx`, never builds `sddc_connector`).
- RX-888 device in the web UI: `BBRF103 / RX666 / RX888 / RX888 mkII (SDDC) device (via SoapySDR)`, 32 MS/s, center 15 MHz, RF/IF gain 20/20. Backed by a SoapySDR module built from **`ON5HB/RX888MK2-Soapy`** (CPU-only, no CUDA) — not SIGedge's own `SDDC_Driver` module, which is a different build for a different direct-access purpose.
- `openwebrx` system user needed adding to the **`radio`** group — the RX-888 in DFU mode (`04b4:00f3`) is `root:radio` 0660 plus a `uaccess` ACL that doesn't cover a service account; without `radio` group membership, `soapy_connector` gets `LIBUSB_ERROR_ACCESS` and segfaults.
- **The real blocker, now understood**: the RX-888's FX3 chip holds only one driver stack's firmware at a time, loaded fresh on every power cycle — **and a plain OS reboot does not count** (it resets the USB link/protocol state but doesn't necessarily drop VBUS power, so the FX3 can keep running whichever firmware a previous owner, e.g. `radiod`, had loaded). Symptom was repeated `[SDDC] ERROR - usb_device: libusb Pipe error` on specific write control transfers immediately followed by a `soapy_connector` segfault in `activateStream` — while `SoapySDRUtil --probe` still succeeded (doesn't touch the same code path), which is what made this confusing. Fix: an actual physical unplug/replug (~15s) of the RX-888, confirmed via `lsusb -d 04b4:` showing genuine DFU mode (`00f3`) beforehand. After that, `soapy_connector` uploaded its firmware cleanly and streamed at ~105% CPU with zero errors — confirmed with a live waterfall/audio in the browser.
- Full writeup folded into the SIGedge repo: `PROJECT_STATE.md` and a new "RX-888 in OpenWebRX+" section in `KA9Q-DEPLOYMENT.md`. The dated followup doc (`OPENWEBRX_RX888_FOLLOWUP_2026-09-04.md`) was removed after folding, matching this repo's established pattern for that doc type.

**Key findings from this work, useful beyond just finishing the install:**
- `~/sovereign-sigint` and `~/SIGliere` are sibling projects on this same host worth checking before solving an already-solved problem: `sovereign-sigint/docs/openwebrx-sdr-quickstart.md` and `scripts/phase6-openwebrx-rx888.sh` documented this exact RX-888/OpenWebRX+ setup (the `ON5HB/RX888MK2-Soapy` build) in detail before this session reproduced it. `SIGliere` is the AI tier (Ollama/Open WebUI) on this box and has no SDR/OpenWebRX+ involvement — its CUDA driver is for Ollama, unrelated to the RX-888.
- If ever mixing a from-source build with a PPA/dpkg package for the same app: check for `/usr/local/bin` and `/usr/local/lib/python3.*/dist-packages` shadowing the package's `/usr/bin` and `/usr/lib/python3/dist-packages` files — this caused a real crash-loop and a stale-file-ownership auth failure earlier in this same work (see git history of the folded docs for full detail if needed).
- `sudo` needs a real TTY in this environment — an agent session has no cached credential and no NOPASSWD rule, so privileged commands must be handed to the user to run in their own terminal.
- rubberduck's own LAN IP is `192.168.173.65/24` (`eno1`); a laptop reaching it over SSH showed source IP `192.168.73.65` — a different /24 (`192.168.73.0/24`, not `.173.`). Easy to transpose.
- ufw is active by default (default-deny incoming) from earlier SIGliere/sovereign-sigint hardening work — a service needs an explicit `ufw allow` or it silently times out rather than refusing.
- `~/SIGliere` (capital L, capital in the middle — not `~/SIGLiere`) is the correct path/casing.
- Another Claude Code session independently worked on this same problem overnight (2026-09-04 evening) in its own scratchpad and left the `ON5HB/RX888MK2-Soapy` module installed plus the `radio` group fix — worth remembering that concurrent/background sessions on the same host can and did make real progress between turns of this one.
