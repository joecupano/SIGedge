# Scripts

## First time setup
When **./SIGedge setup** is run it calls the following scripts in order:

- **setup_start**
starts a menu to select devices and services

- **setup_core**
installs baseline software and libraries used across packages.

- **setup_device**
installs drivers and supporting software for devices. Each device has
its own **scripts/pkg_<device>** for installation and removal.

- **setup_services**
installs and setups services that use the devices. The services are setup
but further configuration is necessary for each service before enabling them.

## Services ##
- **cfg_ka9q-radio**
Directly sourced by **setup_services** during **SIGedge setup**.
Reachable via **SIGedge config ka9q-radio <mission>**. 

## Environment support
- **SIGedge_env**
Environment variables used by SIGedge project. Use as a template for your
own custom scripts>
