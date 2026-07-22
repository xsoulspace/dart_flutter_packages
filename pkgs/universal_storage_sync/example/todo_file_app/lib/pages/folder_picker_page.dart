import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_file_app/pages/todo_list_page.dart';
import 'package:todo_file_app/state/app_state.dart';
import 'package:universal_storage_sync_utils_flutter/universal_storage_sync_utils_flutter.dart';

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
      case final PickSuccess value:
        await appState.setWorkspacePath(value.config);

        // Navigate to the main app screen after setting the path
        if (mounted) {
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (final context) => const TodoListPage()),
          );
        }
      case PickFailure(reason: final FailureReason reason):
        _showErrorDialog(reason.name);
      case PickCancelled():
        // User cancelled, do nothing.
        break;
    }

    setState(() => _isPicking = false);
  }

  void _showErrorDialog(final String message) => showDialog(
    context: context,
    builder: (final context) => AlertDialog(
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

  @override
  Widget build(final BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Select Storage Folder')),
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
