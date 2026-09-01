# Networking Setup

## Intro
By default, ka9q-radio uses mDNS (Avahi) and dynamic IP multicast hashing (turning names like vhf.local automatically into 239.x.x.x addresses). However, if you want to force explicit static IP destinations/sources and a structured scheme for multi-node setups or managed local subnets, you can override this behavior.

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