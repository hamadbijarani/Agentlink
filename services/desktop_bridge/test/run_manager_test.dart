import 'package:agentlink_desktop_bridge/src/models.dart';
import 'package:agentlink_desktop_bridge/src/session_manager.dart';
import 'package:test/test.dart';

void main() {
  test('passes prompts as direct arguments instead of shell text', () {
    const prompt = 'Fix tests; rm -rf / should stay plain text';
    final command = commandFor(
      provider: AgentProvider.opencode,
      prompt: prompt,
    );

    expect(command.executable, 'opencode');
    expect(command.arguments.last, prompt);
    expect(command.arguments, containsAllInOrder(['--prompt']));
  });

  test('builds interactive resume commands for each provider', () {
    expect(
      commandFor(
        provider: AgentProvider.claude,
        resumeSessionId: 'abc-123',
      ).arguments,
      containsAllInOrder(['--resume', 'abc-123']),
    );
    expect(
      commandFor(
        provider: AgentProvider.opencode,
        resumeSessionId: 'ses_123',
      ).arguments,
      containsAllInOrder(['--session', 'ses_123']),
    );
    expect(
      commandFor(
        provider: AgentProvider.codex,
        resumeSessionId: '019a-xyz',
      ).arguments,
      containsAllInOrder(['resume', '019a-xyz']),
    );
    expect(
      commandFor(
        provider: AgentProvider.gemini,
        prompt: 'hello',
      ).arguments,
      containsAllInOrder(['-i', 'hello']),
    );
  });

  test('strips ANSI control sequences from mirrored output', () {
    const raw = '\u001B[31mred\u001B[0m\r\nplain\u001B[2K text';
    expect(stripAnsi(raw), contains('red'));
    expect(stripAnsi(raw), contains('plain'));
    expect(stripAnsi(raw), isNot(contains('\u001B')));
    expect(stripAnsi(raw), isNot(contains('\r')));
  });
}
