import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_file_app/state/app_state.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

/// Creates a test widget with necessary providers and material app wrapper
Widget createTestWidget({
  required final Widget child,
  final AppState? appState,
}) => ChangeNotifierProvider(
  create: (_) => appState ?? AppState(),
  child: MaterialApp(home: Scaffold(body: child)),
);

/// Creates a mock AppState for testing
class MockAppState extends AppState {
  @override
  bool get hasWorkspace => true;
  @override
  FilePathConfig get filePathConfig => FilePathConfig.create(
    macOSBookmarkData: const MacOSBookmark(''),
    path: '/test/workspace',
  );

  @override
  bool get busy => false;

  @override
  String? get error => null;
}
