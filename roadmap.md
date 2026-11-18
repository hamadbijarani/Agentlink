# AgentLink Roadmap

## Phase 1 — Reliability and core mobile UX
1. Stabilize reconnect logic and offline states.
2. Keep only main agent output on mobile by default.
3. Prompt queue with manual and auto-send.
4. Restart ended sessions and history sessions.
5. Interactive fast scrollers across all views.
6. Better terminal rendering and copy/export.

## Phase 2 — Agent interaction and approvals
1. Structured permission approval cards.
2. Preview tool calls, shell commands, and file writes before approval.
3. Diff viewer for proposed changes.
4. Inline question and option selector.
5. Permission profiles: read-only, safe, full access.
6. Auto-approve trusted tools with user confirmation.

## Phase 3 — Voice and notifications
1. Voice-to-text prompts.
2. Text-to-speech replies.
3. Hands-free conversation mode.
4. Push notifications for approvals, idle, and completion.
5. Background session status monitoring.
6. Low-power/background execution handling.

## Phase 4 — Workspace and files
1. Remote file browser.
2. View and edit files from phone.
3. Git status, diff, commit, and branch tools.
4. Project and worktree selector.
5. Bookmarked/recent directories.
6. File upload and download.

## Phase 5 — Provider-specific features
1. Claude model, permission, agent, MCP, and directory options.
2. OpenCode provider/model/MCP/plugin/agent management.
3. Codex model, sandbox, review, fork, archive, and image support.
4. Gemini model and session discovery improvements.
5. Provider capability discovery from the CLI.

## Phase 6 — Administration and polish
1. Multiple saved PCs/servers.
2. Biometric unlock.
3. Device revoke/unpair management.
4. Bridge logs and diagnostics viewer.
5. Usage statistics and session analytics.
6. Localization, themes, and tablet layouts.

## Phase 7 — Collaboration and sharing
1. Shared read-only session view.
2. Temporary device access.
3. Session export/import.
4. Team workspace support.
5. Audit logs.

## Guiding principles
- Keep agent credentials and project files on the PC.
- Prefer direct process arguments over shell execution.
- Maintain one-phone-per-PC pairing by default.
- Support direct LAN, Tailscale, relay, and HTTPS modes.
- Keep mobile UI provider-driven from the bridge.