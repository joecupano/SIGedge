# KA9Q DEPLOYMENT

Below is a practical Ubuntu 24.04 installation path for **ka9q-radio** intended for an SDR edge node that may host an **RX-888 MkII, HackRF One, and RTL-SDR**. It uses the current upstream ka9q-radio architecture, where `radiod` directly interfaces with supported SDR front ends and distributes control, status, IQ, and demodulated streams over IP multicast. ([GitHub][1])

One important distinction for your broader edge architecture: **SoapySDR is not in the ka9q-radio data path for these three radios.** You may still want SoapySDR installed so applications such as SDRangel, GNU Radio, or custom services can access hardware independently, but `radiod` uses its own hardware interfaces.

## 1. Recommended host baseline

For Ubuntu:

* Ubuntu Server **24.04 LTS x86-64**
* 4+ CPU cores
* 8 GB RAM minimum
* Gigabit Ethernet minimum
* USB 3.x controller for RX-888 MkII
* preferably dedicated USB controller/root hub for RX-888
* static IP or DHCP reservation
* wired Ethernet preferred over Wi-Fi

The RX-888 is the demanding device. At 129.6 Msps it can move **more than 2 Gbit/s over USB**, and ka9q's current default is 64.8 Msps partly because full-rate operation increases thermal and system load. ka9q recommends effectively one RX-888 per host. ([GitHub][2])

Verify Ubuntu:

```bash
lsb_release -a
uname -a
```

Update it:

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

After reboot:

```bash
sudo apt update
```

---

# 2. Enable Ubuntu Universe

Some SDR packages reside in Universe.

```bash
sudo add-apt-repository universe
sudo apt update
```

---

# 3. Install build dependencies

Start with the packages needed by ka9q-radio plus the three SDR interfaces.

```bash
sudo apt install -y \
    git \
    build-essential \
    gcc \
    g++ \
    make \
    pkg-config \
    rsync \
    avahi-daemon \
    avahi-utils \
    libavahi-client-dev \
    libbsd-dev \
    libfftw3-dev \
    libiniparser-dev \
    libncurses-dev \
    libncursesw5-dev \
    libopus-dev \
    libogg-dev \
    libsamplerate0-dev \
    libliquid-dev \
    portaudio19-dev \
    libasound2-dev \
    uuid-dev \
    libusb-1.0-0-dev \
    libusb-dev \
    libhackrf-dev \
    hackrf \
    librtlsdr-dev \
    rtl-sdr
```

Recent ka9q-radio installation guidance includes libraries for FFTW, Avahi, HackRF, RTL-SDR, audio, USB, and related components. ([GitHub][3])

Enable Avahi:

```bash
sudo systemctl enable --now avahi-daemon
```

Check it:

```bash
systemctl status avahi-daemon
```

Avahi matters because ka9q-radio uses multicast DNS for service discovery.

---

# 4. Optional: install SoapySDR

I recommend doing this on your edge platform even though ka9q-radio itself doesn't require it for these SDRs.

```bash
sudo apt install -y \
    soapysdr-tools \
    libsoapysdr-dev \
    soapysdr-module-hackrf \
    soapysdr-module-rtlsdr
```

Ubuntu provides native Soapy modules for both HackRF and RTL-SDR. ([GitHub][4])

Verify:

```bash
SoapySDRUtil --info
```

Then:

```bash
SoapySDRUtil --find
```

Expect devices such as:

```text
driver=hackrf
```

and/or

```text
driver=rtlsdr
```

Do **not** expect RX-888 support through this step. Its ka9q-radio path is native.

---

# 5. Clone ka9q-radio

Use the current upstream repository:

```bash
cd ~
git clone https://github.com/ka9q/ka9q-radio.git
cd ka9q-radio
```

Record the build version:

```bash
git rev-parse HEAD
```

For an operational edge platform, I recommend storing this commit hash in your configuration-management inventory rather than blindly updating `main` in production.

---

# 6. Build ka9q-radio

Build:

```bash
make -j"$(nproc)"
```

Watch the final output for the relevant hardware modules.

Current installations can produce modules such as:

```text
hackrf.so
rtlsdr.so
rx888.so
```

ka9q-radio introduced dynamically loadable front-end drivers in 2025, although several common interfaces have historically also been compiled into `radiod`. ([GitHub][5])

Check:

```bash
find . -name 'hackrf.so' -o -name 'rtlsdr.so' -o -name 'rx888.so'
```

Then install:

```bash
sudo make install
```

Run:

```bash
sudo ldconfig
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo udevadm trigger
```

The installation creates, among other things:

```text
/usr/local/sbin/radiod
/usr/local/bin/control
/usr/local/bin/monitor
/usr/local/lib/ka9q-radio/
/etc/radio/
/etc/systemd/system/radiod@.service
```

and installs udev rules for RX-888, HackRF, and RTL-SDR. ([GitHub][6])

Verify:

```bash
which radiod
which control
which monitor
```

Normally:

```text
/usr/local/sbin/radiod
/usr/local/bin/control
/usr/local/bin/monitor
```

---

# 7. Verify the installed hardware modules

Run:

```bash
ls -lh /usr/local/lib/ka9q-radio/
```

Look for:

```text
hackrf.so
rtlsdr.so
rx888.so
```

Exact module composition can vary with the source revision and installed development libraries.

---

# 8. Configure multicast networking

ka9q-radio is fundamentally a **multicast SDR architecture**, not a conventional TCP SDR server. All signal/control/status traffic can use IP multicast. ([GitHub][1])

Find your wired interface:

```bash
ip -br addr
```

Typical Ubuntu names:

```text
enp2s0
eno1
ens18
```

Test multicast capability:

```bash
ip link show
```

You want `MULTICAST` on the desired interface.

For a dedicated SDR edge node I recommend explicitly specifying the Ethernet interface in `radiod` configurations. This avoids cases where Linux sends multicast over Wi-Fi or another interface after boot. The ka9q documentation specifically identifies this issue on multi-interface systems. ([GitHub][5])

For example:

```ini
iface = enp2s0
```

Use your actual interface name.

---

# 9. Test the RX-888 MkII

Plug the RX-888 directly into a USB 3.x port.

Check USB topology:

```bash
lsusb
```

and:

```bash
lsusb -t
```

The RX-888 should be connected through a SuperSpeed path rather than:

```text
480M
```

You ideally want:

```text
5000M
```

or greater.

Inspect kernel messages:

```bash
sudo dmesg --follow
```

Then unplug/replug the RX-888.

## RX-888 ka9q configuration

Create:

```bash
sudo nano /etc/radio/radiod@rx888.conf
```

Start with:

```ini
[global]
hardware = rx888
status = rx888.local
iface = enp2s0

[rx888]
device = rx888
description = "RX888 MkII Edge Receiver"
samprate = 64800000
```

Replace:

```text
enp2s0
```

with your interface.

The upstream configuration is essentially this simple because the RX-888 implementation is native to ka9q-radio and requires no separate SDR library. ([GitHub][2])

The initial sample rate should remain:

```text
64,800,000
```

rather than immediately using 129.6 MHz.

That yields roughly 0–32 MHz of alias-free spectrum under normal Nyquist assumptions, subject to your front-end filtering.

The RX-888 support currently uses **direct sampling**. The R828 tuner/downconverter path associated with the VHF input is not currently supported by ka9q-radio. ([GitHub][2])

---

# 10. Start the RX-888 instance

Because ka9q installs a templated systemd service:

```bash
sudo systemctl enable --now radiod@rx888
```

Check:

```bash
systemctl status radiod@rx888
```

Logs:

```bash
journalctl -u radiod@rx888 -f
```

If it starts successfully, `radiod` should initialize the RX-888 and begin advertising its service/status information.

---

# 11. Verify RX-888 service discovery

Run:

```bash
avahi-browse -art
```

You can narrow this depending on the advertised ka9q service:

```bash
avahi-browse -rt _ka9q-ctl._udp
```

That discovery method is also used by projects consuming ka9q-radio streams. ([GitHub][7])

---

# 12. Test the RTL-SDR

Before starting ka9q, make sure the SDR itself works.

```bash
rtl_test -t
```

A successful result should identify the tuner.

If you get:

```text
Kernel driver is active
```

or similar DVB conflicts, inspect:

```bash
lsmod | grep dvb
```

Ubuntu may have claimed the USB stick with the DVB kernel driver.

The ka9q installation includes RTL-SDR-specific udev handling, but if necessary blacklist the DVB module applicable to your particular tuner.

After changing module rules:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Disconnect/reconnect the stick.

Re-test:

```bash
rtl_test -t
```

---

# 13. Configure RTL-SDR for ka9q-radio

Create:

```bash
sudo nano /etc/radio/radiod@rtlsdr.conf
```

Initial configuration:

```ini
[global]
hardware = rtlsdr
status = rtlsdr.local
iface = enp2s0

[rtlsdr]
device = rtlsdr
description = "RTL-SDR Edge Receiver"
```

ka9q-radio currently supports generic RTL-SDR devices in **tuner mode**. ([GitHub][5])

Start it:

```bash
sudo systemctl enable --now radiod@rtlsdr
```

Check:

```bash
systemctl status radiod@rtlsdr
```

and:

```bash
journalctl -u radiod@rtlsdr -f
```

---

# 14. Validate RTL-SDR through Soapy

Separately:

```bash
SoapySDRUtil --find="driver=rtlsdr"
```

Then probe it:

```bash
SoapySDRUtil --probe="driver=rtlsdr"
```

This verifies the **parallel application ecosystem** independently of ka9q-radio.

Think of these as two distinct access paths:

```text
                   +--> radiod native RTL-SDR driver
RTL-SDR -- libusb -+
                   +--> librtlsdr --> SoapyRTLSDR --> SDRangel/etc
```

They should **not normally access the same physical dongle simultaneously**.

---

# 15. Test the HackRF

Plug in the HackRF.

Run:

```bash
hackrf_info
```

You should see something like:

```text
Found HackRF
Serial number: ...
Board ID Number: ...
Firmware Version: ...
```

If not:

```bash
lsusb
```

Then:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Disconnect and reconnect it.

Retry:

```bash
hackrf_info
```

---

# 16. Verify HackRF through Soapy

```bash
SoapySDRUtil --find="driver=hackrf"
```

Probe:

```bash
SoapySDRUtil --probe="driver=hackrf"
```

This proves your conventional SDR application path.

---

# 17. Configure HackRF for radiod

Here I recommend a little more caution.

The current ka9q hardware documentation lists:

```text
hackrf
```

as a supported front end, and recent installation output includes `hackrf.so`. ([GitHub][8])

However, some upstream narrative documentation still contains older language indicating that HackRF integration was being reworked. ([GitHub][5])

So verify the exact source revision you built before relying on HackRF operationally.

Create:

```bash
sudo nano /etc/radio/radiod@hackrf.conf
```

Start minimally:

```ini
[global]
hardware = hackrf
status = hackrf.local
iface = enp2s0

[hackrf]
device = hackrf
description = "HackRF Edge Receiver"
```

Run interactively first rather than enabling at boot:

```bash
sudo /usr/local/sbin/radiod /etc/radio/radiod@hackrf.conf
```

If that initializes cleanly, stop it with `Ctrl-C`.

Then:

```bash
sudo systemctl start radiod@hackrf
```

Check:

```bash
journalctl -u radiod@hackrf -f
```

Only after validation:

```bash
sudo systemctl enable radiod@hackrf
```

---

# 18. Run several SDRs concurrently

ka9q's systemd template makes this straightforward:

```text
radiod@rx888
radiod@hackrf
radiod@rtlsdr
```

Check all:

```bash
systemctl status 'radiod@*'
```

or:

```bash
systemctl list-units 'radiod@*'
```

Architecture:

```text
                    Ubuntu 24.04 SDR Edge Node
 +----------------------------------------------------------------+
 |                                                                |
 | RX-888 MkII --USB3--> radiod@rx888 -----+                      |
 |                                          |                      |
 | HackRF ------USB----> radiod@hackrf -----+---- RTP/IP Multicast|
 |                                          |                      |
 | RTL-SDR -----USB----> radiod@rtlsdr -----+                      |
 |                                                                |
 |                        |                                       |
 |                        +--> control/status                     |
 |                        +--> channel IQ                          |
 |                        +--> PCM/audio                           |
 |                        +--> downstream decoders                 |
 +------------------------|---------------------------------------+
                          |
                       Ethernet
                          |
       +------------------+------------------+
       |                  |                  |
   Analytics          Decoders            MCP/API
   services           services            services
```

This is where ka9q-radio becomes particularly useful for the edge architecture we were discussing: consumers attach to multicast output rather than opening the SDR hardware itself.

---

# 19. Do not let multiple applications fight over an SDR

This becomes important when you install SoapySDR alongside ka9q-radio.

For example, don't expect:

```text
radiod@hackrf
```

and:

```text
SDRangel -> SoapyHackRF
```

to independently control the same physical HackRF.

Use ownership boundaries.

A sensible arrangement is:

| Radio      | Hardware owner   | Consumers                 |
| ---------- | ---------------- | ------------------------- |
| RX-888 #1  | ka9q `radiod`    | MCP, analytics, recorders |
| HackRF #1  | ka9q `radiod`    | multicast consumers       |
| HackRF #2  | SDRangel/Soapy   | interactive operator      |
| RTL-SDR #1 | ka9q `radiod`    | fixed monitoring          |
| RTL-SDR #2 | OpenWebRX+/Soapy | web users                 |

This matches your earlier decision that you are willing to dedicate SDRs to specific software stacks.

---

# 20. Verify multicast traffic

While radiod is running:

```bash
ip maddr show
```

You should see multicast memberships.

Capture multicast traffic:

```bash
sudo tcpdump -ni enp2s0 multicast
```

Or:

```bash
sudo tcpdump -ni enp2s0 udp
```

If you see traffic on the wrong interface, explicitly set:

```ini
iface = enp2s0
```

in each `radiod` configuration.

This is especially important on a node having:

```text
eno1
wlan0
docker0
tailscale0
virbr0
```

or Kubernetes/container bridge interfaces.

---

# 21. Firewall considerations

Check Ubuntu firewall:

```bash
sudo ufw status
```

If this is a controlled SDR VLAN, my preference is not to globally disable filtering. Instead permit multicast/UDP only on the trusted SDR interface/VLAN.

Also inspect:

```bash
sysctl net.ipv4.conf.all.rp_filter
```

Strict reverse-path filtering can sometimes interact badly with unusual multicast/multi-homed designs.

For an edge node that will eventually run Docker or Kubernetes, carefully validate multicast after adding container networking. Docker bridge/NAT and CNI networking can make multicast behavior significantly more complex.

---

# 22. RX-888 performance tuning

For the RX-888 in particular:

```bash
lsusb -t
```

Make certain other high-bandwidth devices are not on the same root hub.

Monitor:

```bash
htop
```

and:

```bash
watch -n1 'grep -E "cpu MHz" /proc/cpuinfo | head'
```

Check USB errors:

```bash
journalctl -k -f
```

At 64.8 Msps the RX-888 is already feeding the host roughly:

```text
64.8M samples/sec × 16 bits
≈ 1.04 Gbit/sec
```

before USB/protocol overhead.

At 129.6 Msps:

```text
129.6M × 16
≈ 2.07 Gbit/sec
```

which explains ka9q's warning about USB and thermal constraints. ([GitHub][2])

For an operational edge system I would start with:

```ini
samprate = 64800000
```

and only move to:

```ini
samprate = 129600000
```

after sustained USB, CPU, and thermal testing.

---

# 23. Useful health-check commands

I would put these in your edge-node runbook.

Hardware:

```bash
lsusb
lsusb -t
```

HackRF:

```bash
hackrf_info
```

RTL-SDR:

```bash
rtl_test -t
```

Soapy devices:

```bash
SoapySDRUtil --find
```

ka9q services:

```bash
systemctl list-units 'radiod@*'
```

RX-888:

```bash
journalctl -u radiod@rx888
```

HackRF:

```bash
journalctl -u radiod@hackrf
```

RTL-SDR:

```bash
journalctl -u radiod@rtlsdr
```

mDNS:

```bash
avahi-browse -art
```

Multicast:

```bash
ip maddr show
```

Network traffic:

```bash
sudo tcpdump -ni enp2s0 multicast
```

Process utilization:

```bash
htop
```

---

# 24. Recommended software stack for your edge platform

Given the architecture you described previously, I would install the node in layers:

```text
APPLICATION / SERVICE LAYER
------------------------------------------------
Ollama
MCP SDR Server
OpenWebRX+
SDRangel
GNU Radio
recorders / decoders / analytics

NETWORK SDR LAYER
------------------------------------------------
ka9q-radio
  radiod
  RTP
  IP multicast
  mDNS / Avahi

HARDWARE ABSTRACTION LAYER
------------------------------------------------
Native drivers             SoapySDR
  rx888                       |
  hackrf                    SoapyHackRF
  rtlsdr                    SoapyRTLSDR
                             future SDRs

OS / DEVICE LAYER
------------------------------------------------
libusb
udev
systemd
Ubuntu 24.04

HARDWARE
------------------------------------------------
RX-888 MkII
HackRF
RTL-SDR
```

I would **not** put SoapySDR between the RX-888 and ka9q-radio. For the RX-888, let `radiod` own the hardware.

---

# 25. Recommended operational model

For the platform you're building, I would go one step further and separate **radio ownership** from **radio consumption**:

```text
                     SDR EDGE NODE

      +--------------------------------------+
      | Radio Hardware Manager               |
      |                                      |
      | RX888 ------> radiod                 |
      | HackRF -----> radiod                 |
      | RTL-SDR ----> radiod                 |
      |                                      |
      +------------------+-------------------+
                         |
                      multicast
                         |
            +------------+------------+
            |            |            |
         Analyst       AI/MCP       Recorder
         services      services      services
            |
        read-only
```

The edge node becomes the **authoritative hardware-control plane**, while downstream services become consumers.

For the analyst/operator distinction you raised previously, that also provides a clean security boundary:

```text
ANALYST
  subscribe to multicast streams
  read telemetry/status
  no direct hardware access

OPERATOR
  invoke authenticated control API
        |
        v
  MCP/API control service
        |
        v
  ka9q control protocol
        |
        v
      radiod
        |
        v
       SDR
```

That is substantially safer than exposing `librtlsdr`, `libhackrf`, or raw USB devices to every container or application.

## One caution on HackRF

The current tree clearly contains HackRF integration artifacts and lists HackRF as a front end, but upstream documentation is not completely synchronized: one current hardware document lists it as supported while another narrative note still describes reintegration work. ([GitHub][8])

For that reason, for a production image I would pin a known-good ka9q commit and make **HackRF initialization a CI hardware-in-the-loop test**, rather than assuming every new `main` commit has identical behavior.

For **RX-888 MkII**, the current native ka9q path is much more clearly documented and is the path I would use as the primary wideband HF ingest engine. ([GitHub][2])

If this edge platform is going to become a repeatable Ubuntu appliance, the next logical step is to turn the installation above into an **Ansible role or unattended provisioning script** that installs ka9q-radio, SoapySDR, udev rules, three `radiod@` configurations, multicast/network tuning, and a health-check service.

I can also build a **production reference architecture for this node** showing `radiod`, SoapySDR, OpenWebRX+, SDRangel, MCP, Ollama, containers, VLANs, multicast groups, and the analyst/operator control boundaries.

[1]: https://github.com/ka9q/ka9q-radio?utm_source=chatgpt.com "GitHub - ka9q/ka9q-radio: Multichannel SDR based on fast convolution and IP multicasting · GitHub"
[2]: https://github.com/ka9q/ka9q-radio/blob/main/docs/SDR/rx888.md?utm_source=chatgpt.com "ka9q-radio/docs/SDR/rx888.md at main · ka9q/ka9q-radio · GitHub"
[3]: https://github.com/projecthorus/radiosonde_auto_rx/wiki/KA9Q%E2%80%90Radio-Setup-Notes?utm_source=chatgpt.com "KA9Q‐Radio Setup Notes · projecthorus/radiosonde_auto_rx Wiki · GitHub"
[4]: https://github.com/kevinmehall/rust-soapysdr?utm_source=chatgpt.com "GitHub - kevinmehall/rust-soapysdr: Rust bindings for SoapySDR, the vendor-neutral software defined radio hardware abstraction layer · GitHub"
[5]: https://github.com/ka9q/ka9q-radio/blob/main/docs/notes.md?utm_source=chatgpt.com "ka9q-radio/docs/notes.md at main · ka9q/ka9q-radio · GitHub"
[6]: https://github.com/ka9q/ka9q-radio/issues/226?utm_source=chatgpt.com "make install does not create /etc/fftw on Raspberry Pi OS Trixie · Issue #226 · ka9q/ka9q-radio · GitHub"
[7]: https://github.com/HamSCI/hf-timestd/blob/main/docs/EXTERNAL_PREREQUISITES.md?utm_source=chatgpt.com "hf-timestd/docs/EXTERNAL_PREREQUISITES.md at main · HamSCI/hf-timestd · GitHub"
[8]: https://github.com/ka9q/ka9q-radio/blob/main/docs/ka9q-radio-2.md?utm_source=chatgpt.com "ka9q-radio/docs/ka9q-radio-2.md at main · ka9q/ka9q-radio · GitHub"
