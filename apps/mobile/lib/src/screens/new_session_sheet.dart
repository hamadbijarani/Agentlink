import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import 'directory_picker_screen.dart';

final class NewSessionSheet extends StatefulWidget {
  const NewSessionSheet({
    super.key,
    required this.controller,
    this.initialProvider,
    this.initialCwd,
    this.initialResumeId,
    this.initialPrompt,
  });

  final AppController controller;
  final AgentProvider? initialProvider;
  final String? initialCwd;
  final String? initialResumeId;
  final String? initialPrompt;

  @override
  State<NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<NewSessionSheet> {
  late AgentProvider _provider;
  late final TextEditingController _cwdController;
  late final TextEditingController _promptController;
  late final TextEditingController _modelController;
  late final TextEditingController _extraArgsController;
  late final TextEditingController _titleController;
  late final TextEditingController _resumeController;
  late bool _openOnDesktop;
  var _starting = false;
  String _permissionMode = 'default';
  String? _error;

  @override
  void initState() {
    super.initState();
    _provider =
        widget.initialProvider ??
        widget.controller.providers
            .where((item) => item.available)
            .map((item) => item.provider)
            .firstOrNull ??
        AgentProvider.opencode;
    _cwdController = TextEditingController(text: widget.initialCwd ?? '');
    _promptController = TextEditingController(
      text: widget.initialPrompt ?? '',
    );
    _modelController = TextEditingController();
    _extraArgsController = TextEditingController();
    _titleController = TextEditingController();
    _resumeController = TextEditingController(
      text: widget.initialResumeId ?? '',
    );
    _openOnDesktop =
        widget.controller.info?.openDesktopByDefault ?? true;
    widget.controller.selectThemeProvider(_provider);
    if (_cwdController.text.trim().isEmpty) _loadDefaultDirectory();
  }

  Future<void> _loadDefaultDirectory() async {
    try {
      final roots = await widget.controller.fsRoots();
      if (!mounted || _cwdController.text.trim().isNotEmpty) return;
      final home = roots.where((root) => root.kind == 'home').firstOrNull;
      final path = home?.path ?? roots.firstOrNull?.path;
      if (path != null && path.isNotEmpty) {
        setState(() => _cwdController.text = path);
      }
    } on Object {
      // The directory picker still works if the PC is temporarily busy.
    }
  }

  @override
  void dispose() {
    _cwdController.dispose();
    _promptController.dispose();
    _modelController.dispose();
    _extraArgsController.dispose();
    _titleController.dispose();
    _resumeController.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => DirectoryPickerScreen(
          controller: widget.controller,
          initialPath: _cwdController.text.trim().isEmpty
              ? null
              : _cwdController.text.trim(),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _cwdController.text = selected);
    }
  }

  List<String> _permissionArgs() {
    if (_permissionMode == 'default') return const [];
    if (_provider == AgentProvider.claude) {
      return ['--permission-mode', _permissionMode];
    }
    if (_provider == AgentProvider.opencode && _permissionMode == 'auto') {
      return ['--auto'];
    }
    if (_provider == AgentProvider.codex && _permissionMode == 'auto') {
      return ['--full-auto'];
    }
    return const [];
  }

  Future<void> _start() async {
    FocusScope.of(context).unfocus();
    final info = widget.controller.providerInfo(_provider);
    if (info != null && !info.available) {
      setState(() => _error = '${info.label} is not installed on the PC.');
      return;
    }
    if (_cwdController.text.trim().isEmpty) {
      setState(() => _error = 'Choose a working directory on the PC.');
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final session = await widget.controller.startSession(
        provider: _provider,
        cwd: _cwdController.text.trim(),
        prompt: _promptController.text.trim(),
        title: _titleController.text.trim(),
        resumeSessionId: _resumeController.text.trim(),
        model: _modelController.text.trim(),
        extraArgs: [
          ..._permissionArgs(),
          ..._extraArgsController.text
              .trim()
              .split(RegExp(r'\s+'))
              .where((item) => item.isNotEmpty),
        ],
        openOnDesktop: _openOnDesktop,
      );
      if (!mounted) return;
      Navigator.of(context).pop(session);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.controller.providerInfo(_provider);
    final canResume = info?.canResume ?? false;
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New agent session',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Runs a real CLI on the PC',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Label('AGENT'),
                    const SizedBox(height: 8),
                    _ProviderSelector(
                      controller: widget.controller,
                      selected: _provider,
                      onSelected: (provider) {
                        setState(() => _provider = provider);
                        widget.controller.selectThemeProvider(provider);
                      },
                    ),
                    const SizedBox(height: 20),
                    const _Label('WORKING DIRECTORY'),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _browse,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.folder_open,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _cwdController.text.trim().isEmpty
                                    ? 'Browse folders on the PC'
                                    : _cwdController.text.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _Label('INITIAL PROMPT · OPTIONAL'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _promptController,
                      minLines: 3,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText:
                            'Leave empty to open the interactive CLI with no '
                            'prompt.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _Label('MODEL · OPTIONAL'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _modelController,
                      decoration: const InputDecoration(
                        hintText: 'Provider default (e.g. sonnet, gpt-5)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _Label('PERMISSION MODE'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _permissionMode,
                      items: const [
                        DropdownMenuItem(value: 'default', child: Text('Default')),
                        DropdownMenuItem(
                          value: 'acceptEdits',
                          child: Text('Accept edits'),
                        ),
                        DropdownMenuItem(value: 'auto', child: Text('Auto-approve')),
                        DropdownMenuItem(value: 'plan', child: Text('Plan only')),
                        DropdownMenuItem(value: 'dontAsk', child: Text('Don\'t ask')),
                        DropdownMenuItem(
                          value: 'bypassPermissions',
                          child: Text('Bypass permissions'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _permissionMode = value);
                      },
                      decoration: const InputDecoration(isDense: true),
                    ),
                    const SizedBox(height: 12),
                    const _Label('EXTRA CLI ARGS · OPTIONAL'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _extraArgsController,
                      decoration: const InputDecoration(
                        hintText: '--allowedTools Bash Edit, --auto, etc.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _Label('PROVIDER SHORTCUTS'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final shortcut in _shortcutsFor(_provider))
                          ActionChip(
                            label: Text(shortcut.label),
                            onPressed: () {
                              final current = _extraArgsController.text.trim();
                              final next = current.isEmpty
                                  ? shortcut.args
                                  : '$current ${shortcut.args}';
                              setState(() => _extraArgsController.text = next);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Options(
                      titleController: _titleController,
                      resumeController: _resumeController,
                      canResume: canResume,
                      openOnDesktop: _openOnDesktop,
                      onOpenOnDesktopChanged: (value) =>
                          setState(() => _openOnDesktop = value),
                      initiallyExpanded:
                          _resumeController.text.trim().isNotEmpty,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.error.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _starting ? null : _start,
                  icon: _starting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(
                    _starting
                        ? 'Starting on the PC…'
                        : 'Start ${info?.label ?? _provider.label}',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ProviderSelector extends StatelessWidget {
  const _ProviderSelector({
    required this.controller,
    required this.selected,
    required this.onSelected,
  });

  final AppController controller;
  final AgentProvider selected;
  final ValueChanged<AgentProvider> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final provider in AgentProvider.values)
              SizedBox(
                width: width,
                child: _ProviderTile(
                  provider: provider,
                  info: controller.providerInfo(provider),
                  selected: provider == selected,
                  onTap: () => onSelected(provider),
                ),
              ),
          ],
        );
      },
    );
  }
}

final class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.info,
    required this.selected,
    required this.onTap,
  });

  final AgentProvider provider;
  final ProviderInfo? info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = info?.available ?? false;
    final accent = info == null
        ? theme.colorScheme.primary
        : Color(colorValue(info!.theme.accent));
    final color = available ? accent : theme.colorScheme.outline;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: available ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.14)
              : theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.terminal, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    provider.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: available ? null : color,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, size: 16, color: color),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              available
                  ? (info?.version ?? 'Installed')
                  : info == null
                  ? 'Checking…'
                  : 'Not installed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _Options extends StatelessWidget {
  const _Options({
    required this.titleController,
    required this.resumeController,
    required this.canResume,
    required this.openOnDesktop,
    required this.onOpenOnDesktopChanged,
    required this.initiallyExpanded,
  });

  final TextEditingController titleController;
  final TextEditingController resumeController;
  final bool canResume;
  final bool openOnDesktop;
  final ValueChanged<bool> onOpenOnDesktopChanged;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text(
          'Options',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Title, resume id, desktop window',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Session title (optional)',
            ),
          ),
          if (canResume) ...[
            const SizedBox(height: 10),
            TextField(
              controller: resumeController,
              decoration: const InputDecoration(
                labelText: 'Resume session id (optional)',
                hintText: 'Provider session id',
              ),
            ),
          ],
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: openOnDesktop,
            onChanged: onOpenOnDesktopChanged,
            title: const Text(
              'Open a desktop terminal',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              'Show the real CLI on the PC when it starts',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      letterSpacing: 1.3,
      color: Theme.of(context).colorScheme.outline,
    ),
  );
}

final class _Shortcut {
  const _Shortcut(this.label, this.args);

  final String label;
  final String args;
}

List<_Shortcut> _shortcutsFor(AgentProvider provider) => switch (provider) {
  AgentProvider.claude => const [
    _Shortcut('Continue latest', '--continue'),
    _Shortcut('Bypass permissions', '--dangerously-skip-permissions'),
    _Shortcut('Accept edits', '--permission-mode acceptEdits'),
    _Shortcut('Plan mode', '--permission-mode plan'),
    _Shortcut('Chrome', '--chrome'),
    _Shortcut('Bare mode', '--bare'),
  ],
  AgentProvider.opencode => const [
    _Shortcut('Continue latest', '--continue'),
    _Shortcut('Auto approve', '--auto'),
    _Shortcut('Standalone', '--standalone'),
  ],
  AgentProvider.codex => const [
    _Shortcut('Full auto', '--full-auto'),
    _Shortcut('OSS provider', '--oss'),
    _Shortcut('Skip git check', '--skip-git-repo-check'),
  ],
  AgentProvider.gemini => const [
    _Shortcut('Sandbox', '--sandbox'),
  ],
};
