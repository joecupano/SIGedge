# ollama-bridge

Sketch of a read-only bridge between SIGedge's `radiod` multicast channels
and an Ollama server's tool-calling API. Grew out of comparing
[ka9q-web1](https://github.com/wa2n-code/ka9q-web1)'s architecture (a thin
SSRC-keyed relay between radiod's multicast RTP and per-browser WebSocket
sessions — see `multicast.c`/`status.c`/`ka9q-web.c` there) to what an LLM
needs instead: text, not RTP.

## Design constraints (per current scope)

1. **Ollama gets Python function tools**, not raw sockets — `ollama_tools.py`.
2. **A SKILLS.md ships alongside** so a chat session using these tools (via
   Ollama's native tool-calling or a human pasting the doc into a system
   prompt) knows what it can ask for and what it can't.
3. **Read-only, config-curated exposure.** Ollama can only ever see the
   channels an operator has listed in `channels.yaml` — there is no
   "enumerate every SSRC radiod currently has open" tool, and no
   `tune_channel`/`set_frequency` function exists anywhere in this package.
   That's enforced *by omission*: `core.py` has no control-path code to
   wrap, so no adapter built on top of it can expose one by accident.
4. **Portable to MCP later.** `core.py` is plain, fully-typed, stateless
   functions with docstrings and no Ollama-specific code in it —
   `ollama_tools.py` is a thin adapter translating those functions into
   Ollama's `tools=[...]` JSON-schema format. An MCP server wrapping the
   same functions later is expected to look like:

   ```python
   from ka9q_channels import core
   from mcp.server.fastmcp import FastMCP

   mcp = FastMCP("ka9q-channels")
   mcp.tool()(core.list_channels)
   mcp.tool()(core.get_channel_status)
   mcp.tool()(core.get_transcript)
   ```

   i.e. zero changes to `core.py` when that day comes.

## Layout

```
ai/ollama-bridge/
├── channels.yaml              # operator-curated allowlist — "what Ollama can see"
├── ka9q_channels/
│   ├── core.py                # provider-agnostic read-only functions (the reusable part)
│   ├── ollama_tools.py        # Ollama tool-schema adapter over core.py
│   └── mcast_listen.py        # standalone: joins radiod's status multicast, decodes TLV live
├── run_agent_example.py       # minimal Ollama chat + tool-call loop, for testing
└── SKILLS.md                  # chat-facing doc: what the model can/can't do here
```

## What's real vs. stubbed in this pass

- `list_channels()` — real. Reads `channels.yaml`, returns the curated list.
- `get_transcript()` — real against a local JSONL transcript log, but
  **nothing populates that log yet**. The STT stage (radiod audio
  multicast → PCM → whisper.cpp → timestamped text, keyed by SSRC, using
  the same per-SSRC demux `ka9q-web.c`'s `audio_thread()` already does) is
  separate follow-up work, not part of this sketch.
- `get_channel_status()` — still a stub in `core.py`, but the piece it was
  waiting on now exists standalone: `mcast_listen.py` joins radiod's
  status multicast group(s) and decodes the live TLV stream (ported from
  `status.c`'s `decode_*`/`dump_metadata()` and `multicast.c`'s
  `resolve_mcast()`/`listen_mcast()`/`join_group()` — see its own
  docstring), printing a rolling log or `-t` live table of SSRC/freq/
  mode/level/description per channel. It's read-only, same as everything
  else here — it never opens radiod's control socket. Not yet wired into
  `get_channel_status()`: that needs a background listener + cache
  (`core.py` functions are meant to be fast, synchronous calls, not ones
  that block joining a socket), which is the next step, not this one.

  ```bash
  python3 -m ka9q_channels.mcast_listen                    # every status_group in channels.yaml
  python3 -m ka9q_channels.mcast_listen -t 239.192.1.20    # live table, one group
  ```

## Try it

```bash
cd ai/ollama-bridge
pip install --user --break-system-packages ollama pyyaml   # or a venv
python3 run_agent_example.py "What's on the aprs channel right now?"
```

Requires an Ollama server reachable at `OLLAMA_HOST` (default
`http://localhost:11434`) running a tool-calling-capable model (e.g.
`llama3.1`, `qwen2.5`).
