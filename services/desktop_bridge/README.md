# AgentLink Desktop Bridge

The desktop bridge runs on the computer where the AI agent CLIs and their local
session stores live. It is intentionally separate from the Flutter app.

## Capabilities

- Discovers Claude Code, OpenCode, Codex CLI, and Gemini CLI sessions.
- Returns normalized session lists and transcript details.
- Starts real interactive agent sessions in a PTY and keeps them running while
  the desktop screen is locked.
- Mirrors terminal output to the phone (raw or ANSI-stripped plain mode).
- Accepts terminal input, control keys, resize, rename, stop, and desktop attach.
- Browses the desktop filesystem for choosing a working directory.
- Pairs one phone at a time using a one-time QR secret.
- Registers with a self-hosted relay for internet access.

## Run

```bash
cd services/desktop_bridge
dart pub get

# Same trusted LAN:
dart run bin/agentlink_bridge.dart --host 0.0.0.0

# Over the internet via a relay:
dart run bin/agentlink_bridge.dart --relay wss://relay.example.com:8787
```

The first start without a paired phone prints a QR code. The generated
pairing secret and device token hash are stored in `~/.agentlink/bridge.json`.

## Agent launch commands

The bridge invokes the installed CLI directly, without storing provider API
keys or shell-wrapping the prompt:

- Claude Code: `claude [--resume <id>] [prompt]`
- OpenCode: `opencode [--session <id>] [--prompt <prompt>]`
- Codex CLI: `codex [resume <id>] [prompt]`
- Gemini CLI: `gemini [-i <prompt>]`

The CLIs must already be installed and authenticated on the PC. Gemini support
is best-effort for history parsing.

## Desktop terminal attach

For a session started with `openOnDesktop: true`, the bridge opens a terminal
emulator running:

```bash
agentlink-bridge attach <session-id> --endpoint http://127.0.0.1:<port>
```

Press `Ctrl+]` in that terminal to detach without stopping the agent.

## One phone per PC

The bridge stores only the SHA-256 hash of the device token. A second pairing
attempt returns `409 Conflict`. Run `agentlink-bridge reset` to unpair, then
start the bridge again to show a new QR code.
