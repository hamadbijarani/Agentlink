# AgentLink

AgentLink is a remote terminal for AI coding-agent sessions. An Android app pairs
with a desktop PC over the internet (or a LAN) and starts, mirrors, controls, and
closes real CLI sessions on that PC: Claude Code, OpenCode, Codex CLI, and Gemini
CLI.

Agent credentials, project files, and session history never leave the PC. The
phone holds a device token; the PC enforces one paired phone at a time.

## Repository layout

```text
apps/
  mobile/                   Flutter Android app only
services/
  desktop_bridge/           PC bridge: PTY sessions, pairing, relay client
  relay/                    Self-hosted WebSocket relay
research.md
implementation_plan.md
resources.md
```

The mobile app and the PC bridge are separate programs connected by a small,
versioned HTTP API. They may be built and deployed independently.

## Architecture

```text
Android app
   |  HTTPS/WSS + device token
   v
Relay (self-hosted, optional TLS)
   |  WebSocket bridge registration
   v
Desktop bridge on the PC
   |  real PTY via posix_spawn
   v
claude / opencode / codex / gemini
```

- **Pairing** is a one-time QR code. The QR carries a short-lived pairing
  secret; the bridge exchanges it for a device token and stores only its SHA-256
  hash. A second phone receives `409 Conflict` until the PC runs
  `agentlink-bridge reset`.
- **Transport** prefers the relay, falls back to direct LAN endpoints, and
  reconnects automatically. Sessions run in a real PTY owned by the bridge, so
  they keep running while the desktop screen is locked.
- **Desktop visibility** is optional: the bridge opens a terminal emulator
  running `agentlink-bridge attach <sessionId>` against the local HTTP API.
  Closing that terminal detaches; it does not stop the agent.
- **Provider themes** are served by the bridge and applied dynamically in the app.

## Quick start

### 1. Run the relay (on a server or home machine)

```bash
cd services/relay
dart pub get
dart run bin/agentlink_relay.dart --port 8787 --token 'a-long-relay-token'
# Use --cert/--key or a TLS reverse proxy before exposing it to the internet.
```

### 2. Start the desktop bridge (on the PC)

```bash
cd services/desktop_bridge
dart pub get
dart run bin/agentlink_bridge.dart \
  --relay wss://relay.example.com:8787 \
  --relay-token 'a-long-relay-token'
```

The first start prints a QR code (or a pairing link with `--no-qr`). Scan it
with the Android app. The bridge remembers the pairing in
`~/.agentlink/bridge.json`.

### 3. Build and run the Android app

```bash
cd apps/mobile
flutter pub get
flutter run
```

Scan the QR code from the bridge. The app then shows live sessions, history,
and settings. Use **New session** to pick a provider and a folder on the PC.

## Desktop bridge CLI

```text
agentlink-bridge serve [options]   Start the bridge and, if needed, a pairing QR
agentlink-bridge pair [options]    Same as serve
agentlink-bridge status            Show pairing and relay configuration
agentlink-bridge reset             Forget the paired phone and open pairing
agentlink-bridge config [options]  Update relay/HTTP/desktop settings
agentlink-bridge attach [id]       Attach a desktop terminal to a live session
```

Important options: `--relay`, `--relay-token`, `--no-relay`, `--host`,
`--port`, `--lan`, `--local`, `--no-http`, `--no-desktop`, `--no-qr`.

## Security notes

- The relay only forwards authenticated requests; it does not see agent
  credentials or session files.
- The phone stores its device token in Android Keystore.
- The PC accepts only one paired phone at a time. To change phones, run
  `agentlink-bridge reset` on the PC.
- Prompts are passed as direct process arguments, not through a shell.
- Transcript refs are restricted to provider session roots, including resolved
  symbolic links.
- Use `wss://` for the relay whenever it is reachable from the internet.

## Development

```bash
# Desktop bridge
cd services/desktop_bridge
dart analyze
dart test

# Relay
cd services/relay
dart analyze
dart test

# Mobile
cd apps/mobile
flutter analyze
flutter test
flutter build apk --debug
```

A release build of the Android app is produced with
`flutter build apk --release`.

## Documents

- `research.md` — research and technology choices
- `implementation_plan.md` — architecture and phased roadmap
- `resources.md` — dependencies and references
- `services/desktop_bridge/API.md` — HTTP API reference
- `services/desktop_bridge/README.md` — bridge-specific notes
- `services/relay/README.md` — relay-specific notes
