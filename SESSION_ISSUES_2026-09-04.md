# SIGedge issues found from a SIGliere validation session

Host: rubberduck. Captured 2026-09-04 during a SIGliere-side session that was
validating live status multicast end-to-end (SIGliere PROJECT_STATE.md step
4: "Verify live status multicast, routing/interface selection, TTL, IGMP
behavior, and firewall policy"). Import this into a session scoped to
SIGedge changes — everything below is SIGedge/host-level, not SIGliere
application code.

## Fixed this session

### 1. `radiod@rx888-wwv` was never deployed
`scripts/cfg_ka9q-radio` had only ever been run for `rtlsdr`, so
`/etc/radio/radiod@rx888-wwv.conf` didn't exist and the unit was crash-looping
every 5s (`Can't load config file ... status=66/NOINPUT`). Fixed by running:

```bash
sudo ./scripts/cfg_ka9q-radio rx888
sudo systemctl restart radiod@rx888-wwv
```

It's now genuinely running against real RX-888 mk2 hardware, decoding WWV at
10.000 MHz AM with SNR in the 10-20 dB range depending on propagation.

### 2. Host firewall had no multicast/UDP exception
`SIGliere`'s `scripts/install-security-hardening.sh` sets `ufw default deny
incoming` and only opens `22/tcp` and `8443/tcp`. Nothing allowed KA9Q
status/data traffic. Fixed with:

```bash
sudo ufw allow proto udp to 239.0.0.0/8 comment 'KA9Q multicast (SIGedge)'
```

This is scoped to the full RFC 2365 administratively-scoped multicast range,
not just `NETWORKING.md`'s documented `239.192.0.0/16` static-override
sub-range — see open item #2 below for why.

Note: this rule mattered for `eno1`. ufw's default `before.rules` already
exempt `lo` unconditionally, and `radiod` logged "Multicast enabled on
loopback interface lo" — so on this host the fix may have been necessary for
correctness/future remote reachability rather than the literal blocker for
same-host delivery. Worth confirming next time by testing before vs. after
more carefully if a similar symptom recurs on another host.

## Still broken — needs attention in a SIGedge-focused session

### 1. `radiod@hackrf-aprs` and `radiod@hackrf-simplex` are crash-looping
Both currently show `activating (auto-restart)` in `systemctl status`,
restarting every ~5s with `status=66/NOINPUT`.

- **`hackrf-aprs`**: same root cause as rx888 was — never deployed via
  `cfg_ka9q-radio`. Fix: `sudo ./scripts/cfg_ka9q-radio hackrf` then
  `sudo systemctl restart radiod@hackrf-aprs`.
- **`hackrf-simplex`**: this instance name doesn't correspond to any real
  mission. The three proven reference missions are `rx888-wwv`, `hackrf-aprs`,
  and `rtlsdr-simplex` (HackRF does APRS, RTL-SDR does simplex — the name
  `hackrf-simplex` looks like it was typo'd by combining the two). No config
  will ever load for it. Fix: `sudo systemctl stop radiod@hackrf-simplex`
  and, if a persistent "don't retry" is wanted,
  `sudo systemctl disable radiod@hackrf-simplex` (it was never enabled, but
  it's still auto-restarting because it was started directly).

### 2. Multicast addresses are dynamic, and nothing pins them down
By default `cfg_ka9q-radio`'s generated configs don't set an explicit
multicast address — `radiod` uses Avahi + mDNS-hashing to allocate one at
each startup (e.g. `rx888-wwv`'s status address came up as
`239.113.183.73` this run; it will likely be a *different* address next
time `radiod@rx888-wwv` restarts). `NETWORKING.md` documents an optional
static-override scheme (`239.192.0.0/24` SIGedge platform,
`239.192.1.0/24` status/control, etc.) but none of the three reference
configs in `config/` actually use it.

This matters because SIGliere's `gateway/config/nodes.json` hard-codes a
`status_address` per node (used to reach `sigedge-hf` /
`sigedge-vhf-uhf`). Every time `radiod` restarts with dynamic addressing,
that value goes stale and the SIGliere gateway loses reachability until
someone manually re-syncs it (exactly what happened this session — see
below).

**Recommendation for a SIGedge session:** adopt the static-address override
scheme from `NETWORKING.md` for any radiod instance SIGliere's gateway is
supposed to reach, so the multicast address is stable across restarts and
`nodes.json` doesn't need hand-updating after every SIGedge-side restart.

### 3. Unconfirmed: does `ka9q-python`'s `discover_channels_native` actually
filter by the passed multicast address?
Observed anomaly, not fully diagnosed: after editing SIGliere's
`nodes.json` to point `sigedge-hf` at the new live address
(`239.113.183.73`) but *before* restarting the `sigliere-gateway`
container/process, a call to the gateway's `/status/sigedge-hf` endpoint
still echoed the **old**, stale `status_address`
(`239.95.191.236`) in its response — expected, since the process caches
`nodes.json` at startup — but it also reported `"reachable": true"` with a
live channel matching the WWV stream that's actually broadcasting on
`239.113.183.73`/`239.101.208.192`, not `239.95.191.236`.

That's suspicious: either the SDK's `discover_channels_native()` doesn't
strictly join/filter on the literal address argument (e.g. it does a
broader mDNS/network browse and returns whatever `radiod` instances it
finds), or there's some other explanation not yet investigated. Only one
`radiod` instance was up on the LAN at the time, so this couldn't be
distinguished from "found the right one by address" vs. "found the only one
that exists, regardless of address." If/when multiple `radiod` instances
with different declared multicast addresses are running simultaneously,
worth deliberately testing whether querying one node's declared address can
return another node's channels — that would be a real correctness gap in
node-vs-address matching, not just a caching quirk.

## Reference: what's now confirmed working end-to-end

- `radiod@rx888-wwv` → real RX-888 hardware → live WWV 10 MHz AM decode.
- mDNS/Avahi announcement (`sigedge-rx888.local`, `sigedge-wwv10.local`)
  resolves correctly.
- `control` (ka9q-radio's own CLI) discovers and queries the instance
  successfully.
- SIGliere gateway's `ka9q-python` client (`discover_channels_native`)
  reaches the live status address and returns real channel/SNR data.
- SIGliere's `gateway/config/nodes.json` `sigedge-hf.status_address` has
  been updated to the current live value (`239.113.183.73`) and the gateway
  container/service has been restarted to pick it up. **This will go stale
  again the next time `radiod@rx888-wwv` restarts unless open item #2 above
  is addressed.**
