# Implementation Plan: Multi-Agent AI Session Manager for Android (Flutter)

## Project Overview

**App Name**: AgentLink (tentative)
**Target Platform**: Android 8.0+ (API 24+)
**Framework**: Flutter 3.24+ / Dart 3.5+
**Architecture**: Clean Architecture + BLoC/Cubit + Repository Pattern

---

## Phase 1: Foundation & Local Session Browser (Weeks 1-4)

### Sprint 1: Project Setup & Core Infrastructure (Week 1)

#### Tasks
- [ ] Initialize Flutter project with proper structure
- [ ] Set up dependency injection (get_it / riverpod)
- [ ] Configure local database (drift/sqlite) for session caching
- [ ] Set up logging (logger), error handling (sentry/crashlytics optional)
- [ ] Configure CI/CD (GitHub Actions: analyze, test, build APK)
- [ ] Set up code generation (freezed, json_serializable, build_runner)

#### Project Structure
```
lib/
├── core/
│   ├── constants/         # App constants, paths, keys
│   ├── errors/            # Failures, exceptions
│   ├── utils/             # Extensions, helpers
│   ├── network/           # HTTP client, WebSocket wrapper
│   └── storage/           # Secure storage, preferences
├── data/
│   ├── datasources/
│   │   ├── local/         # Drift database, file system readers
│   │   └── remote/        # ACP client, daemon API
│   ├── models/            # DTOs, entity mappings
│   └── repositories/      # Repository implementations
├── domain/
│   ├── entities/          # Core business objects
│   ├── repositories/      # Repository contracts
│   └── usecases/          # Business logic
└── presentation/
    ├── pages/             # Screens
    ├── widgets/           # Reusable components
    ├── cubits/blocs/      # State management
    └── themes/            # Material 3 theming
```

#### Key Dependencies (pubspec.yaml)
```yaml
dependencies:
  flutter:
    sdk: flutter
  # State Management
  flutter_bloc: ^8.1.0
  # Local Database
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.5.0
  path_provider: ^2.1.0
  # Networking
  web_socket_channel: ^2.4.0
  http: ^1.2.0
  # ACP Protocol
  acpd: ^0.3.0
  acpd_http: ^0.3.0
  acpd_io: ^0.3.0
  # Terminal
  xterm: ^3.2.0
  # Security/Storage
  flutter_secure_storage: ^9.0.0
  shared_preferences: ^2.2.0
  # QR/Scanning
  mobile_scanner: ^5.0.0
  qr_flutter: ^4.1.0
  # File System
  path: ^1.9.0
  # Utils
  freezed_annotation: ^2.4.0
  json_annotation: ^4.8.0
  logger: ^2.0.0
  equatable: ^2.0.0
  intl: ^0.19.0
  # Background
  flutter_background_service: ^5.0.0
  # Notifications
  flutter_local_notifications: ^17.0.0
```

---

### Sprint 2: Local Session Discovery & Parsing (Week 2)

#### 2.1 Session File Discovery
Create `SessionDiscoveryService` that scans known paths:

```dart
// domain/entities/session_source.dart
enum SessionSource {
  claudeCode,
  openCode,
  codex,
  geminiCli,
  cursor,
  aider,
  goose,
  copilotCli,
  deepSeekHarness,
  pi,
  // extensible
}

// domain/entities/agent_session.dart
@freezed
class AgentSession with _$AgentSession {
  const factory AgentSession({
    required String id,
    required String title,
    required SessionSource source,
    required String projectPath,
    required String projectName,
    required DateTime lastActivity,
    required int messageCount,
    required String? branch,
    String? resumeCommand,  // CLI command to resume
    Map<String, dynamic>? metadata,
  }) = _AgentSession;
}
```

#### 2.2 Parser Adapters (Strategy Pattern)
```dart
// domain/repositories/session_parser.dart
abstract class SessionParser {
  SessionSource get source;
  Future<List<AgentSession>> discoverSessions();
  Future<SessionDetail> parseSession(String sessionRef);
  String getResumeCommand(String sessionId, String projectPath);
}

// Implementations:
- ClaudeCodeParser: reads ~/.claude/projects/**/*.jsonl
- OpenCodeParser: reads SQLite ~/.local/share/opencode/opencode.db
- CodexParser: reads ~/.codex/sessions/**/*.jsonl
- GeminiParser: reads ~/.gemini/tmp/**/checkpoint*.json
- CursorParser: reads ~/.cursor/projects/**/agent-transcripts/*.jsonl
- etc.
```

#### 2.3 Platform-Specific Path Resolution
```dart
// core/utils/platform_paths.dart
class PlatformPaths {
  static String getHomeDirectory() => Platform.environment['HOME'] ?? '';
  static String getClaudePath() => '$home/.claude/projects';
  static String getOpenCodePath() => Platform.isMacOS 
      ? '$home/Library/Application Support/opencode/opencode.db'
      : '$home/.local/share/opencode/opencode.db';
  // ... etc with env var overrides (CODEX_HOME, OPENCODE_HOME, etc.)
}
```

#### 2.4 Unified Session List Use Case
```dart
// domain/usecases/get_all_sessions.dart
class GetAllSessions {
  final List<SessionParser> parsers;
  
  Future<List<AgentSession>> call({bool forceRefresh = false}) async {
    final futures = parsers.map((p) => p.discoverSessions());
    final results = await Future.wait(futures);
    return results.expand((e) => e).toList()
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  }
}
```

---

### Sprint 3: UI - Session List & Detail Views (Week 3)

#### 3.1 Session List Screen
- **Material 3** design with dynamic color theming
- **Filtering**: By source, project, date range, search query
- **Sorting**: Recent first, alphabetical, message count
- **Pull-to-refresh** for re-scanning
- **Empty states**: No sessions found, no agents installed

#### 3.2 Session Detail Screen
- **Message timeline** with role indicators (user/assistant/tool)
- **Syntax highlighting** for code blocks (flutter_highlight)
- **Tool call visualization**: Expandable cards with input/output
- **Token usage/cost display** (where available)
- **Resume command copy button**
- **Export session brief** (markdown)

#### 3.3 State Management
```dart
// presentation/cubits/session_list_cubit.dart
class SessionListCubit extends Cubit<SessionListState> {
  final GetAllSessions getAllSessions;
  final SessionFilter filter;
  
  // States: Loading, Loaded(List<AgentSession>), Error
  // Filter state managed separately or combined
}
```

---

### Sprint 4: Session Brief Export & Local Features (Week 4)

#### 4.1 Markdown Brief Generator
Based on `sess` tool approach:
```dart
// domain/usecases/export_session_brief.dart
class ExportSessionBrief {
  // Extract: Goal, Decisions, Files touched, Constraints, Next actions, Key facts
  // Output: sess-brief/v1 markdown format
  Future<String> call(AgentSession session, SessionDetail detail);
}
```

#### 4.2 Local Database Caching (Drift)
```dart
// data/datasources/local/session_database.dart
@DriftDatabase(tables: [SessionCache, MessageCache, ProjectCache])
class SessionDatabase extends _$SessionDatabase {
  // Cache parsed sessions for instant load
  // Invalidate on file modification time change
}
```

#### 4.3 Settings & Configuration
- Agent enable/disable toggles
- Custom path overrides
- Theme selection (light/dark/system)
- Auto-refresh interval
- Export directory preference

---

## Phase 2: Remote Control via ACP (Weeks 5-10)

### Sprint 5: ACP Client Implementation (Week 5)

#### 5.1 ACP Connection Manager
```dart
// data/datasources/remote/acp_connection.dart
class AcpConnectionManager {
  // Transport abstraction: stdio, HTTP/SSE, WebSocket
  // Connection pooling for multiple agents
  // Auto-reconnect with exponential backoff
  // Session lifecycle management
}
```

#### 5.2 ACP Client Wrapper (using acpd)
```dart
// data/datasources/remote/acp_client.dart
class AcpAgentClient {
  final ClientRole clientRole;
  late final Client client;
  
  Future<Session> createSession({
    required String cwd,
    List<String> additionalDirectories = const [],
    List<McpServerConfig> mcpServers = const [],
  });
  
  Future<Session> loadSession(String sessionId, String cwd);
  Future<List<SessionInfo>> listSessions({String? cwd});
  Stream<SessionUpdate> prompt(String sessionId, List<ContentBlock> prompt);
  Future<void> cancelPrompt(String sessionId);
  Future<void> approvePermission(String sessionId, String requestId);
  Future<void> denyPermission(String sessionId, String requestId);
}
```

#### 5.3 Desktop Daemon Discovery
- mDNS/Bonjour for LAN discovery (`opencode serve`, `runmote`, custom daemon)
- QR code pairing (like Runmote/OpenCode Mobile)
- Manual IP/port entry fallback
- Connection profiles storage (encrypted)

---

### Sprint 6: Daemon Implementation (Desktop Side) (Week 6)

> **Note**: Desktop daemon can be a separate Flutter/Dart project or Go/Rust binary

#### 6.1 Daemon Responsibilities
- Run as background service (systemd/launchd/Task Scheduler)
- Expose ACP over WebSocket/HTTP
- Manage multiple agent processes
- Handle authentication/authorization
- File system operations (read/write via ACP fs capabilities)
- Terminal PTY management (via ACP terminal capabilities)

#### 6.2 Minimal Daemon (Dart - for consistency)
```dart
// daemon/main.dart
import 'package:acpd/acpd.dart';
import 'package:acpd_http/acpd_http.dart';
import 'package:acpd_io/acpd_io.dart';

void main() async {
  final server = AcpHttpServer(
    agentRole: AgentRole()
      .onInitialize(handleInitialize)
      .onNewSession(handleNewSession)
      .onLoadSession(handleLoadSession)
      // ... all ACP methods
    ,
    authorize: (request) => validateToken(request),
  );
  
  await server.listen(InternetAddress.loopbackIPv4, 8080);
  // Also support stdio for local CLI integration
}
```

#### 6.3 Agent Process Management
```dart
// daemon/agent_manager.dart
class AgentManager {
  // Detect installed agents (which claude, which opencode, etc.)
  // Launch agent with ACP stdio transport
  // Track process lifecycle
  // Handle multiple concurrent sessions per agent
}
```

---

### Sprint 7: Mobile ↔ Daemon Communication (Week 7)

#### 7.1 Transport Layer
```dart
// data/datasources/remote/transport.dart
enum TransportType { webSocket, httpSse, stdioLocal }

class TransportConfig {
  final TransportType type;
  final String endpoint;  // ws://, wss://, http://, https://
  final String? authToken;
  final Duration heartbeatInterval;
}
```

#### 7.2 Pairing Flow
1. User runs `agentlink pair` on desktop (daemon prints QR + code)
2. Mobile app scans QR or enters 8-digit code
3. Daemon validates, returns session token
4. Token stored securely (flutter_secure_storage)
5. App connects to daemon endpoint

#### 7.3 Connection Management
- Automatic reconnection on network changes
- Offline queue for pending actions
- Connection state UI indicator

---

### Sprint 8: Real-Time Session UI (Week 8)

#### 8.1 Streaming Chat Interface
- **Token-by-token streaming** using `session/update` notifications
- **Thinking cards** for reasoning models
- **Tool call visualization** with live progress
- **Diff rendering** for file changes (side-by-side or unified)
- **Mermaid/LaTeX** rendering for diagrams/math

#### 8.2 Approval & Permission Handling
- Push notifications for pending approvals (background)
- In-app approval dialogs with diff preview
- Batch approve/deny for multiple requests
- Custom permission policies per agent/project

#### 8.3 Session Controls
- **Send prompt** (text, images, files)
- **Cancel/Interrupt** current turn
- **Fork session** from specific message
- **Resume/Load** previous session
- **Close/Delete** session

---

### Sprint 9: Terminal & File Browser (Week 9)

#### 9.1 Terminal Emulation (xterm.dart)
```dart
// presentation/widgets/agent_terminal.dart
class AgentTerminal extends StatefulWidget {
  final String sessionId;
  final String cwd;
  
  // PTY over ACP terminal/create, terminal/output, terminal/release
  // Mobile-optimized: gesture input, virtual keyboard shortcuts
  // Themes: One Dark, One Light, custom
}
```

#### 9.2 File Browser & Editor
- Tree view with breadcrumbs
- Syntax highlighting editor (code_edit or custom)
- Diff view with frozen line numbers
- Search across files
- Upload/download from mobile

---

### Sprint 10: Background & Notifications (Week 10)

#### 10.1 Foreground Service
- Persistent notification for active sessions
- Keep WebSocket alive in background
- Handle Android 14+ foreground service types

#### 10.2 Push Notifications (FCM)
- Daemon sends push via FCM when:
  - Session completes
  - Permission requested
  - Error occurs
  - Agent asks question
- Deep link to specific session

#### 10.3 Background Sync
- Periodic session list refresh
- Offline action queue processing
- Battery optimization handling

---

## Phase 3: Advanced Features (Weeks 11-16)

### Sprint 11: Cross-Agent Session Conversion (Week 11)

#### 11.1 Format Conversion Engine
Port `baton` logic to Dart:
```dart
// domain/usecases/convert_session.dart
class ConvertSession {
  // Canonical intermediate representation
  // Read from source format → CanonicalSession → Write to target format
  // Support: Claude ↔ OpenCode ↔ Codex ↔ Gemini (where possible)
}
```

#### 11.2 Session Brief Import/Export
- Generate `sess-brief/v1` markdown
- Import brief as resume prompt for any agent
- Quality scoring (optional, needs LLM API)

---

### Sprint 12: Self-Hosted Relay (Week 12)

#### 12.1 Relay Server (Dart/Go)
- WebSocket relay with session routing
- Pairing code generation/validation
- Rate limiting, encryption
- Docker Compose deployment
- mDNS for LAN discovery

#### 12.2 Mobile Relay Integration
- Auto-detect LAN vs internet
- Fallback to relay when not on same network
- Relay URL configuration in settings

---

### Sprint 13: Multi-Machine Dashboard (Week 13)

#### 13.1 Machine Management
- Add/remove machines (daemon endpoints)
- Machine health monitoring
- Per-machine agent detection
- Unified session list across machines

#### 13.2 Cross-Machine Continuation
- Resume session on different machine
- Project identity preservation
- Git worktree awareness

---

### Sprint 14: MCP Server Management (Week 14)

#### 14.1 MCP Configuration UI
- List configured MCP servers
- Add stdio/HTTP MCP servers from mobile
- Test MCP connections
- Per-session MCP server attachment

---

### Sprint 15: Git Worktree & Project Visualization (Week 15)

#### 15.1 Git Integration
- Show worktrees per project
- Agent sessions per worktree
- Branch status, uncommitted changes
- Parallel agent visualization

---

### Sprint 16: Polish & Release Prep (Week 16)

#### 16.1 Testing & QA
- Unit tests (parsers, use cases)
- Widget tests (key screens)
- Integration tests (daemon communication)
- Device farm testing (Firebase Test Lab)

#### 16.2 Performance Optimization
- Lazy loading for large session lists
- Image caching for diffs/screenshots
- Database query optimization
- Memory profiling

#### 16.3 Store Preparation
- Play Store listing, screenshots, privacy policy
- APK/AAB signing configuration
- Release automation

---

## Technical Architecture Details

### Data Flow (Phase 1 - Local Only)
```
File System → SessionParser → AgentSession Entity → Drift Cache → BLoC → UI
```

### Data Flow (Phase 2 - Remote)
```
Mobile App (ACP Client) ←WebSocket→ Daemon (ACP Server) ←stdio→ Agent Process
                              ↑
                        Relay (optional)
```

### Database Schema (Drift)
```sql
-- Session cache
CREATE TABLE session_cache (
  id TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  title TEXT,
  project_path TEXT NOT NULL,
  project_name TEXT,
  last_activity INTEGER NOT NULL,  -- unix ms
  message_count INTEGER DEFAULT 0,
  branch TEXT,
  resume_command TEXT,
  metadata TEXT,  -- JSON
  file_mtime INTEGER NOT NULL,  -- for invalidation
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Message cache (for detail view)
CREATE TABLE message_cache (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES session_cache(id),
  role TEXT NOT NULL,  -- user, assistant, tool, system
  content TEXT NOT NULL,  -- JSON
  timestamp INTEGER NOT NULL,
  sequence INTEGER NOT NULL
);

-- Machine/daemon profiles
CREATE TABLE machine_profile (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  auth_token TEXT,  -- encrypted
  transport_type TEXT NOT NULL,
  is_default INTEGER DEFAULT 0,
  last_connected INTEGER,
  created_at INTEGER NOT NULL
);
```

---

## Security Considerations

| Aspect | Implementation |
|--------|----------------|
| Session Data | Encrypted at rest (SQLCipher or flutter_secure_storage for keys) |
| Daemon Auth | Token-based, rotated on pairing, stored in Android Keystore |
| Network | TLS 1.3 for all connections, certificate pinning optional |
| Relay | E2E encryption (session content), relay only routes metadata |
| Biometrics | Local auth for app access, credential decryption |
| File Access | Scoped storage, no broad filesystem permission needed |

---

## Minimal External Dependencies Strategy

| Need | Internal Solution | External Alternative (Avoid) |
|------|-------------------|------------------------------|
| Session Parsing | Custom Dart parsers | Python/Node scripts |
| ACP Protocol | `acpd` (Dart native) | Custom JSON-RPC |
| Terminal | `xterm.dart` (Flutter native) | Web-based terminal |
| Relay | Custom Dart/Go binary | Cloudflare, ngrok, Tailscale |
| Database | Drift (SQLite) | Firebase, Supabase |
| Notifications | FCM (standard) | Custom push service |
| File Transfer | ACP fs capabilities | SFTP, custom protocol |

---

## Milestones & Deliverables

| Milestone | Target | Deliverable |
|-----------|--------|-------------|
| M1: Foundation | Week 1 | Buildable Flutter project, CI/CD |
| M2: Local Browser | Week 4 | App lists sessions from 5+ agents locally |
| M3: Remote Control | Week 10 | Full ACP control over LAN |
| M4: Advanced | Week 16 | Cross-agent, relay, multi-machine, MCP |
| M5: Release | Week 18 | Play Store ready APK/AAB |

---

## Team & Resources (Solo Developer Assumptions)

- **Primary**: 1 Flutter/Dart developer
- **Desktop Daemon**: Same codebase (Dart) or minimal Go/Rust
- **Relay**: Optional, can use Runmote's open-source relay
- **Design**: Material 3 defaults, custom theme later
- **Testing**: Emulators + physical device, no device farm initially

---

## Risk Mitigation Summary

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Agent format changes | High | Medium | Adapter pattern, versioned parsers, tests with sample data |
| ACP v2 breaking changes | Low | High | Pin to v1, monitor spec, abstraction layer |
| Android background limits | High | High | Foreground service, proper notification channels |
| Large session performance | Medium | Medium | Pagination, streaming parse, background isolates |
| Daemon complexity | High | High | Start minimal, iterate, consider existing daemons |

---

## Future Extensibility

- **iOS Support**: Flutter makes this straightforward
- **Desktop App**: Same codebase runs on Linux/macOS/Windows
- **Web App**: Flutter Web for browser access
- **Plugin System**: Custom parser/agent adapters
- **AI Features**: Local LLM for session summarization (llama.cpp via FFI)
- **Team Features**: Shared session annotations, collaboration