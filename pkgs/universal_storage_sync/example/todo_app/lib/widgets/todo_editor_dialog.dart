import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/todo.dart';
import '../state/app_state.dart';

/// {@template todo_editor_dialog}
/// Dialog for creating and editing todos.
/// Shows form fields for title, description, and tags.
/// {@endtemplate}
class TodoEditorDialog extends StatefulWidget {
  /// {@macro todo_editor_dialog}
  const TodoEditorDialog({this.todo, super.key});

  /// Todo to edit, null for creating new todo
  final Todo? todo;

  @override
  State<TodoEditorDialog> createState() => _TodoEditorDialogState();
}

class _TodoEditorDialogState extends State<TodoEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _tagsController;

  bool get _isEditing => widget.todo != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.todo?.title ?? '');
    _descriptionController = TextEditingController(
      text: widget.todo?.description ?? '',
    );
    _tagsController = TextEditingController(
      text: widget.todo?.tags.join(', ') ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_isEditing ? 'Edit Todo' : 'New Todo'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title field
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Enter todo title',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Title is required';
                }
                return null;
              },
              autofocus: true,
            ),
            const SizedBox(height: 16),

            // Description field
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Enter todo description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              minLines: 3,
            ),
            const SizedBox(height: 16),

            // Tags field
            TextFormField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags',
                hintText: 'Enter tags separated by commas (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),

      Consumer<AppState>(
        builder: (context, appState, child) => ElevatedButton(
          onPressed: appState.busy ? null : _saveTodo,
          child: appState.busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEditing ? 'Update' : 'Create'),
        ),
      ),
    ],
  );

  Future<void> _saveTodo() async {
    if (!_formKey.currentState!.validate()) return;

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final tags = _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();

    try {
      if (_isEditing) {
        // Update existing todo
        final updatedTodo = widget.todo!.copyWith(
          title: title,
          description: description,
          tags: tags,
        );
        await context.read<AppState>().saveTodo(updatedTodo);
      } else {
        // Create new todo
        await context.read<AppState>().createTodo(
          title: title,
          description: description,
          tags: tags,
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save todo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
