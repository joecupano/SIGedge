# Packages

These scripts are called during SIGedge installation as well as directly via
**SIGedge (install|remove|purge|build|package) <PACKAGE>** for managing
individual packages.

SIGedge project does its utmost to ensure the most recent stable releases for packages are available for installation and maintained in the **debs** directory.

When running **SIGedge package <PACKAGE>** the resulting debian packages are stored in the **debs** directory.

## PACKAGES file format

One line per package, comma-separated:

```
name,version_amd64,version_arm64,description,date
```

`version_amd64`/`version_arm64` are separate fields because the two
architectures do not always ship the same version -- e.g. a prebuilt `.deb`
in `debs/` for one arch can lag behind the other, or a from-source build can
need a different pinned commit per arch to work around an arch-specific
upstream bug. When both architectures genuinely match, both fields carry the
same value. `date` is `YYYYMMDD`. No header/comment line: every consumer
(`SIGedge list packages|installed|library`, each `pkg_*` script's own
`SIGEDGE_INSTALLED`-append pattern) reads every line as data.
