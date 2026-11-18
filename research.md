# Research Document: Multi-Agent AI Session Manager for Android

## Executive Summary

This document consolidates research on building a Flutter Android app that can discover, monitor, control, and manage AI coding agent sessions across multiple providers (Claude Code, OpenCode, Codex, Gemini CLI, etc.) from a mobile device.

---

## 1. AI Agent Session Storage Formats & Locations

### 1.1 Claude Code
- **Location**: `~/.claude/projects/<project-hash>/<session-id>.jsonl`
- **Format**: JSON Lines (JSONL) with alternating `user` and `assistant` message types
- **Key fields**: `sessionId`, `timestamp`, `message.role`, `message.content[]` (includes tool_use/tool_result)
- **Resume command**: `claude --resume <session-id>`
- **Retention**: 30 days auto-deletion

### 1.2 OpenCode
- **Location**: 
  - Linux: `~/.local/share/opencode/opencode.db` (SQLite)
  - macOS: `~/Library/Application Support/opencode/opencode.db`
- **Format**: SQLite database with `session_v2` and `session_message` tables
- **Key tables**: `session_v2` (metadata), `session_message` (messages), `part` (tool calls/results)
- **Resume command**: `opencode --session <session-id>`
- **Export/Import**: `opencode session export/import` (JSON)

### 1.3 Codex CLI
- **Location**: `~/.codex/sessions/YYYY/MM/*.jsonl` (active), `~/.codex/archived_sessions/*.jsonl`, `~/.codex/headless/*.jsonl`
- **Format**: JSONL with `session_meta` header followed by `event_msg` records
- **Resume command**: `codex resume <session-id>`
- **Respects**: `$CODEX_HOME` environment variable

### 1.4 Gemini CLI
- **Location**: `~/.gemini/tmp/<session-id>/chats/` or checkpoint files
- **Format**: JSON checkpoint files, telemetry-based (OTel logs)
- **Resume command**: `gemini` → `/chat resume <session-id>`
- **Note**: Has internal session history under `~/.gemini/tmp/<session-id>/chats/`

### 1.5 Other Agents
| Agent | Location | Format | Resume |
|-------|----------|--------|--------|
| Cursor | `~/.cursor/projects/<hash>/agent-transcripts/<id>.jsonl` | JSONL | `cursor-agent --resume` |
| Goose | `~/.local/share/goose/sessions/*.jsonl` | JSONL | `goose session resume --name` |
| Aider | `~/.aider/` | JSONL | `aider --resume` |
| Copilot CLI | `~/.copilot/history-session-state/*.json` | JSON | `copilot --resume` |
| DeepSeek Harness | `~/.deepseek/harness/session.v3.jsonl.zstd` | JSONL + zstd | Custom |
| Pi | `~/.pi/sessions/` | JSONL | `pi --resume` |

---

## 2. Communication Protocols & Standards

### 2.1 Agent Client Protocol (ACP) - The Emerging Standard
- **Specification**: JSON-RPC 2.0 over stdio, HTTP/SSE, or WebSocket
- **Version**: v1 stable, v2 draft
- **Key Capabilities**:
  - Session management: `new`, `load`, `list`, `resume`, `fork`, `close`, `delete`
  - Prompt turns with streaming updates via `session/update` notifications
  - Permission requests, file operations, terminal access
  - MCP server integration
  - Config options (model, effort, mode)
  - Child session tracking

### 2.2 ACP Transport Options
| Transport | Use Case | Implementation |
|-----------|----------|----------------|
| stdio | Local subprocess | `acpd_io` package |
| HTTP/SSE | Remote with polling | `acpd_http` package |
| WebSocket | Real-time bidirectional | `acpd_http` package |

### 2.3 Agent ACP Support Status
| Agent | ACP Support | Command | Notes |
|-------|-------------|---------|-------|
| OpenCode | ✅ Native | `opencode acp` | Full v1 support, private server per process |
| Codex CLI | ✅ Native | `codex --acp` | Official ACP adapter |
| Claude Code | ✅ Native | `claude --acp` | Official ACP adapter |
| GitHub Copilot | ✅ Native | `copilot --acp` | Native ACP |
| OpenCode v2 | ✅ Native | `opencode acp` | Native ACP |
| DeepSeek Harness | ✅ Native | `dsh --profile acp` | ACP adapter |
| MiMo Code | ✅ Native | `mimo acp` | Native ACP |
| Oh My Pi | ✅ Native | `omp acp` | Native ACP |
| PI | ✅ Native | `pi acp` | ACP adapter |
| Cursor | ❌ | N/A | No ACP, uses internal SQLite |
| Aider | ❌ | N/A | No ACP |
| Goose | ❌ | N/A | No ACP |
| Gemini CLI | ⚠️ Partial | Telemetry only | No official ACP yet |

---

## 3. Existing Solutions in Market

### 3.1 Direct Competitors (Mobile Apps for AI Agent Control)

| App | Platform | Architecture | Agents Supported | Key Differentiator |
|-----|----------|--------------|------------------|-------------------|
| **Runmote** | Android (Flutter) | App → Relay → Daemon → ACP | OpenCode, Claude Code, Codex, Cursor, Copilot | Self-hostable relay, QR pairing, works over 4G |
| **OpenCode Mobile** | iOS/Android (Flutter) | Direct SSE + Relay | OpenCode only | Native opencode server protocol, worktrees |
| **Zedra** | iOS/Android | App ⇄ QUIC Tunnel ⇄ Daemon | Claude Code, Codex, OpenCode, Pi, Hermes | E2E encrypted QUIC, full dev workspace |
| **Happier** | Multi-device | App ↔ Relay ↔ Daemon | Claude Code, Codex, OpenCode, Pi | Cross-agent continuation, subagent spawning |
| **Cmd+Ctrl** | iOS/Android/Web | App ↔ API ↔ Daemons | Claude Code, Codex, Cursor, OpenCode, etc. | Per-agent daemon packages (npm) |
| **PocketCtl** | iOS/Web | App ↔ Hosted Relay | Codex, Claude Code, OpenCode, DeepSeek | Session sharing links, HTML/Markdown reports |
| **Homa** | iOS | SSH + Agent CLI | Codex, Claude Code, OpenCode | SSH/SFTP/Docker integration, AI command assistant |
| **Termopus** | Flutter | App ↔ Cloudflare DO ↔ Bridge | Claude Code | E2E encrypted via Cloudflare Durable Objects |
| **Ferlay (archived)** | Mobile | App ↔ Relay ↔ Daemon | Claude Code only | Replaced by native `claude remote-control` |
| **PiPilot** | Android | App ↔ Source Hub ↔ Pi TUI | Pi agent | Multi-session, session tree navigation |
| **Harness Remote** | Android/Web/Desktop | App ↔ Gateway ↔ ACP | Codex, Claude, Copilot, OpenCode, DeepSeek, Pi | Native sessions, cross-agent/machine continuation |
| **Claude Remote Control** | iOS/Android/Web | App ↔ Claude Cloud ↔ Local | Claude Code only | Official Anthropic solution, requires Pro+ plan |

### 3.2 SSH/Tmux-Based Solutions
| App | Platform | Approach |
|-----|----------|----------|
| **MonkeySSH** | iOS/Android (Flutter) | Full SSH client + tmux/MonkeyMux + agent launch presets |
| **Kammel** | Android/Linux (Flutter) | SSH + SFTP + terminal + editor, agent log viewing |
| **ForgeMind** | Android | SSH + Cloudflare Zero Trust tunnels + MCP client |
| **WorkFromPhone** | Cross-platform | FastAPI backend + Flutter client, PTY terminals |

### 3.3 Desktop/Session Manager Tools (Not Mobile)
| Tool | Type | Agents | Key Feature |
|------|------|--------|-------------|
| **ai-session-manager** | Web (Vite/React) | 9+ agents | Local file reading, resume commands, browser UI |
| **baton** | CLI (Node) | 8+ agents | Format conversion between agents |
| **sess** | CLI (Python) | 5 agents | Markdown brief export/import for context transfer |
| **cue** | CLI (Go) | 4 agents | Unified CLI wrapper, session list/history |
| **partyline** | Terminal | 4+ agents | tmux-based, session discovery across worktrees |
| **Motif** | Rust + Flutter | Codex | PTY pool, git, file ops, mirrored sessions |

---

## 4. Architecture Patterns

### 4.1 Three-Tier Architecture (Most Common)
```
Mobile App (Flutter) ←→ Relay Server ←→ Desktop Daemon ←→ AI Agent (ACP/CLI)
```
- **Mobile**: UI, session list, chat, approvals, terminal
- **Relay**: Connection brokering, NAT traversal, session metadata
- **Daemon**: Agent process management, ACP communication, file system access

### 4.2 Direct Connection (LAN/Tailscale)
```
Mobile App ←→ WebSocket/HTTP → Desktop Daemon (with embedded ACP)
```
- No relay needed on same network
- mDNS for discovery
- TLS for encryption

### 4.3 SSH/Tmux Bridge
```
Mobile App ←→ SSH → tmux/MonkeyMux → AI Agent CLI
```
- Traditional terminal approach
- Session persistence via tmux
- No agent-specific protocol needed

---

## 5. Key Technical Components for Flutter Implementation

### 5.1 Dart/Flutter Packages Available
| Package | Purpose | Maturity |
|---------|---------|----------|
| `acpd` | ACP v1 SDK (complete schema, typed) | Production-ready |
| `acpd_io` | stdio transport for local agents | Production-ready |
| `acpd_http` | HTTP/SSE/WebSocket transport | Production-ready |
| `acpd_test` | Testing utilities | Production-ready |
| `dart_acp_sdk` | Alternative ACP SDK | Stable v1 |
| `xterm.dart` | Terminal emulator (mobile optimized) | 3.x, Flutter 3+ |
| `dartssh2` | SSH client for Dart | Used by Kammel |
| `drift` | Local SQLite database | Used by OpenCode Mobile |
| `flutter_rust_bridge` | FFI to Rust (for terminal core) | Used by Okena |

### 5.2 Required Mobile Capabilities
- **Background execution**: Foreground service for persistent connections
- **Push notifications**: FCM for session alerts (completion, approval needed)
- **Biometric auth**: Android Keystore for credentials
- **QR code scanning**: For pairing
- **File system access**: For local session cache (if reading directly)
- **Network**: WebSocket, HTTP/2, mDNS

---

## 6. Differentiation Opportunities

### 6.1 Unique Value Propositions

| Opportunity | Description | Feasibility |
|-------------|-------------|-------------|
| **Universal Local Session Discovery** | Read all agent session files directly (no daemon needed for read-only) | High - parsers exist |
| **Cross-Agent Session Continuation** | Export session from Claude → Import to Codex → Continue seamlessly | Medium - needs format conversion |
| **Offline-First with Sync** | Local SQLite cache, sync when online | High - drift/sqlite |
| **Multi-Agent Dashboard** | Single view of all sessions across all agents on all machines | High - unified data model |
| **Session Brief Export** | Generate markdown briefs (like `sess` tool) for context transfer | Medium - LLM-assisted or heuristic |
| **Agent-Agnostic Terminal** | xterm.dart + PTY over WebSocket for any agent | High - xterm.dart exists |
| **Self-Hosted Relay Option** | Docker-compose relay like Runmote | Medium - relay is simple |
| **MCP Server Management from Mobile** | Add/configure MCP servers without editing desktop config | High - ACP supports this |
| **Git Worktree Visualization** | Show parallel agents in worktrees (like OpenCode Mobile) | Medium - needs git integration |

### 6.2 Gaps in Current Market
1. **No truly agent-agnostic mobile app** - Most tied to specific agent or protocol
2. **No local-only mode** - All require daemon/relay even for reading history
3. **No cross-agent context transfer** - Can't move session from Claude to Codex on mobile
4. **No unified session search** - Can't search across all agents' history at once
5. **Limited terminal support** - Most are chat-only, not full terminal
6. **No session comparison** - Can't diff two sessions side-by-side
7. **Poor offline story** - Most need constant connection

---

## 7. Recommended Approach for This Project

### 7.1 Phase 1: Local Session Browser (Read-Only)
- Parse local session files from all supported agents
- Unified session list with filtering/search
- Session detail view with message history
- Export session briefs (markdown)
- **No network required** - runs entirely on device with file access

### 7.2 Phase 2: Remote Control via ACP
- Implement ACP client using `acpd` + `acpd_http`
- Connect to desktop daemon over LAN/Tailscale
- Real-time session streaming, approvals, terminal
- QR code pairing for easy setup

### 7.3 Phase 3: Advanced Features
- Cross-agent session conversion (using baton/sess logic)
- Self-hosted relay for internet access
- Push notifications via FCM
- Multi-machine dashboard
- MCP server management

---

## 8. Technical Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Agent format changes | Session parsing breaks | Version detection, graceful degradation, adapter pattern |
| ACP protocol evolution | Incompatibility | Pin to ACP v1 stable, monitor v2 draft |
| Background execution limits | Connection drops | Foreground service, proper lifecycle management |
| Large session files | Memory/performance | Streaming parsers, pagination, caching |
| Security (session data) | Data exposure | Local encryption, no cloud sync by default |
| Android version fragmentation | Compatibility issues | Min SDK 24 (Android 7.0), test on emulators |

---

## 9. References & Sources

- [Agent Client Protocol Specification](https://agentclientprotocol.com/protocol/v1/overview)
- [OpenCode ACP Documentation](https://opencode.ai/docs/cli/acp/)
- [Runmote Architecture](https://runmote.dev/)
- [ai-session-manager GitHub](https://github.com/daniel-farina/ai-session-manager)
- [baton GitHub](https://github.com/Kaseban/baton)
- [sess PyPI](https://pypi.org/project/sess/)
- [Harness Remote GitHub](https://github.com/giuliastro/harness-remote)
- [xterm.dart GitHub](https://github.com/TerminalStudio/xterm.dart)
- [acpd Dart packages](https://pub.dev/packages/acpd)
- [Session Store Formats](https://agentarchaeology.ai/field-guide/session-stores/)
- [Five Coding Agents Comparison](https://dev.to/dspv/five-coding-agents-five-formats-one-table-5g7h)