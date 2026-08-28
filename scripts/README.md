# Scripts

These scripts are called during SIGpi installation. SOme of them in turn call the scripts in **devices** and **package**

## setup_start 
called by **SIGedge** Depending on options passed either **setup_core** or **setup_devices** are run next

## setup_core
Installs devices selected, core packages, running **setup_devices**, **setup_core_packages** respectively

## Various support scripts

**SIGedge_env**
**SIGedge_exec-in-shell**
**run_SDRplay.sh**
**run_direwolf.sh**
**run_sdrangel.sh**
**run_urh.sh**
