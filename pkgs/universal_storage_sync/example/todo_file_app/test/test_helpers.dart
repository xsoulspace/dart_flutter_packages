import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_app/state/app_state.dart';

/// Creates a test widget with necessary providers and material app wrapper
Widget createTestWidget({
  required Widget child,
  AppState? appState,
}) {
  return ChangeNotifierProvider(
    create: (_) => appState ?? AppState(),
    child: MaterialApp(
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

/// Creates a mock AppState for testing
class MockAppState extends AppState {
  @override
  bool get hasWorkspace => true;

  @override
  String? get workspacePath => '/test/workspace';

  @override
  bool get busy => false;

  @override
  String? get error => null;
}
