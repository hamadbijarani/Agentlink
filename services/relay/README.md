# AgentLink Relay

A small, self-hosted WebSocket relay. It lets a phone reach a desktop bridge
over the internet without exposing the PC directly.

## Run

```bash
cd services/relay
dart pub get
dart run bin/agentlink_relay.dart --port 8787 --token 'a-long-relay-token'
```

Use `--cert` and `--key` (or a TLS reverse proxy) before exposing the port to
the public internet. The relay token must be at least 16 characters.

## Protocol

- Bridges connect to `/v1/connect?role=bridge&bridgeId=...&secret=...`.
- Phones connect to `/v1/connect?role=client&bridgeId=...&token=...`.
- Frames are JSON with type `req`, `res`, `event`, `ready`, `bridge`, `ping`,
  and `pong`.
- Client request paths must start with `/v1/`. Messages are limited to 8 MiB
  and at most 64 requests may be in flight per client.
- The relay persists bridge registration state so a bridge can reconnect after
  a restart.

## Security

- The relay authenticates both sides with the configured token.
- It only forwards requests; it never sees agent credentials or session files.
- Bridges register with a per-bridge secret; phones use the relay token plus
  their device token for the bridge.
- Use `wss://` in production.
