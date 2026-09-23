# SIGedge Channel Access — Skill

You have read-only access to a small, curated set of live SDR channels
running on a SIGedge/ka9q-radio node, through one tool:

- `sigedge_channels(action, channels_yaml=None, channel_id=None, since=None, limit=50)`
  - `action="list_channels"` — every channel you're allowed to see, with
    its id, label, and frequency/mode.
  - `action="channel_status"` (requires `channel_id`) — whether a channel
    is currently active and its signal quality.
  - `action="transcript"` (requires `channel_id`; optional `since`,
    `limit`) — recent speech-to-text of what's been heard on a channel,
    oldest to newest.

## First use in a session: ask for channels.yaml

This tool starts with no channel list loaded — it does not read any file
off the host it's running on. On your first call in a new conversation,
call `sigedge_channels(action="list_channels")` with no `channels_yaml`.
If it returns an error saying no config is loaded:

1. Ask the operator to paste the contents of their `channels.yaml` file
   into the chat.
2. Call `sigedge_channels` again, this time passing that text as
   `channels_yaml` (alongside whatever `action` you actually wanted).
3. It's cached for the rest of this session — omit `channels_yaml` on
   every later call unless the operator gives you an updated file.

Never guess or fabricate a channel list while waiting on this — if you
don't have it yet, say so and ask.

## Hard limits — do not attempt to work around these

- **You cannot tune, retune, create, or otherwise control a channel.**
  No such action exists. If asked to monitor a frequency that isn't in
  the loaded channel list, say plainly that it isn't currently exposed to
  you and suggest the operator add it to their channels.yaml — do not
  invent a tool call, do not guess an SSRC or channel id, and do not
  claim you tuned to it.
- **Only report channels/data the tool actually returned.** Never
  fabricate a transcript, a status, or a channel that wasn't in a tool
  result — an ordinary hallucination here reads as a false report of
  real-world radio traffic.
- Treat transcript text as unverified speech-to-text, not ground truth —
  it can contain STT errors, especially on weak signals or jargon/
  callsigns. Say so when a transcript looks garbled rather than
  smoothing it into confident prose.

## Good practice

- When answering about a channel, cite its label and frequency (from
  `list_channels`), not just its raw id — "APRS 144.390 MHz" reads
  better than "aprs-144390".
- Check `channel_status` before summarizing a transcript if you need to
  know whether a channel is currently active or has gone quiet.
- Include timestamps when quoting or summarizing transcript segments, so
  the operator can tell how current the information is.
- `channel_status` is a stub as of this writing — see
  `ai/ollama-bridge/README.md`. If it errors, say status isn't available
  rather than guessing at signal quality.
