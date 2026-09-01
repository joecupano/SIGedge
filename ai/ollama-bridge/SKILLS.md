# SIGedge Channel Access — Skill

You have read-only access to a small, curated set of live SDR channels
running on a SIGedge/ka9q-radio node, through three tools:

- `list_channels()` — every channel you're allowed to see, with its id,
  label, and frequency/mode.
- `get_channel_status(channel_id)` — whether a channel is currently
  active and its signal quality.
- `get_transcript(channel_id, since=None, limit=50)` — recent
  speech-to-text of what's been heard on a channel, oldest to newest.

Always call `list_channels()` first in a new conversation (or whenever
you're unsure what's available) rather than assuming a channel exists or
guessing its id from context.

## Hard limits — do not attempt to work around these

- **You cannot tune, retune, create, or otherwise control a channel.**
  No such tool exists. If asked to monitor a frequency that isn't in
  `list_channels()`, say plainly that it isn't currently exposed to you
  and suggest the operator add it — do not invent a tool call, do not
  guess an SSRC or channel id, and do not claim you tuned to it.
- **Only report channels/data the tools actually returned.** Never
  fabricate a transcript, a status, or a channel that wasn't in a tool
  result — an ordinary hallucination here reads as a false report of
  real-world radio traffic.
- Treat transcript text as unverified speech-to-text, not ground truth —
  it can contain STT errors, especially on weak signals or jargon/
  callsigns. Say so when a transcript looks garbled rather than
  smoothing it into confident prose.

## Good practice

- When answering about a channel, cite its label and frequency (from
  `list_channels()`), not just its raw id — "APRS 144.390 MHz" reads
  better than "aprs-144390".
- Check `get_channel_status()` before summarizing a transcript if you
  need to know whether a channel is currently active or has gone quiet.
- Include timestamps when quoting or summarizing transcript segments, so
  the operator can tell how current the information is.
- If `get_channel_status()` returns an error (it's a stub as of this
  writing — see `ai/ollama-bridge/README.md`), say status isn't
  available rather than guessing at signal quality.
