#!/bin/bash

###
### SIGedge
###
### verify_ka9q-radio.sh
###

###
###  REVISION: 20260827-2300
###

# Hardware
lsusb
sleep 3
lsusb -t
sleep 3

# HackRF
hackrf_info
sleep 3

# RTL-SDR
rtl_test -t
sleep 3

# Soapy Devices
SoapySDRUtil --find
sleep 3

# KA9Q Services
journalctl -u radiod@rx888
sleep 3
journalctl -u radiod@rtlsdr
sleep 3
journalctl -u radiod@hackrf
sleep 3

# mDNS
avahi-browse -art
sleep 3

# multicast activity
ip maddr show
sleep 3

# Network Traffic
# What is the IP Address
SIGEDGE_IPADDR=`ip -br address | grep UP | awk '{print $1}'`
sudo tcpdump -ni $SIGEDGE_IPADDR multicast
sleep 3

# Process Utilization
htop
sleep 3
