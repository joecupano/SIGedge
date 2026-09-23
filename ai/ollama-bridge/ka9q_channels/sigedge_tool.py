"""
ka9q_channels.sigedge_tool — the one Ollama tool for SIGedge channel access.

Replaces the old core.py/ollama_tools.py split (that split existed to keep
the read-only functions portable to an MCP server later; MCP is out of
scope for now, so one file/one function is simpler). Still read-only by
construction: there is no action here that tunes, retunes, or creates a
channel, and no code that opens radiod's control multicast socket.

Config handling: this process has no channels.yaml of its own to read.
The operator's channels.yaml is supplied by the model, in chat, via the
`channels_yaml` argument — pasted/uploaded once per session (see
SKILLS.md) and cached in-process (_CACHED_CONFIG) so later calls in the
same run can omit it. Restarting this process forgets it; that's
intentional, not a bug to fix.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import yaml

BRIDGE_DIR = Path(__file__).resolve().parent.parent
TRANSCRIPT_LOG = BRIDGE_DIR / "transcripts.jsonl"  # written by a not-yet-built STT worker

_CACHED_CONFIG: dict | None = None


TOOL: dict[str, Any] = {
    "type": "function",
    "function": {
        "name": "sigedge_channels",
        "description": (
            "Query SIGedge/ka9q-radio SDR channels: list the channels you're "
            "allowed to see, check one channel's live status, or fetch its "
            "recent speech-to-text transcript. This process starts with no "
            "channel list loaded. On the first call in a session, try "
            "action='list_channels' with no channels_yaml — if that errors "
            "saying no config is loaded, ask the operator to paste the "
            "contents of their channels.yaml file, then call again passing "
            "that text as channels_yaml. Once supplied, it's cached for the "
            "rest of this session — omit channels_yaml on later calls."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "enum": ["list_channels", "channel_status", "transcript"],
                    "description": "Which read-only query to run.",
                },
                "channels_yaml": {
                    "type": "string",
                    "description": (
                        "Full text content of the operator's channels.yaml. "
                        "Required on the first call of a session (or after a "
                        "restart); omit once it has been supplied and cached."
                    ),
                },
                "channel_id": {
                    "type": "string",
                    "description": (
                        "id field from a list_channels() result. Required for "
                        "channel_status and transcript."
                    ),
                },
                "since": {
                    "type": "string",
                    "description": (
                        "ISO-8601 UTC timestamp; for transcript only, omit for "
                        "no lower bound."
                    ),
                },
                "limit": {
                    "type": "integer",
                    "description": "For transcript only, max segments to return (default 50).",
                },
            },
            "required": ["action"],
        },
    },
}


class UnknownChannelError(KeyError):
    """Raised when a channel_id isn't in the loaded channels.yaml — never guess an SSRC."""


class NoConfigLoadedError(RuntimeError):
    """Raised when no channels_yaml has been supplied yet this session."""


def _channel_row(channel_id: str) -> dict:
    if _CACHED_CONFIG is None:
        raise NoConfigLoadedError(
            "no channels.yaml loaded yet — ask the operator to paste its "
            "contents and pass it as channels_yaml"
        )
    for row in _CACHED_CONFIG["channels"]:
        if row["id"] == channel_id:
            return row
    raise UnknownChannelError(
        f"{channel_id!r} is not in the loaded channels.yaml — it cannot be "
        "tuned into existence, only added there by an operator."
    )


def _list_channels() -> list[dict]:
    if _CACHED_CONFIG is None:
        raise NoConfigLoadedError(
            "no channels.yaml loaded yet — ask the operator to paste its "
            "contents and pass it as channels_yaml"
        )
    return [
        {
            "id": row["id"],
            "label": row["label"],
            "instance": row["instance"],
            "freq_hz": row["freq_hz"],
            "mode": row["mode"],
        }
        for row in _CACHED_CONFIG["channels"]
    ]


def _channel_status(channel_id: str) -> dict:
    """STUB: real implementation joins the channel's status_group multicast
    and decodes radiod's TLV status stream. Deliberately raising rather
    than returning fabricated numbers."""
    _channel_row(channel_id)  # validates id
    raise NotImplementedError(
        "channel_status: radiod status-multicast decode not yet wired up"
    )


def _transcript(channel_id: str, since: str | None, limit: int) -> list[dict]:
    _channel_row(channel_id)  # validates id

    if not TRANSCRIPT_LOG.exists():
        return []

    segments: list[dict] = []
    with TRANSCRIPT_LOG.open() as f:
        for line in f:
            row = json.loads(line)
            if row["channel_id"] != channel_id:
                continue
            if since is not None and row["ts"] < since:
                continue
            segments.append(row)

    return segments[-limit:]


def sigedge_channels(
    action: str,
    channels_yaml: str | None = None,
    channel_id: str | None = None,
    since: str | None = None,
    limit: int = 50,
) -> dict:
    """The one function Ollama calls. Never raises — errors come back as
    {"error": "..."} so the model can react (e.g. ask the operator to paste
    channels.yaml) instead of the process crashing on a bad/guessed argument.
    """
    global _CACHED_CONFIG
    try:
        if channels_yaml is not None:
            _CACHED_CONFIG = yaml.safe_load(channels_yaml)

        if action == "list_channels":
            return {"channels": _list_channels()}
        elif action == "channel_status":
            if channel_id is None:
                raise ValueError("channel_status requires channel_id")
            return _channel_status(channel_id)
        elif action == "transcript":
            if channel_id is None:
                raise ValueError("transcript requires channel_id")
            return {"segments": _transcript(channel_id, since, limit)}
        else:
            raise ValueError(f"unknown action {action!r}")
    except Exception as exc:  # noqa: BLE001 - deliberately broad, see docstring
        return {"error": str(exc)}
