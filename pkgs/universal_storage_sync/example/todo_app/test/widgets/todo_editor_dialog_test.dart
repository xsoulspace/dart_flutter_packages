import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/todo.dart';
import 'package:todo_app/widgets/todo_editor_dialog.dart';

import '../test_helpers.dart';

void main() {
  group('TodoEditorDialog', () {
    testWidgets('shows correct title for new todo', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const AlertDialog(
            title: Text('New Todo'),
            content: TodoEditorDialog(),
          ),
        ),
      );

      expect(find.text('New Todo'), findsOneWidget);
    });

    testWidgets('shows correct title for editing todo', (tester) async {
      final todo = Todo.create(
        id: const TodoId('test-id'),
        title: 'Test Todo',
      );

      await tester.pumpWidget(
        createTestWidget(
          child: AlertDialog(
            title: const Text('Edit Todo'),
            content: TodoEditorDialog(todo: todo),
          ),
        ),
      );

      expect(find.text('Edit Todo'), findsOneWidget);
    });

    testWidgets('populates fields when editing existing todo', (tester) async {
      final todo = Todo.create(
        id: const TodoId('test-id'),
        title: 'Test Todo',
        description: 'Test Description',
        tags: ['tag1', 'tag2'],
      );

      await tester.pumpWidget(
        createTestWidget(
          child: TodoEditorDialog(todo: todo),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Test Todo'), findsOneWidget);
      expect(find.text('Test Description'), findsOneWidget);
      expect(find.text('tag1, tag2'), findsOneWidget);
    });

    testWidgets('validates required title field', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const TodoEditorDialog(),
        ),
      );

      await tester.pumpAndSettle();

      // Try to submit without title
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Title is required'), findsOneWidget);
    });

    testWidgets('allows submission with valid title', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const TodoEditorDialog(),
        ),
      );

      await tester.pumpAndSettle();

      // Enter title
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter todo title'),
        'New Todo Title',
      );

      // Submit form
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Should not show validation error
      expect(find.text('Title is required'), findsNothing);
    });

    testWidgets('shows Update button when editing', (tester) async {
      final todo = Todo.create(
        id: const TodoId('test-id'),
        title: 'Test Todo',
      );

      await tester.pumpWidget(
        createTestWidget(
          child: TodoEditorDialog(todo: todo),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Create'), findsNothing);
    });

    testWidgets('shows Create button when creating new todo', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const TodoEditorDialog(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Update'), findsNothing);
    });
  });
}
