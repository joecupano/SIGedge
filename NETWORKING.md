# Networking Setup

## Intro
By default, ka9q-radio uses mDNS (Avahi) and dynamic IP multicast hashing (turning names like vhf.local automatically into 239.x.x.x addresses). However, if you want to force explicit static IP destinations/sources and a structured scheme for multi-node setups or managed local subnets, you can override this behavior.

## How the override actually works
This is verified against ka9q-radio's actual source (`src/radio.c`, `src/modes.c`,
`src/multicast.c`), not just its docs — the two disagree in ways worth knowing before you
touch a template.

`status` (global) and `data` (per-channel) are each resolved by one of two mechanisms,
selected by the `dns` setting (global default, per-channel override):

- `dns = off` (the default). `radiod` hashes the field's exact string with FNV-1 into a
  `239.0.0.0/8` address (`make_maddr()` — a pure function of the string, no time/PID/other
  entropy). **This is already stable, not random per restart** — the same string always
  hashes to the same address. What actually goes stale is the string itself changing (a
  different mission name, a different host, an edited template), not the act of
  restarting.
- `dns = yes`. `radiod` instead resolves the field with a real `getaddrinfo()` lookup,
  falling back to the same hash if that fails. A literal `239.x.x.x` address resolves to
  itself here — **for `data`**. **`status` is different: `radiod` unconditionally appends
  `.local` to whatever's in the `status` field before resolving it**
  (`ensure_suffix(cp,".local")` in `radio.c`, run regardless of `dns`), so a literal
  address there becomes an unresolvable string like `239.192.1.20.local` and silently
  falls back to hashing *that* — not the address you wrote. Confirmed live on this host: a
  template with `status = 239.192.1.20` actually broadcast status on `239.103.203.219`
  (FNV-1 of `"239.192.1.20.local"`), not `239.192.1.20` — `239.192.1.20` carried nothing.

So the two fields need different treatment to land on a chosen address:

```
[global]
dns = yes
status = sigedge-rx888.local   # unchanged name; ensure_suffix() is then a no-op
data = 239.192.64.10           # literal address; no mangling for per-channel data
```

`status` then resolves via a real lookup of `sigedge-rx888.local` — on Debian/Ubuntu,
`/etc/hosts` is consulted before mDNS (`hosts: files mdns4_minimal ... dns` in
`/etc/nsswitch.conf`), so a static `/etc/hosts` entry for that exact name is what pins it.
`scripts/cfg_ka9q-radio` manages this entry automatically (see its own comments); it isn't
something the checked-in templates can do alone.

Avahi/mDNS advertisement (`avahi_start()`) is gated by the separate `advertise` setting
(default on), not by `dns` — it runs either way and publishes whatever address `status`/
`data` actually resolved to, hashed or static. So none of this costs `avahi-browse`/
`*.local` discoverability; a consumer can keep resolving by name *or* use the fixed
address directly.

**`dns = yes`, not `dns = on`.** ka9q-radio's config parser (`iniparser`) decides a
boolean purely from the value's *first character* — `y`/`Y`/`1`/`t`/`T` is true,
`n`/`N`/`0`/`f`/`F` is false, anything else (including `on`, `off`, `enabled`) silently
falls through to whatever default the call site passed, which for `dns` is `false`. Write
`dns = on` in a template and it is indistinguishable from not setting `dns` at all — no
warning, no error, just quietly still hashing. This bit twice while building this scheme:
both `status`'s hosts-file lookup and `data`'s literal address were being silently ignored
until every `dns = on` in the templates below was corrected to `dns = yes`.

## Deployment Structure

```
SITE
    EDGE NODE
        RECEIVER
            CHANNEL

MTNVILLE
    sigedge
        rx888
            ch-01
            ch-02 ...

```

## Multicast schema

```
239.192.0.0/24    SIGedge platform

239.192.1.0/24    SIGedge platform status/control
239.192.2.0/24    Second SIGedge platform status/control

239.192.32.0/24   IQ Channels
239.192.64.0/24   Audio Channels
239.192.96.0/24   Spectrum/Telemetry
```

## Current static assignment

This host is SIGedge platform #1 (`239.192.1.0/24` for status/control). Its three proven
reference missions (`scripts/cfg_ka9q-radio`, `config/radiod@<instance>.conf`) each get a
status address from that pool and a data address from the Audio Channels pool — all three
missions demodulate to audio, none run a raw IQ or spectrum/telemetry channel today. The
host-portion suffix (`.10`/`.20`/`.30`) is shared between a mission's status and data
address so the pairing is visible at a glance:

| Instance | Signal | Status (`239.192.1.0/24`) | Data (`239.192.64.0/24`) |
|---|---|---|---|
| `radiod@rx888-wwv` | WWV 10.000 MHz AM | `239.192.1.10` | `239.192.64.10` |
| `radiod@hackrf-aprs` | APRS 144.390 MHz FM | `239.192.1.20` | `239.192.64.20` |
| `radiod@rtlsdr-simplex` | Simplex 144.650 MHz FM | `239.192.1.30` | `239.192.64.30` |

The data addresses are checked into the templates directly (not filled in by
`scripts/cfg_ka9q-radio` — they aren't host-specific the way
`##TTL##`/`##IFACE##`/`##SERIAL##` are). The status addresses are this same table, but
reach `radiod` indirectly: each template keeps its human-readable
`status = sigedge-<hardware>.local`, and `scripts/cfg_ka9q-radio` syncs a static
`/etc/hosts` entry pointing that exact name at the address above — see "How the override
actually works" for why status can't just take the literal address the way data does. A
second
SIGedge platform on the LAN should use `239.192.2.0/24` for status/control and its own
suffix range (e.g. `.110`/`.120`/`.130`) out of the same `239.192.32.0/24` /
`239.192.64.0/24` / `239.192.96.0/24` channel-type pools, so two platforms' channels never
collide even though they share those pools.

## Example

```
[global]
hardware = rx888

# Status/Control name
status = sigedge-rx888.local

# Force multicast onto the SDR data-plane interface
iface = eno1

#  1 - Keep multicast to local LAN, 0 - local to box
ttl = 1
fft-threads = 2

[rx888]
device = rx888
description = "SIGedge RX888 HF"

# Half-rate operation covers HF through 30 MHz and reduces host
# load substantially compared to 129.6 MS/s.
samprate = 64800000
gain = 0

[WWV-10-IQ]
disable = no
freq = "10m000000"
mode = iq
samprate = 16000
encoding = float
data = sigedge-wwv10-iq.local
agc = 0
gain = 0

[FT8-20M]
disable = no
freq = "14m074000"
mode = usb
samprate = 12000
encoding = float
data = sigedge-ft8-20m.local

# Pass normal FT8 audio range with some margin
low = 100
high = 3500

agc = 0
gain = 0

[CW-30M]
disable = no
freq = "10m106000"
mode = cw
samprate = 12000
encoding = float
data = sigedge-cw-30m.local

# Narrow CW audio passband
low = 300
high = 1200

agc = 1
gain = 0

```

**SSRC and Frequency Overlap**
Dynamic channel tools typically instantiate streams using an SSRC derived from the channel's frequency in Hertz. If a dynamic channel is spun up on a frequency already governed by static configuration, it can result in duplicate or conflicting RTP streams fighting for the same destination socket buffer.