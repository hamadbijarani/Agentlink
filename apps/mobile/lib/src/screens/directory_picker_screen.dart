import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import '../widgets/empty_state.dart';

final class DirectoryPickerScreen extends StatefulWidget {
  const DirectoryPickerScreen({
    super.key,
    required this.controller,
    this.initialPath,
  });

  final AppController controller;
  final String? initialPath;

  @override
  State<DirectoryPickerScreen> createState() => _DirectoryPickerScreenState();
}

class _DirectoryPickerScreenState extends State<DirectoryPickerScreen> {
  List<FsRoot> _roots = const [];
  FsListing? _listing;
  String? _error;
  var _loading = true;
  var _showHidden = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final roots = await widget.controller.fsRoots();
      if (!mounted) return;
      setState(() => _roots = roots);
      final initial = widget.initialPath?.trim() ?? '';
      final path = initial.isNotEmpty
          ? initial
          : roots.isNotEmpty
          ? roots.first.path
          : '';
      await _load(path);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _load(String path) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await widget.controller.fsList(
        path,
        showHidden: _showHidden,
      );
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _toggleHidden() async {
    setState(() => _showHidden = !_showHidden);
    final path = _listing?.path ?? '';
    if (path.isNotEmpty) await _load(path);
  }

  Future<void> _newFolder() async {
    final listing = _listing;
    if (listing == null) return;
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    if (name.contains('/') || name.contains('\\')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use a single folder name.')),
      );
      return;
    }
    final separator = listing.path.contains('\\') ? '\\' : '/';
    final base = listing.path.endsWith(separator)
        ? listing.path.substring(0, listing.path.length - 1)
        : listing.path;
    try {
      final entry = await widget.controller.fsMkdir('$base$separator$name');
      if (!mounted) return;
      await _load(entry.path);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose folder'),
        actions: [
          IconButton(
            tooltip: _showHidden ? 'Hide hidden folders' : 'Show hidden folders',
            onPressed: _toggleHidden,
            icon: Icon(
              _showHidden ? Icons.visibility_off : Icons.visibility_outlined,
            ),
          ),
          IconButton(
            tooltip: 'New folder',
            onPressed: listing == null ? null : _newFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: listing == null ? null : () => _load(listing.path),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_roots.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _roots.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final root = _roots[index];
                  final selected =
                      listing != null && listing.path == root.path;
                  return ChoiceChip(
                    selected: selected,
                    label: Text(root.label),
                    avatar: Icon(
                      switch (root.kind) {
                        'home' => Icons.home_outlined,
                        'filesystem' => Icons.storage_outlined,
                        'drive' => Icons.storage,
                        'desktop' => Icons.desktop_windows_outlined,
                        'documents' => Icons.description_outlined,
                        'downloads' => Icons.download_outlined,
                        _ => Icons.folder_outlined,
                      },
                      size: 16,
                    ),
                    onSelected: (_) => _load(root.path),
                  );
                },
              ),
            ),
          if (listing != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Parent folder',
                    onPressed: listing.parent == null
                        ? null
                        : () => _load(listing.parent!),
                    icon: const Icon(Icons.arrow_upward, size: 18),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        listing.path,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _ErrorView(
                    message: _error!,
                    onRetry: listing == null
                        ? _initialize
                        : () => _load(listing.path),
                  )
                : listing == null
                ? const SizedBox.shrink()
                : _DirectoryList(
                    listing: listing,
                    onOpen: _load,
                  ),
          ),
        ],
      ),
      bottomNavigationBar: listing == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      listing.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, listing.path),
                    icon: const Icon(Icons.check),
                    label: const Text('Use folder'),
                  ),
                ],
              ),
            ),
    );
  }
}

final class _DirectoryList extends StatelessWidget {
  const _DirectoryList({required this.listing, required this.onOpen});

  final FsListing listing;
  final Future<void> Function(String path) onOpen;

  @override
  Widget build(BuildContext context) {
    final folders = listing.entries
        .where((entry) => entry.isDirectory)
        .toList();
    if (folders.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_open,
        title: 'No subfolders',
        message:
            'This folder has no subfolders. You can still choose it and start '
            'an agent here.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => onOpen(listing.path),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: folders.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final folder = folders[index];
          return ListTile(
            leading: Icon(
              folder.isLink ? Icons.link : Icons.folder_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(folder.name),
            subtitle: folder.isLink
                ? const Text('Symbolic link')
                : Text(
                    folder.modifiedAt == null
                        ? ''
                        : _modified(folder.modifiedAt!),
                  ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpen(folder.path),
          );
        },
      ),
    );
  }

  String _modified(DateTime time) {
    final local = time.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

final class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_off_outlined, size: 44),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => onRetry(), child: const Text('Retry')),
        ],
      ),
    ),
  );
}
