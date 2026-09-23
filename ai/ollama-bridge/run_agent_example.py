#!/usr/bin/env python3
"""
run_agent_example.py — minimal Ollama chat + tool-call loop.

For testing ka9q_channels.sigedge_tool against a real Ollama server.
Not part of the bridge itself; a real integration would run its own
long-lived session/monitoring loop instead of a one-shot CLI.

Usage:
    python3 run_agent_example.py "What's on the aprs channel right now?"

The model has no channel list on the first call. Per SKILLS.md, it should
ask you to paste your channels.yaml contents; this script watches stdin
for that and feeds it back in as a tool result, same as a real chat UI
would when a user pastes/uploads a file mid-conversation.

Env:
    OLLAMA_HOST   default http://localhost:11434
    OLLAMA_MODEL  default llama3.1 (must support tool calling)
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import ollama

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ka9q_channels.sigedge_tool import TOOL, sigedge_channels  # noqa: E402

MODEL = os.environ.get("OLLAMA_MODEL", "llama3.1")
SKILLS_TEXT = (Path(__file__).resolve().parent / "SKILLS.md").read_text()


def main() -> None:
    question = " ".join(sys.argv[1:]) or "What channels can you see?"
    client = ollama.Client(host=os.environ.get("OLLAMA_HOST", "http://localhost:11434"))

    messages = [
        {"role": "system", "content": SKILLS_TEXT},
        {"role": "user", "content": question},
    ]

    while True:
        response = client.chat(model=MODEL, messages=messages, tools=[TOOL])
        messages.append(response["message"])

        calls = response["message"].get("tool_calls")
        if not calls:
            print(response["message"]["content"])
            return

        for call in calls:
            args = call["function"]["arguments"]
            result = sigedge_channels(**args)
            if "no channels.yaml loaded yet" in result.get("error", ""):
                pasted = input(
                    "\n[model needs channels.yaml — paste its contents, then press enter]\n"
                )
                args["channels_yaml"] = pasted
                result = sigedge_channels(**args)
            messages.append(
                {"role": "tool", "content": json.dumps(result), "name": call["function"]["name"]}
            )


if __name__ == "__main__":
    main()
