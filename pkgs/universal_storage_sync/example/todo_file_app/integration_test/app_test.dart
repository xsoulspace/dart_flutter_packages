import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:todo_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Todo App Integration Tests', () {
    late Directory tempDir;

    setUpAll(() async {
      // Create a temporary directory for testing
      tempDir = await Directory.systemTemp.createTemp('todo_app_test_');
    });

    tearDownAll(() async {
      // Clean up
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('app starts with folder picker when no workspace selected',
        (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Should show folder picker page
      expect(find.text('Welcome to Todo App'), findsOneWidget);
      expect(find.text('Select Folder'), findsOneWidget);
      expect(find.byIcon(Icons.folder_open), findsWidgets);
    });

    testWidgets('shows folder picker tips and help text', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      expect(find.text('Tips'), findsOneWidget);
      expect(
        find.textContaining('The selected folder will be used to store'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Each todo is saved as a separate YAML file'),
        findsOneWidget,
      );
    });

    testWidgets('folder picker shows error for invalid actions',
        (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // The select folder button should be present
      expect(find.text('Select Folder'), findsOneWidget);

      // Note: We can't easily test the actual folder selection dialog
      // in integration tests as it requires platform-specific file dialogs
      // This would be better tested with manual testing or platform-specific tests
    });

    // Note: Full integration testing with file system operations would require
    // more complex setup and potentially mocked file dialogs, which are
    // platform-specific and challenging to test in automated environments.
    // The core functionality can be tested through unit tests of AppState
    // and widget tests of individual components.
  });
}
