#!/usr/bin/env python3
"""
run_agent_example.py — minimal Ollama chat + tool-call loop.

For testing ka9q_channels.ollama_tools against a real Ollama server.
Not part of the bridge itself; a real integration would run its own
long-lived session/monitoring loop instead of a one-shot CLI.

Usage:
    python3 run_agent_example.py "What's on the aprs channel right now?"

Env:
    OLLAMA_HOST   default http://localhost:11434
    OLLAMA_MODEL  default llama3.1 (must support tool calling)
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import ollama

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ka9q_channels.ollama_tools import TOOLS, dispatch_tool_call  # noqa: E402

MODEL = os.environ.get("OLLAMA_MODEL", "llama3.1")
SKILLS_TEXT = (Path(__file__).resolve().parent / "SKILLS.md").read_text()


def main() -> None:
    question = " ".join(sys.argv[1:]) or "What channels can you see?"
    client = ollama.Client(host=os.environ.get("OLLAMA_HOST", "http://localhost:11434"))

    messages = [
        {"role": "system", "content": SKILLS_TEXT},
        {"role": "user", "content": question},
    ]

    response = client.chat(model=MODEL, messages=messages, tools=TOOLS)
    messages.append(response["message"])

    for call in response["message"].get("tool_calls", []):
        name = call["function"]["name"]
        args = call["function"]["arguments"]
        result = dispatch_tool_call(name, args)
        messages.append({"role": "tool", "content": result, "name": name})

    if response["message"].get("tool_calls"):
        response = client.chat(model=MODEL, messages=messages, tools=TOOLS)

    print(response["message"]["content"])


if __name__ == "__main__":
    main()
