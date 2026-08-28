#!/bin/bash

###
### SIGedge
###
### run_ka9q-radio.sh
###

###
###  REVISION: 20260827-2300
###

sudo systemctl enable --now radiod@
sleep 3
sudo systemctl start --now radiod@
sleep 3
systemctl status radiod@
sleep 3
journalctl -u radiod@