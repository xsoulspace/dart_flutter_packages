import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_storage_sync_utils/universal_storage_sync_utils.dart';

import '../state/app_state.dart';
import 'todo_list_page.dart';

/// {@template folder_picker_page}
/// Page for selecting a workspace folder.
/// Shows welcome message and folder selection UI.
/// {@endtemplate}
class FolderPickerPage extends StatefulWidget {
  /// {@macro folder_picker_page}
  const FolderPickerPage({super.key});

  @override
  State<FolderPickerPage> createState() => _FolderPickerPageState();
}

class _FolderPickerPageState extends State<FolderPickerPage> {
  bool _isPicking = false;

  Future<void> _pickAndSetWorkspace() async {
    setState(() => _isPicking = true);

    final AppState appState = context.read<AppState>();
    final PickResult result = await pickWritableDirectory(context: context);

    if (!mounted) return;

    switch (result) {
      case PickSuccess(:final path, :final macOSBookmark):
        await appState.setWorkspacePath(path, macOSBookmark: macOSBookmark);

        // Navigate to the main app screen after setting the path
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const TodoListPage()),
          );
        }
        break;
      case PickFailure(reason: final FailureReason reason):
        _showErrorDialog(reason.name);
        break;
      case PickCancelled():
        // User cancelled, do nothing.
        break;
    }

    setState(() => _isPicking = false);
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text('Could not select directory: $message'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Storage Folder'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Please select a folder to store your To-Do list.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isPicking ? null : _pickAndSetWorkspace,
              child: _isPicking
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Select Folder'),
            ),
          ],
        ),
      ),
    );
  }
}
