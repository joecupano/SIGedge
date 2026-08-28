# SIGedge

## Introduction

**SIGedge** is a SDR platform that abstracts attached RF hardware and exposes usable RF/IQ/audio services to multiple network-connected consumers such as AI/LLM workflows, signals analysis (SDRangel, OpneWebRX+, etc) recorders, and custom analytics.

**SIGedge** can be built on the following platforms:

- Intel i5 with 16GB RAM and 128GB storage
- Raspberry Pi 5 with 8GB RAM, 64GB storage
- Ubuntu Server 24.04 LTS (amd64 and arm64)

## Setup

```
sudo apt update && sudo apt upgrade
sudo apt-get install -y build-essential cmake git
cd ~
mkdir ~/SIGedge && cd ~/SIGedge
git clone https://github.com/joecupano/SIGedge.git
cd SIGedge
./SIGedge setup
```

## Adding Devices

Once started you will be given a menu of SDR devices to choose to install. RTL-SDR and HackRF are selected as defaults. Select the additional devices you would like to install and then click **OK**. For the next 15 to 20 minutes you will see messages scroll by as the SIGedge platform components are installed

After setup the system will reboot.

Don't worry about missing a device. Post install you can add it using **SIGedge device install <DEVICE>**

## Adding Packages

Once setup, you can list the inventory of packages SIGpi includes as well as those already installed with the following

```
SIGedge list library
```

An **asterisk** in the INSTALLED column indicates that package is already installed while those without asterisks have not been installed. For example, you will see **SDRangel Server** has not been installed. You can do so with the following

```
SIGpi install sdrangel-server
```

Go back and list again to install other packages of interest

## Managing Packages

Packages can be installed, removed and purged using the following commands respectively

```
SIGpi install <package>
SIGpi remove <package>
SIGpi purge <package>
```

Periodically new applications will be added to SIGpiand notifications sent to those watching the repo. To add applcations available for install into your SIGpi instance simple run run the following from within your /home/pi/SIG/SIGpi directory

```
git pull
```

You will see the new applications as available running the list library command

```
SIGedge list library
```

You can update packages in your existing SIGpi install. For example, if there is a  **SDRangel** update you can run

```
SIGedge update sdrangel-server

Update 7.27.3 is available

SIGedge upgrade sdrangel-server
```

## Example Hardware Setup
![alt-test](https://github.com/joecupano/SIGpi/blob/main/backgrounds/SIGpi_architecture.png)

### Power
In this setup a 12V@17A switching supply powers all the kit. Since RPi4 are picky about getting 5.1V a set-up converter is added to power it. A 12V Rpi4 are picky about getting 5.1V. USB peripherals can be hungry so a powered USB hub is included. While 7 ports are available no more than three devices requiring power should be enabled since hub produces a maximum of 36 Watts ( 3 x 5V x 2.4A = 36 Watts)

### Raspberry RPi4/5
Since this is a SIGINT platform we do not want to be generating any RF so onboard Bluetooth and WiFi should be disabled. If Internet is needed and only available via WiFi then so be it and use your onboard WiFi.

### USB Peripherals
Only three USB devices requiring power should be enabled at a time. The range of devices depicted is only to demonstrate what you could potentially connect to it.

