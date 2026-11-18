# AgentLink Mobile

Flutter Android application for the AgentLink MVP. The app code is isolated in
this directory and communicates with the separate PC bridge only through its
versioned HTTP API.

## Run

1. Start `services/desktop_bridge` on the PC.
2. Connect an Android device or start an emulator.
3. Run:

```bash
cd apps/mobile
flutter pub get
flutter run
```

For a physical phone, use the PC's LAN/VPN address. For an Android emulator,
use `http://10.0.2.2:7331` when the bridge is bound on the host.

## MVP features

- Saves and tests a token-authenticated desktop bridge profile.
- Lists and searches sessions from Claude Code, OpenCode, Codex, and Gemini.
- Displays normalized transcript messages.
- Starts one-shot managed sessions with an initial prompt.
- Polls run status/output and can stop a managed process.

This MVP deliberately has no provider SDKs, API keys, desktop process code, or
session parsers inside the Android application.

The bridge token is stored with `flutter_secure_storage`, backed by Android
Keystore. The MVP connection itself is plain HTTP and must remain on a trusted
LAN or VPN.
