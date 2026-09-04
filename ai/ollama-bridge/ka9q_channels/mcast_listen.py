#!/usr/bin/env python3
"""
ka9q_channels.mcast_listen — passive multicast client for radiod's status stream.

A simple Python port of the wire-level pieces of ka9q-radio's own
metadump/status.c/multicast.c (see source/ka9q-radio/src/ in this repo),
just enough to join one or more of radiod's status multicast groups and
decode the TLV status packets it broadcasts for every open channel —
SSRC, frequency, mode, description, signal level, etc.

This is *listen-only*: it never opens the control socket and never sends
a packet, so it cannot poll, tune, or otherwise influence radiod (see
ai/ollama-bridge/README.md's read-only design constraint). It is the
piece core.py's get_channel_status() stub is waiting on.

Wire format (from src/status.h, src/status.c, src/dump.c):
  packet   := pkt_type(1 byte: 0=STATUS,1=CMD) tlv* eol(1 byte: 0x00)
  tlv      := type(1 byte) length value(length bytes)
  length   := 0x00-0x7f directly, or (0x80|n) followed by n big-endian
              length bytes, for values >= 128 bytes
  ints     := big-endian, leading zero bytes suppressed (0 encodes as
              length 0); floats/doubles are their raw bit pattern encoded
              the same way

Usage:
    python3 -m ka9q_channels.mcast_listen 239.192.1.20
    python3 -m ka9q_channels.mcast_listen                  # all status_group in channels.yaml
    python3 -m ka9q_channels.mcast_listen -i 192.168.1.10 -t 239.192.1.10 239.192.1.20

A bare, dot-free name (e.g. "sigedge-hackrf") still gets ".local" appended and
resolved via mDNS/Avahi -- but that only works for a radiod instance still on
NETWORKING.md's dynamic default (dns = off). The three reference missions in
channels.yaml use dns = on with a static 239.192.x.x address instead (see
NETWORKING.md's "Current static assignment" table), which resolve_group()
below passes straight through.
"""
from __future__ import annotations

import argparse
import selectors
import socket
import struct
import sys
import time
from dataclasses import dataclass, field
from enum import IntEnum
from pathlib import Path

DEFAULT_STAT_PORT = 5006  # src/rtp.h DEFAULT_STAT_PORT


# --- enum status_type (src/status.h), fields this tool actually decodes ---
class StatusType(IntEnum):
    EOL = 0
    COMMAND_TAG = 1
    DESCRIPTION = 4
    OUTPUT_SSRC = 41
    RADIO_FREQUENCY = 61
    LOW_EDGE = 69
    HIGH_EDGE = 70
    DEMOD_TYPE = 82
    OUTPUT_LEVEL = 108
    PRESET = 128
    LIFETIME = 163


_DEMOD_NAMES = {0: "linear", 1: "FM", 2: "WFM", 3: "spectrum", 4: "spectrum2"}


# --- TLV decode, ported from src/status.c / src/dump.c ---

def decode_int(raw: bytes) -> int:
    """decode_int64(): big-endian, leading-zero-suppressed unsigned int."""
    return int.from_bytes(raw, "big") if raw else 0


def decode_float(raw: bytes) -> float:
    """decode_float(): compressed uint32 bit pattern -> IEEE-754 float."""
    if not raw:
        return 0.0
    return struct.unpack(">f", decode_int(raw).to_bytes(4, "big"))[0]


def decode_double(raw: bytes) -> float:
    if not raw:
        return 0.0
    return struct.unpack(">d", decode_int(raw).to_bytes(8, "big"))[0]


def iter_tlv(buf: bytes):
    """Yield (type_byte, raw_value_bytes) — mirrors dump_metadata()'s loop."""
    i, n = 0, len(buf)
    while i < n:
        t = buf[i]
        i += 1
        if t == StatusType.EOL:
            return
        if i >= n:
            return  # truncated
        optlen = buf[i]
        i += 1
        if optlen & 0x80:
            length_of_length = optlen & 0x7F
            if i + length_of_length > n:
                return
            optlen = int.from_bytes(buf[i : i + length_of_length], "big")
            i += length_of_length
        if i + optlen > n:
            return  # invalid length, stop like the C code does
        yield t, buf[i : i + optlen]
        i += optlen


@dataclass
class ChannelSnapshot:
    ssrc: int
    freq_hz: float | None = None
    mode: str | None = None
    description: str | None = None
    low_edge: float | None = None
    high_edge: float | None = None
    output_level_db: float | None = None
    lifetime: int | None = None
    last_seen: float = field(default_factory=time.time)
    source: str = ""


def decode_status_packet(buf: bytes) -> ChannelSnapshot | None:
    """buf is the packet *after* the leading pkt_type byte, as in dump_metadata()."""
    ssrc = None
    snap_fields: dict = {}
    for t, raw in iter_tlv(buf):
        if t == StatusType.OUTPUT_SSRC:
            ssrc = decode_int(raw)
        elif t == StatusType.RADIO_FREQUENCY:
            snap_fields["freq_hz"] = decode_double(raw)
        elif t == StatusType.LOW_EDGE:
            snap_fields["low_edge"] = decode_float(raw)
        elif t == StatusType.HIGH_EDGE:
            snap_fields["high_edge"] = decode_float(raw)
        elif t == StatusType.DEMOD_TYPE:
            snap_fields["mode"] = _DEMOD_NAMES.get(decode_int(raw), f"?{decode_int(raw)}")
        elif t == StatusType.PRESET:
            snap_fields["mode"] = raw.decode("utf-8", "replace")  # preset name is more specific
        elif t == StatusType.DESCRIPTION:
            snap_fields["description"] = raw.decode("utf-8", "replace")
        elif t == StatusType.OUTPUT_LEVEL:
            snap_fields["output_level_db"] = decode_float(raw)
        elif t == StatusType.LIFETIME:
            snap_fields["lifetime"] = decode_int(raw)
    if ssrc is None:
        return None
    return ChannelSnapshot(ssrc=ssrc, **snap_fields)


# --- multicast join, ported from src/multicast.c resolve_mcast()/listen_mcast()/join_group() ---

def resolve_group(spec: str, default_port: int = DEFAULT_STAT_PORT) -> tuple[str, int, str | None]:
    """Parse 'name[:port][,iface]', append .local if unqualified, resolve via
    the system resolver — same two paths as radiod's own resolve_mcast(): a
    dotted 239.x.x.x address (NETWORKING.md's static override) resolves to
    itself; a bare name falls through to mDNS/Avahi, which only answers for
    an instance still on the dynamic default (dns = off)."""
    host = spec
    iface = None
    if "," in host:
        host, iface = host.rsplit(",", 1)
    port = default_port
    if ":" in host:
        host, port_s = host.rsplit(":", 1)
        port = int(port_s)
    if "." not in host:
        host += ".local"
    addr = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_DGRAM)[0][4][0]
    return addr, port, iface


def join_multicast_socket(group_ip: str, port: int, iface: str | None) -> socket.socket:
    """One socket per group, bound directly to the group address:port —
    same model as listen_mcast()/join_group() in multicast.c. IPv4 only."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"):
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    sock.bind((group_ip, port))

    # IP_ADD_MEMBERSHIP takes a local *interface address*, not an interface
    # name — unlike join_group()'s if_nametoindex(), so -i/,iface here must
    # be given as a dotted address (e.g. -i 192.168.1.10), not "eth0". Falls
    # through to INADDR_ANY (default route) if unset, same as radiod when no
    # ,iface is given.
    local_addr = "0.0.0.0"
    if iface:
        try:
            socket.inet_aton(iface)  # validates it's a dotted address
            local_addr = iface
        except OSError:
            print(f"warning: -i/,iface {iface!r} isn't a dotted IPv4 address, ignoring", file=sys.stderr)
    mreq = socket.inet_aton(group_ip) + socket.inet_aton(local_addr)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    return sock


# --- CLI ---

def _load_groups_from_channels_yaml() -> list[str]:
    import yaml  # optional dependency, only needed for this convenience path

    path = Path(__file__).resolve().parent.parent / "channels.yaml"
    with path.open() as f:
        rows = yaml.safe_load(f)["channels"]
    seen, groups = set(), []
    for row in rows:
        g = row["status_group"]
        if g not in seen:
            seen.add(g)
            groups.append(g)
    return groups


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument(
        "groups",
        nargs="*",
        help="status multicast group name(s) or static address(es), e.g. 239.192.1.20 "
        "(default: every status_group in channels.yaml)",
    )
    ap.add_argument("-i", "--iface", help="local interface address to join on (see NETWORKING.md)")
    ap.add_argument("-t", "--table", action="store_true", help="redraw a live table instead of a scrolling log")
    ap.add_argument("-v", "--verbose", action="store_true", help="print every decoded field, not just the summary")
    args = ap.parse_args(argv)

    groups = args.groups or _load_groups_from_channels_yaml()
    if not groups:
        ap.error("no groups given and none found in channels.yaml")

    sel = selectors.DefaultSelector()
    channels: dict[int, ChannelSnapshot] = {}

    for spec in groups:
        try:
            ip, port, iface = resolve_group(spec)
        except socket.gaierror as exc:
            print(f"warning: can't resolve {spec!r}: {exc}", file=sys.stderr)
            continue
        try:
            sock = join_multicast_socket(ip, port, args.iface or iface)
        except OSError as exc:
            print(f"warning: can't join {spec!r} ({ip}:{port}): {exc}", file=sys.stderr)
            continue
        print(f"listening: {spec} -> {ip}:{port}", file=sys.stderr)
        sel.register(sock, selectors.EVENT_READ, spec)

    if not sel.get_map():
        print("no groups joined, exiting", file=sys.stderr)
        return 1

    def render_table() -> None:
        print("\033[H\033[J", end="")  # clear screen, simple "live" view
        print(f"{'SSRC':>12}  {'FREQ (Hz)':>14}  {'MODE':<10}  {'LEVEL':>7}  DESCRIPTION")
        for snap in sorted(channels.values(), key=lambda s: s.ssrc):
            freq = f"{snap.freq_hz:,.0f}" if snap.freq_hz is not None else "?"
            level = f"{snap.output_level_db:+.1f}" if snap.output_level_db is not None else "?"
            print(
                f"{snap.ssrc:>12}  {freq:>14}  {snap.mode or '?':<10}  {level:>7}  "
                f"{snap.description or ''}"
            )

    try:
        while True:
            for key, _ in sel.select(timeout=1.0):
                sock: socket.socket = key.fileobj  # type: ignore[assignment]
                buf, addr = sock.recvfrom(4096)
                if not buf:
                    continue
                pkt_type, body = buf[0], buf[1:]
                snap = decode_status_packet(body)
                if snap is None:
                    continue
                snap.source = key.data
                channels[snap.ssrc] = snap
                if not args.table:
                    kind = "STAT" if pkt_type == 0 else "CMD"
                    line = (
                        f"{time.strftime('%H:%M:%S')} {key.data} {kind} "
                        f"SSRC={snap.ssrc} freq={snap.freq_hz} mode={snap.mode} "
                        f"level={snap.output_level_db} desc={snap.description!r}"
                    )
                    if args.verbose:
                        line += f" from={addr}"
                    print(line)
            if args.table:
                render_table()
    except KeyboardInterrupt:
        pass
    finally:
        for key in list(sel.get_map().values()):
            key.fileobj.close()  # type: ignore[union-attr]
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
