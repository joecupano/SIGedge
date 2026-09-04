# Work needed on SIGliere following SIGedge's static-multicast fix

Host: rubberduck. Written 2026-09-04 from a SIGedge-side session that implemented
`NETWORKING.md`'s static-multicast-address scheme (the fix SIGliere's own
`PROJECT_STATE.md` flagged as outstanding — "Known gap carried forward:
`radiod`'s multicast addresses are allocated dynamically per restart..."). That
gap is now closed on the SIGedge side and verified live on rubberduck. Import
this into a session scoped to SIGliere changes — everything below is
SIGliere/`gateway`-side, not SIGedge host config.

## What changed on the SIGedge side

All three reference `radiod` instances (`rx888-wwv`, `hackrf-aprs`,
`rtlsdr-simplex`) now use fixed, checked-in multicast addresses instead of
ka9q-radio's per-name hash. Verified live on rubberduck at the kernel socket
level (`ss -uan`), IGMP membership, and actual decoded traffic — not just
config content:

| Instance | node concept | Status address | Data address |
|---|---|---|---|
| `radiod@rx888-wwv` | `sigedge-hf` | `239.192.1.10` | `239.192.64.10` |
| `radiod@hackrf-aprs` | (unmapped — see open item below) | `239.192.1.20` | `239.192.64.20` |
| `radiod@rtlsdr-simplex` | (unmapped — see open item below) | `239.192.1.30` | `239.192.64.30` |

Full detail and the general addressing scheme (for future SIGedge platforms/
missions beyond these three) is in SIGedge's `NETWORKING.md`, "Current static
assignment" table. These addresses are now stable across `radiod` restarts —
confirmed by reading ka9q-radio's own source (the hash is a pure function of
the configured name string) and by live-testing a restart.

## 1. Update `sigedge-hf`'s stale address in `nodes.json`

`gateway/config/nodes.json` currently has:

```json
"node_id": "sigedge-hf",
"status_address": "239.113.183.73",
```

`239.113.183.73` was the dynamic hash address from the earlier validation
session (2026-09-04, documented in SIGliere's own `PROJECT_STATE.md`). Change
it to the new static address:

```json
"status_address": "239.192.1.10",
```

Restart/redeploy `sigliere-gateway` afterward — it caches `nodes.json` at
startup, so the running container won't pick up the edit otherwise (this is
exactly the caching behavior that caused the stale-echo anomaly noted in
open item #3 during the original validation session).

After restarting, re-run the same checks `PROJECT_STATE.md` already used to
confirm `sigedge-hf`: `scripts/validate-tiered.sh` and a direct query against
`/status/sigedge-hf`, expecting `"reachable": true` with the live WWV channel
and real SNR — same result as before, but now against an address that won't
go stale on the next SIGedge-side `radiod@rx888-wwv` restart.

## 2. Decide what `sigedge-vhf-uhf` should actually point at

Per `PROJECT_STATE.md`, `sigedge-vhf-uhf`'s current `status_address`
(`239.172.80.224`) is an **unverified placeholder** — no VHF/UHF `radiod`
instance was ever brought up to confirm or replace it. That's still true, but
the situation on the SIGedge side has changed: there are now *two* running,
statically-addressed VHF missions, and neither one alone matches what
`sigedge-vhf-uhf` currently claims to be:

- `radiod@hackrf-aprs` — APRS 144.390 MHz FM only, status `239.192.1.20`
- `radiod@rtlsdr-simplex` — simplex 144.650 MHz FM only, status `239.192.1.30`

`sigedge-vhf-uhf`'s declared `min_hz`/`max_hz` (30 MHz–6 GHz) and mode list
(`nfm`, `wfm`, `fm`, `am`, `usb`, `lsb`, `cw`) describe a general-coverage
receiver neither of these narrow single-channel missions actually is. Options,
in rough order of how much they change `nodes.json`'s shape:

- Leave `sigedge-vhf-uhf` as an aspirational placeholder for a real wideband
  receiver not yet built, and add `hackrf-aprs`/`rtlsdr-simplex` as two new,
  narrowly-scoped nodes instead (e.g. `sigedge-vhf-aprs` at `239.192.1.20`
  with `min_hz`/`max_hz` pinned to 144.390 MHz and `modes: ["fm"]`,
  `sigedge-vhf-simplex` at `239.192.1.30` similarly for 144.650 MHz).
- Repoint `sigedge-vhf-uhf` at whichever of the two matters more for now
  (probably `rtlsdr-simplex`, since APRS is arguably its own node concept),
  accepting that its range/mode list overstates what's actually behind it
  until a real wideband receiver exists.
- Something else — this is a SIGliere-side node-modeling decision, not
  something the SIGedge-side fix resolves by itself.

Whichever direction: the concrete static addresses to use once decided are
`239.192.1.20` (`hackrf-aprs`) and `239.192.1.30` (`rtlsdr-simplex`), both
stable across restarts the same way `sigedge-hf`'s now is.

## 3. Still unconfirmed: does `discover_channels_native` actually filter by the passed address?

Carried forward from the original validation session, still not diagnosed.
Observed there: after editing `nodes.json` to point `sigedge-hf` at a new
live address but *before* restarting the gateway, `/status/sigedge-hf` still
echoed the old cached `status_address` yet reported `"reachable": true"` with
a channel matching the address that was *actually* broadcasting — suspicious,
but at the time only one `radiod` instance existed on the LAN, so "found the
right one by address" was indistinguishable from "found the only one that
exists, regardless of address."

That ambiguity is now resolvable: rubberduck runs three simultaneous `radiod`
instances with three distinct, stable status addresses (`239.192.1.10`,
`.20`, `.30`). Point `discover_channels_native()` (or the gateway's
`/status/<node>` endpoint) at one node's declared address and confirm it
returns *that* node's channels specifically — not another instance's, and not
a merged/ambiguous result from a broader mDNS/network browse. If it can
return another node's channels regardless of the address argument, that's a
real correctness gap in `sigedge_client.py`'s node-vs-address matching, worth
its own fix.

## Reference: what's now confirmed working end-to-end (SIGedge side)

- All three `radiod` instances resolve `status`/`data` to the fixed addresses
  in the table above, confirmed via kernel socket state (`ss -uan`), IGMP
  membership, and live decoded traffic (WWV audio flowing continuously on
  `239.192.64.10`; APRS bursts on `239.192.64.20`).
- These addresses survive a `radiod` restart — tested directly on rubberduck.
- SIGedge's `scripts/cfg_ka9q-radio` now manages this automatically (config
  templates plus a synced `/etc/hosts` block); no manual re-sync step is
  needed on the SIGedge side going forward.
