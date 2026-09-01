"""
ka9q_channels.ollama_tools — Ollama /api/chat tool adapter.

Wraps core.py's read-only functions as Ollama tool-call functions. See
https://github.com/ollama/ollama/blob/main/docs/api.md#chat-request-with-tools :
Ollama's chat API accepts a `tools=[...]` array of OpenAI-style function
specs and, for tool-calling-capable models (llama3.1+, qwen2.5,
mistral-nemo, firefunction-v2, ...), returns `message.tool_calls` naming
a function + JSON arguments for the caller to execute and feed back as a
role="tool" message.

This file owns exactly two things:
  1. TOOLS               — the JSON-schema specs to pass as tools=
  2. dispatch_tool_call() — executes one requested call against core.py

There is no tool here for tuning or creating channels, because core.py
has no such function to wrap — see core.py's module docstring. Adding
one would require deliberately writing new control-path code, not just
registering an existing function.
"""
from __future__ import annotations

import json
from typing import Any, Callable

from . import core

TOOLS: list[dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "list_channels",
            "description": (
                "List every SDR channel currently exposed to you. This is "
                "the complete set — there is no channel outside this list, "
                "and no way to tune into one that isn't."
            ),
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_channel_status",
            "description": "Get live status (active/idle, SNR) for one exposed channel.",
            "parameters": {
                "type": "object",
                "properties": {
                    "channel_id": {
                        "type": "string",
                        "description": "id field from list_channels(), e.g. 'aprs-144390'",
                    }
                },
                "required": ["channel_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_transcript",
            "description": (
                "Get recent speech-to-text transcript segments for one "
                "exposed channel, most recent last."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "channel_id": {
                        "type": "string",
                        "description": "id field from list_channels()",
                    },
                    "since": {
                        "type": "string",
                        "description": "ISO-8601 UTC timestamp; omit for no lower bound",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "max segments to return (default 50)",
                    },
                },
                "required": ["channel_id"],
            },
        },
    },
]

_REGISTRY: dict[str, Callable[..., Any]] = {
    "list_channels": core.list_channels,
    "get_channel_status": core.get_channel_status,
    "get_transcript": core.get_transcript,
}


def dispatch_tool_call(name: str, arguments: dict[str, Any]) -> str:
    """Execute one Ollama tool call by name, return a JSON string result.

    Never raises — errors (unknown tool, unknown channel_id, not-yet-
    implemented status decode) come back as {"error": "..."} so the model
    can react instead of the process crashing on a bad/guessed argument.
    """
    fn = _REGISTRY.get(name)
    if fn is None:
        return json.dumps({"error": f"unknown tool {name!r}"})
    try:
        result = fn(**arguments)
    except Exception as exc:  # noqa: BLE001 - deliberately broad, see docstring
        return json.dumps({"error": str(exc)})
    # Every core.py function returns a dataclass or a list of them.
    return json.dumps(core.to_jsonable(result))
