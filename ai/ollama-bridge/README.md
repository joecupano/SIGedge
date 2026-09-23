# ollama-bridge

Sketch of a read-only bridge between SIGedge's `radiod` multicast channels
and an Ollama server's tool-calling API. Grew out of comparing
[ka9q-web1](https://github.com/wa2n-code/ka9q-web1)'s architecture (a thin
SSRC-keyed relay between radiod's multicast RTP and per-browser WebSocket
sessions — see `multicast.c`/`status.c`/`ka9q-web.c` there) to what an LLM
needs instead: text, not RTP.

## Design constraints (per current scope)

1. **Ollama gets one Python function tool**, not raw sockets —
   `sigedge_tool.py`'s `sigedge_channels()`, dispatching on an `action`
   argument (`list_channels` / `channel_status` / `transcript`) instead of
   three separate tools. MCP is explicitly **out of scope for now** — no
   FastMCP wrapper, no attempt to keep this file provider-agnostic beyond
   what one file naturally is. If MCP comes back into scope later, this
   file gets split again then, not preemptively.
2. **A SKILLS.md ships alongside** so a chat session using this tool (via
   Ollama's native tool-calling or a human pasting the doc into a system
   prompt) knows what it can ask for and what it can't.
3. **Read-only, config-curated exposure.** Ollama can only ever see the
   channels an operator has pasted in via `channels.yaml`'s contents —
   there is no "enumerate every SSRC radiod currently has open" action,
   and no `tune_channel`/`set_frequency` action exists anywhere in this
   package. That's enforced *by omission*: `sigedge_tool.py` has no
   control-path code, so it can't expose one by accident.
4. **No config file on the host.** `sigedge_tool.py` never reads
   `channels.yaml` off disk itself. The model asks the operator to paste
   its contents into the chat on first use (see SKILLS.md) and passes
   that text in as the `channels_yaml` argument, which gets cached
   in-process for the rest of the session. This makes the tool-serving
   side itself stateless and config-free — the channel list lives in the
   conversation, not in a file the process trusts implicitly.

## Layout

```
ai/ollama-bridge/
├── channels.yaml              # template/example — operator edits their own copy and pastes its contents into chat
├── ka9q_channels/
│   ├── sigedge_tool.py        # the one Ollama tool: TOOL spec + sigedge_channels()
│   └── mcast_listen.py        # standalone: joins radiod's status multicast, decodes TLV live
├── run_agent_example.py       # minimal Ollama chat + tool-call loop, for testing
└── SKILLS.md                  # chat-facing doc: what the model can/can't do here
```

## What's real vs. stubbed in this pass

- `list_channels` action — real, once `channels_yaml` has been supplied
  (see above). Returns the curated list from whatever text the operator
  pasted in.
- `transcript` action — real against a local JSONL transcript log
  (`transcripts.jsonl`, still read straight off this host — that's log
  data, not the config-injection this bridge changed), but **nothing
  populates that log yet**. The STT stage (radiod audio multicast → PCM →
  whisper.cpp → timestamped text, keyed by SSRC, using the same per-SSRC
  demux `ka9q-web.c`'s `audio_thread()` already does) is separate
  follow-up work, not part of this sketch.
- `channel_status` action — still a stub in `sigedge_tool.py`, but the
  piece it was waiting on now exists standalone: `mcast_listen.py` joins
  radiod's status multicast group(s) and decodes the live TLV stream
  (ported from `status.c`'s `decode_*`/`dump_metadata()` and
  `multicast.c`'s `resolve_mcast()`/`listen_mcast()`/`join_group()` — see
  its own docstring), printing a rolling log or `-t` live table of
  SSRC/freq/mode/level/description per channel. It's read-only, same as
  everything else here — it never opens radiod's control socket. Not yet
  wired into `channel_status`: that needs a background listener + cache
  (`sigedge_channels()` is meant to be a fast, synchronous call, not one
  that blocks joining a socket), which is the next step, not this one.

  ```bash
  python3 -m ka9q_channels.mcast_listen                    # every status_group in your channels.yaml
  python3 -m ka9q_channels.mcast_listen -t 239.192.1.20    # live table, one group
  ```

## Try it

```bash
cd ai/ollama-bridge
pip install --user --break-system-packages ollama pyyaml   # or a venv
python3 run_agent_example.py "What's on the aprs channel right now?"
```

`run_agent_example.py` is scripted to notice when the model asks for
`channels.yaml` and prompt you on stdin to paste it — same thing a real
chat UI's file-upload would feed back in as a tool result.

Requires an Ollama server reachable at `OLLAMA_HOST` (default
`http://localhost:11434`) running a tool-calling-capable model (e.g.
`llama3.1`, `qwen2.5`).
