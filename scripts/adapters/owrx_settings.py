#!/usr/bin/env python3
"""Read and reconcile OpenWebRX+'s SDR device list for scripts/adapters/openwebrx.

    owrx_settings.py claims    SETTINGS
        Print "kind id -" for every enabled device entry SIGedge knows how
        to map. id is the pinned serial, or "*" when the entry isn't pinned
        (it opens whichever device of that kind it finds).

    owrx_settings.py reconcile SETTINGS [kind:id ...]
        Make the enabled device entries match exactly the given
        assignments: matching entries are enabled (and pinned by serial
        where the driver supports it), entries that don't match are
        disabled (never deleted -- their profiles are kept), and an entry
        with a default profile is created for an assignment with none.
        Prints the number of enabled entries. Must run as a user that can
        write SETTINGS; ownership and mode are preserved.

Pinning: rtl_sdr takes the serial in "device"; hackrf (SoapyHackRF) takes
"serial=<serial>". sddc_soapy (the RX-888) can't select by serial -- the
RX888MK2-Soapy driver reports only a label -- so an RX-888 entry is never
pinned and the adapter allows only one attached RX-888.
"""

import json
import os
import sys
import tempfile
import uuid

# kind -> OpenWebRX+ source types that drive it (first one used when creating)
TYPES = {
    "rx888": ["sddc_soapy"],
    "hackrf": ["hackrf"],
    "rtlsdr": ["rtl_sdr"],
}

DEFAULT_PROFILES = {
    "rx888": {"name": "WWV 10 MHz", "center_freq": 11000000, "samp_rate": 32000000,
              "start_freq": 10000000, "start_mod": "am", "tuning_step": 100},
    "hackrf": {"name": "2 m APRS", "center_freq": 144800000, "samp_rate": 2400000,
               "start_freq": 144390000, "start_mod": "nfm", "tuning_step": 1000},
    "rtlsdr": {"name": "2 m simplex", "center_freq": 146000000, "samp_rate": 2400000,
               "start_freq": 146520000, "start_mod": "nfm", "tuning_step": 1000},
}

NAMES = {"rx888": "RX-888 MkII", "hackrf": "HackRF One", "rtlsdr": "RTL-SDR"}


def kind_of(entry):
    for kind, types in TYPES.items():
        if entry.get("type") in types:
            return kind
    return None


def soapy_args(text):
    args = {}
    for part in (text or "").split(","):
        if "=" in part:
            key, value = part.split("=", 1)
            args[key.strip()] = value.strip()
    return args


def pinned_id(kind, entry):
    device = entry.get("device")
    if not device:
        return "*"
    if kind == "rtlsdr":
        return str(device)
    if kind == "hackrf":
        return soapy_args(str(device)).get("serial", "*")
    return "*"


def pin(kind, entry, ident):
    if kind == "rtlsdr":
        entry["device"] = ident
    elif kind == "hackrf":
        args = soapy_args(entry.get("device"))
        args["serial"] = ident
        entry["device"] = ",".join(f"{k}={v}" for k, v in args.items())
    # rx888: no per-device selection available


def load(path):
    with open(path) as f:
        return json.load(f)


def save(path, data):
    st = os.stat(path)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".settings.")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=4)
        f.write("\n")
    os.chown(tmp, st.st_uid, st.st_gid)
    os.chmod(tmp, st.st_mode & 0o7777)
    os.replace(tmp, path)


def claims(path):
    for entry in load(path).get("sdrs", {}).values():
        kind = kind_of(entry)
        if kind and entry.get("enabled", True):
            print(kind, pinned_id(kind, entry), "-")


def reconcile(path, wanted):
    data = load(path)
    sdrs = data.setdefault("sdrs", {})
    wanted = [w.split(":", 1) for w in wanted]
    used = set()
    for kind, ident in wanted:
        if kind not in TYPES:
            sys.exit(f"unsupported kind: {kind}")
        # Prefer an entry already pinned to this device, then an unpinned one.
        match = None
        for key, entry in sdrs.items():
            if key not in used and kind_of(entry) == kind and pinned_id(kind, entry) == ident:
                match = key
                break
        if match is None:
            for key, entry in sdrs.items():
                if key not in used and kind_of(entry) == kind and pinned_id(kind, entry) == "*":
                    match = key
                    break
        if match is None:
            match = str(uuid.uuid4())
            sdrs[match] = {
                "name": NAMES[kind] if kind == "rx888" else f"{NAMES[kind]} {ident[-6:]}",
                "type": TYPES[kind][0],
                "profiles": {str(uuid.uuid4()): dict(DEFAULT_PROFILES[kind])},
            }
            print(f"created OpenWebRX+ device entry '{sdrs[match]['name']}' with a default profile",
                  file=sys.stderr)
        pin(kind, sdrs[match], ident)
        sdrs[match]["enabled"] = True
        used.add(match)
    for key, entry in sdrs.items():
        if key not in used and kind_of(entry) and entry.get("enabled", True):
            entry["enabled"] = False
            print(f"disabled OpenWebRX+ device entry '{entry.get('name', key)}'", file=sys.stderr)
    save(path, data)
    print(len(used))


def main(argv):
    if len(argv) >= 3 and argv[1] == "claims":
        claims(argv[2])
    elif len(argv) >= 3 and argv[1] == "reconcile":
        reconcile(argv[2], argv[3:])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
