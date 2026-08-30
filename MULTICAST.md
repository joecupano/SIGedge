# Multicast Setup

## Intro
By default, ka9q-radio uses mDNS (Avahi) and dynamic IP multicast hashing (turning names like vhf.local automatically into 239.x.x.x addresses). However, if you want to force explicit static IP destinations/sources and a structured naming scheme for multi-node setups or managed local subnets, you can override this behavior using the dns = yes parameter along with explicit host/IP mapping.  

## Naming Scheme Convention
Design a clean, hierarchical naming convention for your station nodes, hardware front-ends, and virtual channels.

- Nodes/Hosts: <location>-<rig> (e.g., station1-hackrf.local)
- Status/Control Streams: <node>.<purpose>.status (e.g., station1.vhf.status)
- Data Streams: <node>.<channel>.stream (e.g., station1.aprs.stream)

## Configuring radiod@.conf for static names and IP addresses
To bypass automatic multicast hashing and map streams directly to static IP addresses (or fixed local hostnames mapped in /etc/hosts), enable dns = yes and explicitly define your status and data parameters.

```
[global]
hardware = hackrf-vhf
blocktime = 20
overlap = 5
fft-threads = 4

# Force DNS/Static IP resolution instead of automatic mDNS hashing
dns = yes 

# Static naming and explicit destination for the node's central control
status = station1.vhf.status
# If binding to a specific network interface card (e.g., dedicated wired Ethernet)
iface = eth0

[hackrf-vhf]
device = hackrf
freq = 145500000
samprate = 8000000
gain = 20
amp = y
data = 192.168.1.50         # Static target IP for raw hardware IQ output stream
status = station1.hw.status

[aprs]
freq = 144390000
mode = nfm
samprate = 24000
dns = yes
data = 192.168.1.101         # Static IP destination where your APRS decoder pulls this stream
```

## Fixing Static IPs in /etc/hosts for Clean Names
If you prefer using readable hostnames over raw IP numbers while maintaining strict static routing, map them manually in the Linux system resolver table on every machine handling streams (/etc/hosts):

```
# /etc/hosts mapping for ka9q-radio static cluster
192.168.1.50   station1-hackrf.local
192.168.1.101  aprs-decoder.local
192.168.1.102  packet-node.local
```

When dns = yes is set in your config files, ka9q-radio will query the system resolver or local hosts file instead of generating dynamic local multicast groups, locking your data streams to those exact designated static routes.