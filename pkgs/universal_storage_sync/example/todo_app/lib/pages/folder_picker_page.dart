import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// {@template folder_picker_page}
/// Page for selecting a workspace folder.
/// Shows welcome message and folder selection UI.
/// {@endtemplate}
class FolderPickerPage extends StatelessWidget {
  /// {@macro folder_picker_page}
  const FolderPickerPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Welcome header
            const Icon(Icons.folder_open, size: 96, color: Colors.blue),
            const SizedBox(height: 24),

            Text(
              'Welcome to Todo App',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            Text(
              'Select a folder to store your todos. Each todo will be saved as a separate YAML file.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Folder selection button
            Consumer<AppState>(
              builder: (context, appState, child) => Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: appState.busy
                        ? null
                        : () => _selectFolder(context),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Select Folder'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  ),

                  if (appState.busy) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('Setting up workspace...'),
                  ],

                  if (appState.error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        border: Border.all(color: Colors.red[200]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error, color: Colors.red[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              appState.error!,
                              style: TextStyle(color: Colors.red[700]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Help text
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Tips',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• The selected folder will be used to store your todo files\n'
                    '• Each todo is saved as a separate YAML file\n'
                    '• The app will remember your folder selection',
                    style: TextStyle(color: Colors.blue[700]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _selectFolder(BuildContext context) async {
    try {
      final directoryPath = await getDirectoryPath();
      if (directoryPath != null && context.mounted) {
        await context.read<AppState>().setWorkspacePath(directoryPath);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select folder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
