import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

import '../state/mesh_app_state.dart';

class FilesPage extends StatelessWidget {
  const FilesPage({required this.state, super.key});

  final MeshAppState state;

  @override
  Widget build(final BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${state.selfId} files'),
      actions: [
        IconButton(
          tooltip: 'Back to pairing',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.qr_code),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: state.syncing ? null : state.sync,
      icon: state.syncing
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
      label: Text(state.syncing ? 'Syncing' : 'Sync now'),
    ),
    body: ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        if (state.files.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: [
                Text(state.status),
                FilledButton(
                  onPressed: () => _createFile(context),
                  child: const Text('Create local file'),
                ),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            for (final file in state.files)
              ListTile(
                title: Text(file.name),
                subtitle: Text(state.status),
                onTap: () => _showFile(context, file),
              ),
          ],
        );
      },
    ),
  );

  Future<void> _createFile(final BuildContext context) async {
    final pathController = TextEditingController(text: 'notes/demo.json');
    final contentController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create local file'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pathController,
              decoration: const InputDecoration(labelText: 'Path'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Content'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await state.createFile(
                pathController.text,
                contentController.text,
              );
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFile(
    final BuildContext context,
    final FileEntry file,
  ) async {
    final content = await state.readFile(file);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.name),
        content: SelectableText(content ?? '(missing)'),
        actions: [
          FilledButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
