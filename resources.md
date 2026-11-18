# Resources & References: Multi-Agent AI Session Manager

## Official Protocols & Specifications

| Resource | Link | Description |
|----------|------|-------------|
| **Agent Client Protocol (ACP) v1** | https://agentclientprotocol.com/protocol/v1/overview | Official ACP specification - JSON-RPC 2.0 based |
| **ACP GitHub Repository** | https://github.com/agent-client-protocol/agent-client-protocol | Protocol definitions, schemas, examples |
| **OpenCode ACP Docs** | https://opencode.ai/docs/cli/acp/ | OpenCode-specific ACP implementation details |
| **OpenCode ACP Source** | https://github.com/sst/opencode/tree/main/packages/opencode/src/acp | Reference implementation in TypeScript/Effect |

## Dart/Flutter ACP Libraries

| Package | Pub.dev | GitHub | Description |
|---------|---------|--------|-------------|
| **acpd** | https://pub.dev/packages/acpd | https://github.com/fluttercandies/acpd | Complete ACP v1 SDK for Dart - schema, JSON-RPC, sessions |
| **acpd_io** | https://pub.dev/packages/acpd_io | https://github.com/fluttercandies/acpd | Stdio transport for local agent processes |
| **acpd_http** | https://pub.dev/packages/acpd_http | https://github.com/fluttercandies/acpd | HTTP/SSE/WebSocket transports |
| **acpd_test** | https://pub.dev/packages/acpd_test | https://github.com/fluttercandies/acpd | Testing utilities, in-memory transports |
| **dart_acp_sdk** | https://pub.dev/packages/dart_acp_sdk | https://github.com/Salakar/dart_acp | Alternative ACP SDK with different API style |

## Terminal Emulation

| Package | Pub.dev | GitHub | Description |
|---------|---------|--------|-------------|
| **xterm.dart** | https://pub.dev/packages/xterm | https://github.com/TerminalStudio/xterm.dart | Full-featured terminal emulator for Flutter, mobile optimized |
| **xterm.dart Examples** | - | https://github.com/TerminalStudio/xterm.dart/tree/main/example | Usage examples |

## Existing Open Source Projects (Reference Implementations)

### Mobile Apps (Flutter)
| Project | GitHub | Description |
|---------|--------|-------------|
| **Runmote** | https://github.com/runmote/runmote | Flutter Android app + daemon + relay for ACP agents |
| **OpenCode Mobile** | https://github.com/opencode-ai/opencode-mobile | Official OpenCode mobile client (Flutter, drift, SSE) |
| **Zedra** | https://github.com/zedra-app/zedra | QUIC-based remote control for multiple agents |
| **Happier** | https://github.com/happier-dev/happier | Multi-device orchestration for 100+ agents |
| **PiPilot** | https://github.com/CikeSeven/pi_pilot | Flutter app for Pi agent with session tree navigation |
| **Harness Remote** | https://github.com/giuliastro/harness-remote | Android/Web/Desktop for multiple ACP agents |
| **Termopus** | https://github.com/Termopus/termopus | Flutter + Rust bridge + Cloudflare Durable Objects |
| **MonkeySSH** | https://github.com/depollsoft/MonkeySSH | Full SSH client with agent launch presets |
| **Kammel** | https://github.com/kammel-app/kammel | SSH + SFTP + terminal + editor for Android/Linux |
| **ForgeMind** | https://github.com/diiiua/forgemind | SSH + Cloudflare Zero Trust + MCP client |
| **WorkFromPhone** | https://github.com/xxparthparekhxx/workfromphone | FastAPI backend + Flutter client |

### Session Managers & Converters (Desktop/CLI)
| Project | GitHub | Language | Description |
|---------|--------|----------|-------------|
| **ai-session-manager** | https://github.com/daniel-farina/ai-session-manager | TypeScript/React | Web UI reading 9+ agent formats locally |
| **baton** | https://github.com/Kaseban/baton | TypeScript/Node | Format converter between 8+ agents |
| **sess** | https://github.com/dspv/sess | Python | Markdown brief export/import for context transfer |
| **cue** | https://github.com/cue-org/cue | Go | Unified CLI wrapper for 4 agents |
| **partyline** | https://github.com/partyline/partyline | Go | tmux-based session manager |
| **Motif** | https://github.com/xiachufang/motif | Rust + Flutter | PTY pool, git, file ops, mirrored sessions |

### Daemon/Relay Infrastructure
| Project | GitHub | Description |
|---------|--------|-------------|
| **Runmote Daemon** | https://github.com/runmote/daemon | Cross-platform daemon (Linux/macOS/Windows) |
| **Runmote Relay** | https://github.com/runmote/relay | Self-hostable WebSocket relay (Docker) |
| **Harness Remote Gateway** | https://github.com/giuliastro/harness-remote/tree/main/gateway | Local-first control plane daemon |
| **Motif Server** | https://github.com/xiachufang/motif/tree/main/crates/motif-server | Rust daemon with embedded Flutter web client |

## Agent-Specific Documentation

### Session Storage Formats
| Agent | Documentation | Storage Location |
|-------|--------------|------------------|
| **Claude Code** | https://github.com/anthropics/claude-code | `~/.claude/projects/**/*.jsonl` |
| **OpenCode** | https://opencode.ai/docs/ | `~/.local/share/opencode/opencode.db` (SQLite) |
| **Codex CLI** | https://github.com/openai/codex | `~/.codex/sessions/**/*.jsonl` |
| **Gemini CLI** | https://github.com/google-gemini/gemini-cli | `~/.gemini/tmp/**/checkpoint*.json` |
| **Cursor** | https://cursor.com/ | `~/.cursor/projects/**/agent-transcripts/*.jsonl` |
| **Aider** | https://github.com/Aider-AI/Aider | `~/.aider/*.jsonl` |
| **Goose** | https://github.com/block/goose | `~/.local/share/goose/sessions/*.jsonl` |
| **Copilot CLI** | https://github.com/github/copilot-cli | `~/.copilot/history-session-state/*.json` |
| **DeepSeek Harness** | https://github.com/deepseek-ai/harness | `~/.deepseek/harness/session.v3.jsonl.zstd` |
| **Pi** | https://github.com/pilabs/pi | `~/.pi/sessions/` |

### ACP Integration Commands
| Agent | ACP Command | Status |
|-------|-------------|--------|
| OpenCode | `opencode acp` | ✅ Native |
| Codex CLI | `codex --acp` | ✅ Native |
| Claude Code | `claude --acp` | ✅ Native |
| Copilot CLI | `copilot --acp` | ✅ Native |
| OpenCode v2 | `opencode acp` | ✅ Native |
| DeepSeek Harness | `dsh --profile acp` | ✅ Native |
| MiMo Code | `mimo acp` | ✅ Native |
| Oh My Pi | `omp acp` | ✅ Native |
| PI | `pi acp` | ✅ Native |

## Flutter Packages for Core Features

### State Management & Architecture
```yaml
flutter_bloc: ^8.1.0          # BLoC/Cubit pattern
riverpod: ^2.5.0              # Alternative: Riverpod
get_it: ^7.7.0                # Service locator / DI
freezed: ^2.5.0               # Immutable data classes + unions
equatable: ^2.0.0             # Value equality
```

### Local Database
```yaml
drift: ^2.18.0                # Type-safe SQLite
sqlite3_flutter_libs: ^0.5.0  # Bundled SQLite
path_provider: ^2.1.0         # Platform paths
```

### Networking & WebSocket
```yaml
web_socket_channel: ^2.4.0    # WebSocket client
http: ^1.2.0                  # HTTP client
dio: ^5.4.0                   # Alternative HTTP with interceptors
```

### Security & Storage
```yaml
flutter_secure_storage: ^9.0.0  # Encrypted key-value (Keystore/Keychain)
shared_preferences: ^2.2.0      # Simple preferences
encrypt: ^5.0.0                 # Encryption utilities
pointycastle: ^3.8.0            # Cryptographic algorithms
```

### QR Code & Scanning
```yaml
mobile_scanner: ^5.0.0      # Camera-based barcode/QR scanning
qr_flutter: ^4.1.0          # QR code generation
```

### Terminal & Code Editing
```yaml
xterm: ^3.2.0               # Terminal emulator
flutter_highlight: ^0.7.0   # Syntax highlighting
code_edit: ^0.3.0           # Code editor widget
```

### Background & Notifications
```yaml
flutter_background_service: ^5.0.0      # Android foreground service
flutter_local_notifications: ^17.0.0    # Local notifications
firebase_messaging: ^14.7.0             # FCM push notifications
workmanager: ^0.5.0                     # Background tasks
```

### File System & Paths
```yaml
path: ^1.9.0                # Path manipulation
file_picker: ^8.0.0         # File selection
permission_handler: ^11.0.0 # Runtime permissions
```

### UI & Theming
```yaml
material_symbols_icons: ^4.2670.0  # Material Symbols
google_fonts: ^6.1.0               # Dynamic fonts
animate_do: ^3.3.0                 # Animations
```

### Testing
```yaml
bloc_test: ^9.1.0           # BLoC testing
mocktail: ^1.0.0            # Mocking
integration_test:           # Flutter integration tests
patrol: ^2.0.0              # E2E testing (alternative)
```

## Architecture References

### Clean Architecture for Flutter
- **Reso Coder Tutorial**: https://resocoder.com/2019/08/27/flutter-tdd-clean-architecture-course-1-explanation-project-structure/
- **Flutter Architecture Samples**: https://github.com/flutter/samples/tree/main/architecture
- **Very Good Architecture**: https://github.com/VeryGoodOpenSource/very_good_architecture

### BLoC Pattern
- **Official Bloc Library**: https://bloclibrary.dev/
- **Bloc Testing**: https://bloclibrary.dev/testing/

### Drift Database
- **Documentation**: https://drift.simonbinder.eu/
- **Migration Guide**: https://drift.simonbinder.eu/docs/advanced-features/migrations/

### xterm.dart Usage
- **README**: https://github.com/TerminalStudio/xterm.dart#readme
- **Mobile Keyboard**: https://github.com/TerminalStudio/xterm.dart/blob/main/doc/mobile_keyboard.md

## Platform-Specific Guides

### Android Background Execution
- **Foreground Services**: https://developer.android.com/guide/components/foreground-services
- **Android 14 Changes**: https://developer.android.com/about/versions/14/changes/foreground-services
- **Flutter Background Service**: https://pub.dev/packages/flutter_background_service

### iOS Background (Future)
- **Background Modes**: https://developer.apple.com/documentation/ios/app-background-modes
- **Push Notifications**: https://developer.apple.com/documentation/usernotifications

### Desktop Daemon Deployment
- **systemd Service**: https://www.freedesktop.org/software/systemd/man/systemd.service.html
- **launchd (macOS)**: https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html
- **Task Scheduler (Windows)**: https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page

## Security Resources

### Encryption & Key Management
- **Android Keystore**: https://developer.android.com/training/articles/keystore
- **iOS Keychain**: https://developer.apple.com/documentation/security/keychain_services
- **flutter_secure_storage Internals**: https://pub.dev/packages/flutter_secure_storage

### Network Security
- **Certificate Pinning**: https://owasp.org/www-project-mobile-top-10/2023/risks/m4-insecure-authentication
- **TLS Best Practices**: https://developer.android.com/training/articles/security-config

## Design & UX References

### Material 3
- **Material 3 Spec**: https://m3.material.io/
- **Flutter Material 3**: https://docs.flutter.dev/ui/design/material
- **Dynamic Color**: https://developer.android.com/design/ui/color/dynamic-color

### Mobile Terminal UX
- **Termius Mobile**: https://termius.com/ (Reference for terminal UX)
- **Blink Shell**: https://blink.sh/ (iOS terminal UX patterns)
- **xterm.js Mobile**: https://xtermjs.org/docs/guides/mobile/

## Learning Resources

### ACP Protocol Deep Dive
- **ACP Overview**: https://agentclientprotocol.com/protocol/v1/overview
- **ACP Methods Reference**: https://agentclientprotocol.com/protocol/v1/methods
- **OpenCode ACP Service**: https://github.com/sst/opencode/blob/main/packages/opencode/src/acp/service.ts

### Session Format Analysis
- **Agent Archaeology Field Guide**: https://agentarchaeology.ai/field-guide/session-stores/
- **Five Agents Comparison**: https://dev.to/dspv/five-coding-agents-five-formats-one-table-5g7h
- **Baton Format Docs**: https://github.com/Kaseban/baton/blob/main/docs/formats.md

### Flutter Advanced Topics
- **Flutter Internals**: https://flutter.github.io/flutter-internals/
- **Performance Best Practices**: https://docs.flutter.dev/perf/best-practices
- **Platform Channels**: https://docs.flutter.dev/platform-integration/platform-channels

## Community & Support

### Discord/Slack Communities
- **Flutter Discord**: https://discord.gg/flutter
- **Dart Discord**: https://discord.gg/dart
- **OpenCode Discord**: https://discord.gg/opencode
- **ACP Discussions**: https://github.com/agent-client-protocol/agent-client-protocol/discussions

### Issue Trackers for Reference
- **acpd Issues**: https://github.com/fluttercandies/acpd/issues
- **xterm.dart Issues**: https://github.com/TerminalStudio/xterm.dart/issues
- **Runmote Issues**: https://github.com/runmote/runmote/issues

## Sample Data for Testing

### Session Format Samples
| Agent | Sample Location |
|-------|-----------------|
| Claude Code | https://github.com/daniel-farina/ai-session-manager/tree/main/test/fixtures/claude |
| OpenCode | https://github.com/sst/opencode/tree/main/packages/opencode/test/fixtures |
| Codex | https://github.com/openai/codex/tree/main/src/codex/session |
| Gemini | https://github.com/google-gemini/gemini-cli/tree/main/packages/cli/test/fixtures |

### Test Repositories
- **micro-repo**: https://github.com/daniel-farina/micro-repo (Tiny repo for agent testing)
- **ACP Test Vectors**: https://github.com/agent-client-protocol/agent-client-protocol/tree/main/test-vectors

## Deployment & Distribution

### Google Play Store
- **Play Console**: https://play.google.com/console
- **App Signing**: https://developer.android.com/studio/publish/app-signing
- **Release Workflow**: https://docs.github.com/en/actions/use-cases-and-examples/deploying/deploying-to-google-play

### GitHub Releases (Alternative)
- **Release Action**: https://github.com/softprops/action-gh-release
- **Flutter Build APK/AAB**: https://docs.flutter.dev/deployment/android

### F-Droid (Open Source)
- **F-Droid Submission**: https://gitlab.com/fdroid/fdroiddata/-/blob/master/CONTRIBUTING.md

## License Considerations

| Dependency | License | Compatibility |
|------------|---------|---------------|
| Flutter | BSD-3 | ✅ |
| acpd | MIT | ✅ |
| xterm.dart | MIT | ✅ |
| drift | MIT | ✅ |
| flutter_secure_storage | MIT | ✅ |
| mobile_scanner | MIT | ✅ |
| Runmote Relay | MIT | ✅ (if used) |

**Recommendation**: Use MIT/BSD licensed dependencies to keep app distributable under any license.

---

## Quick Start Commands

```bash
# Create new Flutter project
flutter create --org com.agentlink --platforms=android agentlink
cd agentlink

# Add core dependencies
flutter pub add flutter_bloc drift sqlite3_flutter_libs path_provider
flutter pub add web_socket_channel http acpd acpd_http acpd_io
flutter pub add xterm flutter_secure_storage shared_preferences
flutter pub add mobile_scanner qr_flutter freezed_annotation json_annotation
flutter pub add logger equatable intl

# Add dev dependencies
flutter pub add --dev build_runner freezed json_serializable drift_dev
flutter pub add --dev bloc_test mocktail very_good_analysis

# Generate code
dart run build_runner build --delete-conflicting-outputs

# Run on device
flutter run
```

---

## Recommended Reading Order

1. **ACP Specification** - Understand the protocol
2. **acpd README** - Learn Dart ACP API
3. **ai-session-manager source** - See parser implementations
4. **baton source** - See format conversion logic
5. **OpenCode Mobile source** - See Flutter ACP integration
6. **xterm.dart examples** - Learn terminal integration
7. **Runmote daemon/relay** - Understand infrastructure

---

*Last Updated: November 2026*
*Maintainer: [Your Name/Project]*