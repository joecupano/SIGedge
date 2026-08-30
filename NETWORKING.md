# Networking Setup

## Intro
By default, ka9q-radio uses mDNS (Avahi) and dynamic IP multicast hashing (turning names like vhf.local automatically into 239.x.x.x addresses). However, if you want to force explicit static IP destinations/sources and a structured naming scheme for multi-node setups or managed local subnets, you can override this behavior using the dns = yes parameter along with explicit host/IP/port  mapping.  

## Naming Scheme Convention
Design a clean, hierarchical naming and port convention for your station nodes, hardware front-ends, and virtual channels.

- Nodes: <rig> (e.g., hackrf.local)
- Status/Control Stream: <rig>.local:5004 (e.g., hackrf.local:5004)
- Data Streams: <rig>.local:<port 5010-5100> (e.g., hackrf.local:5010, hackrf.local:5012 ...)

## Fixing Static IPs in /etc/hosts for Clean Names
If you prefer using readable hostnames over raw IP numbers while maintaining strict static routing, map them manually in the Linux system resolver table on every machine handling streams (/etc/hosts):

If running on upstream services on the same host as SIGedge then use the loopback interface:
```
# Single-server ka9q-radio loopback routing
127.0.0.1   localhost
127.0.0.1   rx888.local
127.0.0.1   hackrf.local
127.0.0.1   rtlsdr.local
```

else the server's IP address:
```
# /etc/hosts mapping for ka9q-radio static cluster
127.0.0.1   localhost
192.168.73.100   rx888.local
192.168.73.100   hackrf.local
192.168.73.100   rtlsdr.local
```

When dns = yes is set in your config files, ka9q-radio will query the system resolver or local hosts file instead of generating dynamic local multicast groups, locking your data streams to those exact designated static routes.

## Configuring radiod@.conf for static names and IP addresses
To bypass automatic multicast hashing and map streams directly to static IP addresses (or fixed local hostnames mapped in /etc/hosts), enable dns = yes and explicitly define your status and data parameters.

```
[global]
hardware = myhackrf
blocktime = 20
overlap = 5
fft-threads = 4
dns = yes
status = hackrf.local

[myhackrf]
device = hackrf
description = "HackRF SDR Node"
freq = 145500000
samprate = 8000000
gain = 20
amp = y
data = hackrf.local:5004

[aprs]
freq = 144390000
mode = nfm
description = "HackRF APRS Stream"
samprate = 24000
dns = yes
data = hackrf.local:5006

[packet]
freq = 145100000
mode = nfm
description = "HackRF Packet Stream (145.10 MHz)"
samprate = 24000
dns = yes
data = hackrf.local:5008

[simplex]
freq = 146520000
mode = nfm
description = "HackRF Simplex 2m Stream (146.52 MHz)"
samprate = 24000
dns = yes
data = hackrf.local:5010
```

/etc/radio/modes.conf

```
[nfm]
demod = fm
samprate = 24000
low = -6250
high = +6250
deemph-tc = 0
threshold-extend = no
```

