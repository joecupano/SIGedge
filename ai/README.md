# ai

Bridges/adapters that expose SIGedge's `radiod` multicast channels to AI
consumers — the "APIs / MCP" / "analytics and AI workflows" branch of the
architecture diagram in the top-level [README.md](../README.md).

**ollama-bridge** — read-only channel status/transcript tools for an
Ollama server's tool-calling API, written so the same core module can be
re-wrapped as an MCP server later. See
[ollama-bridge/README.md](ollama-bridge/README.md).

Nothing here is wired into `SIGedge setup`/`scripts/` dispatch yet — run
and configure it directly, same pattern as `scripts/cfg_ka9q-radio_tui`.

## Deployment

### Today (sketch stage)

`ollama-bridge` currently touches no network beyond outbound calls to
Ollama's REST API — `get_channel_status()` and the transcript writer are
both stubs (see [ollama-bridge/README.md](ollama-bridge/README.md#whats-real-vs-stubbed-in-this-pass)),
so at this stage it only reads local files (`channels.yaml`,
`transcripts.jsonl`). That means:

- It can run **anywhere** — same host as `radiod`, a different SIGedge
  node, or a laptop — as long as it can reach whichever Ollama server
  `OLLAMA_HOST` points at (default `http://localhost:11434`; point it at
  a LAN host with a GPU if this node doesn't have one).
- No systemd unit yet. Run it directly as a plain process, same as
  `scripts/cfg_ka9q-radio_tui` — it isn't a long-running daemon in this
  sketch, `run_agent_example.py` is a one-shot CLI for testing.
- Use a venv for anything beyond ad-hoc testing, same guidance as
  `scripts/README.md`'s `textual` note: `sudo apt-get install -y
  python3-venv && python3 -m venv .venv && .venv/bin/pip install ollama
  pyyaml` (plain `python3 -m venv` fails on Debian/Ubuntu until
  `python3-venv` is installed).

### Once the stubs are filled in (status decode + STT worker)

Filling in `get_channel_status()` and the STT worker that populates
`transcripts.jsonl` changes the deployment picture, since both need to
join radiod's live multicast groups:

- Must then run on a host that can reach the `status_group`/`data_group`
  multicast addresses named per-channel in `channels.yaml` — either the
  SIGedge node itself, or another host on the same L2 segment /
  multicast-routed network.
- On any multi-homed host, bind explicitly to the interface facing the
  SDR's multicast segment rather than relying on the default route —
  same requirement `cfg_ka9q-radio`'s `KA9Q_IFACE` exists for; see
  [NETWORKING.md](../NETWORKING.md).
- The STT worker is the CPU-heavier piece (whisper.cpp per active
  channel) — plan for it as a separate process/host from the lightweight
  tool-serving side, not necessarily co-located.
- At that point this should become a real systemd service, but — per
  the top-level README's install/activation split and the caution
  around `soapyremote-server` — it should be **installed but left
  disabled by default**, an explicit operator opt-in, not auto-enabled.
  It's a new pathway for RF traffic to leave the node (into an LLM,
  local or not); treat enabling it with the same deliberateness as
  enabling a `radiod@<instance>` mission or SoapyRemote.
