# AgentLink Bridge API v1

All authenticated requests require `Authorization: Bearer <device-token>`.
Responses are JSON with `Cache-Control: no-store`. Request bodies are limited to
1 MiB.

The bridge may be reached directly over HTTP on a trusted LAN, or through the
self-hosted relay. Over the relay, the same paths are forwarded inside
WebSocket frames.

## Public (unauthenticated)

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/v1/health` | Reachability and pairing state |
| `POST` | `/v1/pair/claim` | Exchange a one-time pairing secret for a device token |

Pairing body:

```json
{
  "secret": "<from the QR code>",
  "deviceName": "Pixel 9",
  "platform": "android"
}
```

Response: `deviceToken`, `device`, `bridge`, `providers`.

## Authenticated

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/v1/info` | Bridge, relay, desktop, and provider information |
| `GET` | `/v1/providers` | Installed providers and their themes |
| `GET` | `/v1/sessions?limit=200` | Historical sessions across providers |
| `GET` | `/v1/session?provider=...&ref=...` | Transcript details |
| `GET` | `/v1/live-sessions` | Live PTY sessions |
| `POST` | `/v1/live-sessions` | Start a live session |
| `GET` | `/v1/live-sessions/<id>` | One live session |
| `DELETE` | `/v1/live-sessions/<id>` | Stop a live session |
| `PATCH` | `/v1/live-sessions/<id>` | Rename a live session |
| `GET` | `/v1/live-sessions/<id>/terminal` | Mirrored terminal output |
| `POST` | `/v1/live-sessions/<id>/input` | Send text or base64 bytes |
| `POST` | `/v1/live-sessions/<id>/resize` | Resize the PTY |
| `POST` | `/v1/live-sessions/<id>/attach` | Open a desktop terminal |
| `GET` | `/v1/fs/roots` | Filesystem roots for browsing |
| `GET` | `/v1/fs/list?path=...&showHidden=0\|1` | List folders |
| `GET` | `/v1/fs/read?path=...&max=...` | Read a small file |
| `POST` | `/v1/fs/mkdir` | Create a folder |

### Start-session body

```json
{
  "provider": "claude",
  "cwd": "/absolute/path/on/the/pc",
  "prompt": "optional initial prompt",
  "title": "optional title",
  "resumeSessionId": "optional provider session id",
  "openOnDesktop": true
}
```

### Terminal query parameters

- `cursor` — byte cursor to continue from
- `plain=1` — return ANSI-stripped text for mobile
- `max` — maximum bytes to return (1024..262144)

### Security boundary

- File-backed transcript refs are opaque to the client and validated against
  the provider's configured session roots, including resolved symbolic links.
- Only sessions started by this bridge instance can be stopped or controlled.
- The bridge binds to `0.0.0.0` by default for LAN use; restrict it with
  `--local` when you do not need direct access.
- Use TLS on the relay before exposing it to the public internet.
