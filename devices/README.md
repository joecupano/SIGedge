# Devices

These scripts are called during SIGedge installation as well as directly via
**SIGedge device (install|remove|purge|build|package) <DEVICE>** for managing
individual devices.

SIGedge project does its utmost to ensure the most recent stable releases for devices are available for installation and maintained in the **debs** directory.

When running **SIGedge device package <DEVICE>** the resulting debian packages are stored in the **debs** directory.

## DEVICES file format

Same shape as `packages/PACKAGES` -- see that file's README for the
rationale on separate arch columns:

```
name,version_amd64,version_arm64,description,date
```
