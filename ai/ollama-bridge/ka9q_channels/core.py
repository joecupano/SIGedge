"""
ka9q_channels.core — read-only channel presentation layer.

This module is the single source of truth for "what a language model is
allowed to see" from a SIGedge/ka9q-radio node. It deliberately contains
no tuning/control path: there is no `tune_channel`, no `set_frequency`,
no function that opens radiod's control multicast socket for writing.
Any adapter built on top of this module (ollama_tools.py today, an MCP
server later) can only ever expose read access, because there is nothing
else here to wrap.

Architecture note (see the ka9q-web1 comparison this package grew out
of): ka9q-web1 relays radiod's status/control/audio multicast streams
straight into per-browser WebSocket sessions and decodes nothing itself
(multicast.c's listen_mcast()/join_group(), status.c's TLV decode_*(),
ka9q-web.c's control_set_frequency() and audio_thread()). This module
takes the same status-decode approach for *read* data only, and adds a
transcript layer that ka9q-web1 has no analog for, since an LLM consumes
text, not RTP audio.

Every public function is stateless w.r.t. the caller (channel_id in,
plain data out) and fully typed — that's what makes each one a one-line
MCP tool later:

    @mcp.tool()
    def list_channels() -> list[ChannelInfo]: ...
"""
from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path

import yaml

BRIDGE_DIR = Path(__file__).resolve().parent.parent
CHANNELS_CONFIG = BRIDGE_DIR / "channels.yaml"
TRANSCRIPT_LOG = BRIDGE_DIR / "transcripts.jsonl"  # written by a not-yet-built STT worker


@dataclass(frozen=True)
class ChannelInfo:
    id: str
    label: str
    instance: str
    freq_hz: int
    mode: str


@dataclass(frozen=True)
class ChannelStatus:
    id: str
    active: bool
    snr_db: float | None
    note: str


@dataclass(frozen=True)
class TranscriptSegment:
    channel_id: str
    ts: str          # ISO-8601 UTC
    text: str


class UnknownChannelError(KeyError):
    """Raised when a channel_id isn't in channels.yaml — never guess an SSRC."""


def _load_config() -> dict:
    with CHANNELS_CONFIG.open() as f:
        return yaml.safe_load(f)


def _channel_row(channel_id: str) -> dict:
    for row in _load_config()["channels"]:
        if row["id"] == channel_id:
            return row
    raise UnknownChannelError(
        f"{channel_id!r} is not in channels.yaml — it cannot be tuned into "
        "existence, only added there by an operator."
    )


def list_channels() -> list[ChannelInfo]:
    """Return every channel currently exposed to this bridge.

    This is the *entire* discovery surface: reflects channels.yaml
    exactly, nothing radiod-side is enumerated live.
    """
    return [
        ChannelInfo(
            id=row["id"],
            label=row["label"],
            instance=row["instance"],
            freq_hz=row["freq_hz"],
            mode=row["mode"],
        )
        for row in _load_config()["channels"]
    ]


def get_channel_status(channel_id: str) -> ChannelStatus:
    """Return live status (SNR, active/idle) for one exposed channel.

    STUB: real implementation joins the channel's status_group multicast
    (channels.yaml) and decodes radiod's TLV status stream — porting
    status.c's decode_int64()/decode_float() and multicast.c's
    listen_mcast()/join_group() from ka9q-web1, or shelling out to
    ka9q-radio's own `control`/`monitor`. Deliberately raising rather
    than returning fabricated numbers.
    """
    _channel_row(channel_id)  # validates id, raises UnknownChannelError if absent
    raise NotImplementedError(
        "get_channel_status: radiod status-multicast decode not yet wired up"
    )


def get_transcript(
    channel_id: str, since: str | None = None, limit: int = 50
) -> list[TranscriptSegment]:
    """Return recent speech-to-text segments for one exposed channel.

    Reads transcripts.jsonl, one {"channel_id","ts","text"} object per
    line. Real today, but nothing populates that file yet — that's a
    separate STT worker (radiod audio multicast -> PCM -> whisper.cpp,
    keyed by the per-SSRC demux ka9q-web.c's audio_thread() already
    does) to be built as follow-up work, not part of this sketch.
    """
    _channel_row(channel_id)  # validates id, raises UnknownChannelError if absent

    if not TRANSCRIPT_LOG.exists():
        return []

    segments: list[TranscriptSegment] = []
    with TRANSCRIPT_LOG.open() as f:
        for line in f:
            row = json.loads(line)
            if row["channel_id"] != channel_id:
                continue
            if since is not None and row["ts"] < since:
                continue
            segments.append(TranscriptSegment(**row))

    return segments[-limit:]


def to_jsonable(obj) -> dict | list:
    """Dataclass (or list of them) -> plain dict/list, for JSON responses."""
    if isinstance(obj, list):
        return [asdict(o) for o in obj]
    return asdict(obj)
